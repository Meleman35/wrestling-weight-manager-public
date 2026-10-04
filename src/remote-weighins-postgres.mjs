// Server-only adapter for the private draft schema. No REST/client grants needed.
// db.query is a parameterized privileged server connection, never a browser client.
const fail=m=>{throw Error(m);};
const iso=x=>x==null?null:new Date(x).toISOString();
export function createRemotePostgresAdapters({db,verifyPersonalSession,resolveRosterNames}) {
 if(![db?.query,verifyPersonalSession,resolveRosterNames].every(f=>typeof f==='function'))fail('Trusted PostgreSQL dependencies required');
 const sessions=new WeakMap();
 async function getActor(session){
  const personal=await verifyPersonalSession(session);
  if(!personal?.userId||!personal.sessionId||!personal.generation||personal.personal!==true||personal.locked!==false||personal.deleted!==false)fail('Active personal session required');
  const live=await db.query(`select u.id from auth.users u join auth.sessions s on s.user_id=u.id
    where u.id=$1::uuid and s.id=$2::uuid and u.email_confirmed_at is not null and u.deleted_at is null
    and (u.banned_until is null or u.banned_until<=clock_timestamp()) and (s.not_after is null or s.not_after>clock_timestamp())`,[personal.userId,personal.sessionId]);
  if(live.rows.length!==1)fail('Active personal session required');
  const grants=await db.query('select program_id,club_id,role,active from remote_reporting.assignments where user_id=$1::uuid and active',[personal.userId]);
  const actor={userId:personal.userId,sessionId:personal.sessionId,generation:personal.generation,personal:true,locked:false,deleted:false,confirmed:true,sessionActive:true,
    reportingGrants:grants.rows.map(r=>({programId:r.program_id,clubId:r.club_id,role:r.role,active:r.active}))};
  sessions.set(actor,session);return actor;
 }
 async function getProgram(id){
  const result=await db.query(`select p.*,p.active and not p.coverage_revoked and p.covered_until>clock_timestamp() as covered,
    coalesce((select array_agg(c.club_id order by c.club_id) from remote_reporting.club_enrollments c where c.program_id=p.id and c.active),'{}') as club_ids
    from remote_reporting.programs p where p.id=$1`,[id]);
  const p=result.rows[0];return p?{id:p.id,kind:p.kind,eventId:p.event_id,active:p.active,covered:p.covered===true,clubIds:p.club_ids}:null;
 }
 async function getWindow(id){
  const r=(await db.query('select * from remote_reporting.windows where id=$1',[id])).rows[0];
  return r?{id:r.id,programId:r.program_id,eventId:r.event_id,opensAt:iso(r.opens_at),closesAt:iso(r.closes_at),timeZone:r.time_zone,syncGraceMs:Number(r.sync_grace_ms),active:r.active}:null;
 }
 async function getWindows(programId){
  const rows=(await db.query('select id from remote_reporting.windows where program_id=$1 and active order by closes_at desc,id limit 100',[programId])).rows;
  return Promise.all(rows.map(r=>getWindow(r.id)));
 }
 async function getRoster(programId,windowId,clubId=null){
  const result=await db.query(`select club_id,athlete_id,active,remote_consent from remote_reporting.roster
    where program_id=$1 and window_id=$2 and ($3::text is null or club_id=$3) order by club_id,athlete_id`,[programId,windowId,clubId]);
  const rows=result.rows.map(r=>({clubId:r.club_id,athleteId:r.athlete_id,active:r.active,remoteConsent:r.remote_consent}));
  const names=await resolveRosterNames(rows.map(r=>({clubId:r.clubId,athleteId:r.athleteId})));
  if(!Array.isArray(names))fail('Canonical roster names required');
  const map=new Map(names.map(r=>[JSON.stringify([r.clubId,r.athleteId]),r]));
  return rows.map(r=>{const n=map.get(JSON.stringify([r.clubId,r.athleteId]));if(!n||typeof n.clubName!=='string'||typeof n.athleteName!=='string')fail('Canonical roster names required');return {...r,clubName:n.clubName,athleteName:n.athleteName};});
 }
 async function getEvidence(id){
  const e=(await db.query(`select *,expires_at>clock_timestamp() as unexpired from remote_reporting.evidence where id=$1`,[id])).rows[0];
  return e?{id:e.id,binding:e.binding,digest:e.digest,verified:e.verified&&e.unexpired,private:true,noticeAccepted:e.notice_accepted,settled:e.settled,source:e.source}:null;
 }
 const store={
  async receipt(submissionId){
   const r=(await db.query('select submission_id,receipt_id,received_at from remote_reporting.submissions where submission_id=$1',[submissionId])).rows[0];
   return r?{submissionId:r.submission_id,receiptId:r.receipt_id,status:'submitted',receivedAt:iso(r.received_at)}:null;
  },
  async findSubmission(submissionId){
   const r=(await db.query('select record from remote_reporting.submissions where submission_id=$1',[submissionId])).rows[0];return r?.record??null;
  },
  async atomicAccept({actor,record,payloadHash}){
   const session=sessions.get(actor);if(!session)fail('Trusted acceptance actor required');
   const live=await getActor(session);
   if(live.userId!==actor.userId||live.sessionId!==actor.sessionId||live.generation!==actor.generation)fail('Operator session changed');
   // accept owns transaction locks, deadlines and retry/conflict semantics.
   const result=await db.query('select remote_reporting.accept($1::uuid,$2::uuid,$3::jsonb,$4::text) as receipt',[live.userId,live.sessionId,JSON.stringify(record),payloadHash]);
   const receipt=result.rows[0].receipt;
   return {submissionId:receipt.submissionId,receiptId:receipt.receiptId,status:receipt.status,receivedAt:iso(receipt.receivedAt)};
  },
  async list({programId,windowId,clubId=null}){
   const rows=(await db.query(`select record,receipt_id,received_at from remote_reporting.submissions
      where program_id=$1 and window_id=$2 and ($3::text is null or club_id=$3) order by club_id,athlete_id`,[programId,windowId,clubId])).rows;
   return rows.map(r=>({...r.record,receiptId:r.receipt_id,receivedAt:iso(r.received_at),status:'submitted'}));
  }
 };
 return Object.freeze({getActor,getProgram,getWindow,getWindows,getRoster,getEvidence,store});
}
