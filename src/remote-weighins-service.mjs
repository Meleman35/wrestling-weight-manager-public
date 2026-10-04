/* Server-only service contract. Not a deployed API. Every dependency below must
 * use trusted server data; atomicAccept must enforce database transactions. */
import {createHash} from 'node:crypto';
import {normalizeMemberships} from './remote-athlete-memberships.mjs';
import {validateWindow, summarizeWindow, reportCsv} from './remote-weighins.mjs';
const deny = message => { throw new Error(message); };
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
const timestamp = value => { const ms = Date.parse(value); if (!Number.isFinite(ms)) deny('Invalid timestamp'); return ms; };
const same = (a,b) => a && typeof a === 'object' && Object.keys(a).length === Object.keys(b).length && Object.keys(b).every(k=>a[k]===b[k]);
export function createRemoteReportingService({getActor, getProgram, getWindow, getWindows, getRoster, getEvidence, store, coverageGate, now=Date.now}) {
  if (![getActor,getProgram,getWindow,getRoster,getEvidence,store?.atomicAccept,store?.list,coverageGate?.read,coverageGate?.capture].every(x=>typeof x==='function')) deny('Trusted reporting adapters required');
  async function authority(session, programId, action, clubId=null) {
    const actor=await getActor(session), program=await getProgram(programId);
    if (!actor?.userId || actor.sessionActive!==true || actor.confirmed!==true || actor.personal!==true || actor.locked===true || actor.deleted===true) deny('Active personal session required');
    if (!program || program.id!==programId || program.active!==true || !['network','tournament'].includes(program.kind)) deny('Reporting program unavailable');
    if (program.covered!==true) deny('Qualifying reporting coverage required');
    if(await coverageGate.read({programId})!==true)deny('Separate network coverage required');
    if (action==='submit'&&await coverageGate.capture({programId,clubId})!==true)deny('Participating team coverage required');
    if (program.kind==='tournament' && !validId(program.eventId)) deny('Tournament event required');
    const grants=actor.reportingGrants?.filter(g=>g.programId===programId && g.active===true)||[];
    if (action==='submit') {
      if (!program.clubIds?.includes(clubId) || !grants.some(g=>g.role==='operator' && g.clubId===clubId)) deny('Club operator assignment required');
    } else if (!grants.some(g=>g.role==='director' || (g.role==='club_reader' && g.clubId===clubId))) deny('Reporting read assignment required');
    return {actor,program};
  }
  async function period(program, windowId) {
    const window=validateWindow(await getWindow(windowId));
    if (window.programId!==program.id || window.active!==true || (program.kind==='tournament' && window.eventId!==program.eventId)) deny('Reporting window does not belong to this program');
    if (!Number.isFinite(window.syncGraceMs) || window.syncGraceMs<0 || window.syncGraceMs>7*86400000) deny('Bounded sync grace required');
    return window;
  }
  return Object.freeze({
    async context(session) {
      if(typeof getWindows!=='function')deny('Reporting context unavailable');
      const actor=await getActor(session);
      if(!actor?.userId||actor.sessionActive!==true||actor.confirmed!==true||actor.personal!==true||actor.locked===true||actor.deleted===true)deny('Active personal session required');
      const scopes=[];
      const programs=[...new Set((actor.reportingGrants||[]).filter(g=>g.active===true).map(g=>g.programId))];
      for(const programId of programs){
        const program=await getProgram(programId);
        if(!program?.active||program.covered!==true||!['network','tournament'].includes(program.kind))continue;
        try{if(await coverageGate.read({programId})!==true)continue;}catch{continue;}
        if(program.kind==='tournament'&&!validId(program.eventId))continue;
        const windows=await getWindows(programId);
        const periods=[];
        for(const candidate of windows){const w=await period(program,candidate.id);periods.push({id:w.id,programId:w.programId,timeZone:w.timeZone,opensAt:w.opensAt,closesAt:w.closesAt,lockedAt:w.lockedAt??null,label:`${w.id} · ${w.timeZone}`});}
        const grants=actor.reportingGrants.filter(g=>g.programId===programId&&g.active===true),clubs=new Map();
        if(grants.some(g=>g.role==='director'))scopes.push({programId,clubId:null,canCapture:false,label:`${programId} · All clubs`,windows:periods});
        for(const g of grants){if(['operator','club_reader'].includes(g.role)&&program.clubIds.includes(g.clubId))clubs.set(g.clubId,(clubs.get(g.clubId)||false)||g.role==='operator');}
        for(const [clubId,assignedCapture] of clubs){let canCapture=false;if(assignedCapture){try{canCapture=await coverageGate.capture({programId,clubId})===true;}catch{}}scopes.push({programId,clubId,canCapture,label:`${programId} · ${clubId}`,windows:periods});}
      }
      return {scopes,serverTime:new Date(now()).toISOString()};
    },
    // Eligibility preflight only; photo provenance still requires trusted capture proof.
    async authorizeCapture(session,input) {
      if(!input||!['programId','windowId','clubId','athleteId','operatorId','generation'].every(k=>validId(input[k])))deny('Invalid capture scope');
      const {actor,program}=await authority(session,input.programId,'submit',input.clubId);
      if(input.operatorId!==actor.userId||input.generation!==actor.generation)deny('Operator session changed');
      const window=await period(program,input.windowId);
      const serverTime=now(),opens=timestamp(window.opensAt),closes=timestamp(window.closesAt);
      if(input.capturedAt!==undefined||input.photoCapturedAt!==undefined){
        const captured=timestamp(input.capturedAt),photo=timestamp(input.photoCapturedAt);
        if(captured<opens||captured>=closes||photo<captured||photo>=closes||photo-captured>30000||photo>serverTime||captured+240*3600000<=serverTime)deny('Capture outside allotted reporting period');
      }else if(serverTime<opens||serverTime>=closes)deny('Allotted reporting period is closed');
      const roster=await getRoster(program.id,window.id,input.clubId);
      if(!roster.some(r=>r.clubId===input.clubId&&r.athleteId===input.athleteId&&r.active===true&&r.remoteConsent===true))deny('Roster consent unavailable');
      return true;
    },
    async submit(session,input) {
      if (!input || !['submissionId','captureId','programId','windowId','clubId','athleteId','operatorId','generation','evidenceId'].every(k=>validId(input[k]))) deny('Invalid submission identity');
      if (!['qr','nfc'].includes(input.method) || input.unit!=='lb' || !Number.isFinite(input.weight) || input.weight<=0 || input.weight>800) deny('Invalid scale capture');
      const {actor,program}=await authority(session,input.programId,'submit',input.clubId);
      if (input.operatorId!==actor.userId || input.generation!==actor.generation) deny('Operator session changed');
      const window=await period(program,input.windowId);
      const roster=await getRoster(program.id,window.id);
      if (!roster.some(r=>r.clubId===input.clubId && r.athleteId===input.athleteId && r.active===true && r.remoteConsent===true)) deny('Athlete is not enrolled with remote consent');
      const captured=timestamp(input.capturedAt),photo=timestamp(input.photoCapturedAt),received=now();
      if (captured<timestamp(window.opensAt) || photo>=timestamp(window.closesAt) || photo<captured || photo-captured>30000 || captured>received || photo>received) deny('Capture outside reporting window');
      // Evidence service must verify immutable capture metadata, account ownership,
      // notice/consent, upload digest, native provenance and settled scale binding.
      const evidence=await getEvidence(input.evidenceId);
      const binding={captureId:input.captureId,programId:program.id,windowId:window.id,clubId:input.clubId,athleteId:input.athleteId,operatorId:actor.userId,generation:actor.generation,weight:input.weight,unit:input.unit,capturedAt:input.capturedAt,photoCapturedAt:input.photoCapturedAt,method:input.method};
      if (!evidence || evidence.verified!==true || evidence.private!==true || evidence.noticeAccepted!==true || evidence.source!=='camera' || evidence.settled!==true || !validId(evidence.digest) || !same(evidence.binding,binding)) deny('Verified private capture evidence required');
      const canonical={submissionId:input.submissionId,evidenceId:input.evidenceId,...binding,eventId:program.kind==='tournament'?program.eventId:null,kind:program.kind,evidenceDigest:evidence.digest};
      const payloadHash=createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
      // The transaction must first return an identical prior receipt, even after
      // syncGrace expires; reject changed payloads and concurrent current records.
      // New acceptance after the grace deadline must be rejected inside the same
      // transaction. Revocation/coverage/session predicates must be rechecked there.
      return store.atomicAccept({actor,program,window,record:canonical,payloadHash,receivedAt:new Date(received).toISOString(),newAcceptanceAllowed:received<=timestamp(window.closesAt)+window.syncGraceMs});
    },
    async receipt(session,input) {
      if(!input||!['submissionId','programId','windowId','clubId','operatorId','generation'].every(k=>validId(input[k]))||typeof store.findSubmission!=='function'||typeof store.receipt!=='function')deny('Receipt unavailable');
      const {actor,program}=await authority(session,input.programId,'submit',input.clubId);
      if(input.operatorId!==actor.userId||input.generation!==actor.generation)deny('Operator session changed');
      const window=await period(program,input.windowId);
      const roster=await getRoster(program.id,window.id,input.clubId);
      if(!roster.some(r=>r.clubId===input.clubId&&r.athleteId===input.athleteId&&r.active===true&&r.remoteConsent===true))deny('Roster consent unavailable');
      const record=await store.findSubmission(input.submissionId);if(!record)return null;
      const keys=['submissionId','evidenceId','captureId','programId','windowId','clubId','athleteId','operatorId','generation','weight','unit','capturedAt','photoCapturedAt','method'];
      if(!keys.every(k=>input[k]===record[k]))deny('Idempotency conflict');
      return store.receipt(input.submissionId);
    },
    async evidenceForSubmission(session,{submissionId}) {
      if(!validId(submissionId)||typeof store.findSubmission!=='function')deny('Photo unavailable');
      const record=await store.findSubmission(submissionId);if(!record)deny('Photo unavailable');
      const {program}=await authority(session,record.programId,'read',record.clubId);
      const window=await period(program,record.windowId);
      const roster=await getRoster(program.id,window.id,record.clubId);
      if(!roster.some(r=>r.clubId===record.clubId&&r.athleteId===record.athleteId&&r.active===true&&r.remoteConsent===true))deny('Photo unavailable');
      return record.evidenceId;
    },
    async report(session,{programId,windowId,clubId=null,status=null,offset=0,limit=100,format='json'}) {
      if (!validId(programId)||!validId(windowId)||(clubId!==null&&!validId(clubId))||!Number.isInteger(offset)||offset<0||!Number.isInteger(limit)||limit<1||limit>500||!['json','csv'].includes(format)||!(status===null||['submitted','late','missing'].includes(status))) deny('Invalid report query');
      const {program}=await authority(session,programId,'read',clubId),window=await period(program,windowId);
      // Narrow query at storage/roster boundary; do not retrieve other clubs for a
      // club_reader then hide them only in the browser.
      const expected=(await getRoster(program.id,window.id,clubId)).filter(r=>r.active===true && r.remoteConsent===true && (!clubId||r.clubId===clubId));
      const submissions=await store.list({programId,windowId,clubId});
      const result=summarizeWindow({window,expected,submissions,clubId,status});
      const rows=result.rows.sort((a,b)=>String(a.clubName).localeCompare(String(b.clubName))||a.clubId.localeCompare(b.clubId)||String(a.athleteName).localeCompare(String(b.athleteName))||a.athleteId.localeCompare(b.athleteId));
      const page=rows.slice(offset,offset+limit),nextOffset=offset+page.length<rows.length?offset+page.length:null;
      // Explicit allowlist: never return evidence IDs, photo links, raw evidence,
      // account/session identifiers, arbitrary roster columns or medical records.
      const projected=page.map(r=>({clubId:r.clubId,athleteId:r.athleteId,clubName:r.clubName,athleteName:r.athleteName,...normalizeMemberships(r),status:r.status,submission:r.submission?{submissionId:r.submission.submissionId,receiptId:r.submission.receiptId,weight:r.submission.weight,unit:r.submission.unit,capturedAt:r.submission.capturedAt,receivedAt:r.submission.receivedAt}:null}));
      return {programId,windowId,kind:program.kind,eventId:program.kind==='tournament'?program.eventId:null,classification:program.kind==='tournament'?'Remote tournament check-in':'Remote club report',timeZone:window.timeZone,counts:result.counts,total:rows.length,nextOffset,rows:projected,...(format==='csv'?{csv:reportCsv(projected)}:{})};
    }
  });
}
