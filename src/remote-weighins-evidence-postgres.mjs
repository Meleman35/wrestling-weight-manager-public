// Request-scoped privileged PostgreSQL adapter. Proof and retention policy are mandatory.
const deny=m=>{throw Error(m);};
const safe=x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,160}$/.test(x);
export function createRemotePostgresEvidenceStore({db,session,getActor,verifyCapture,expiresAtForCapture}) {
 if(![db?.query,db?.transaction,getActor,verifyCapture,expiresAtForCapture].every(f=>typeof f==='function'))deny('Trusted evidence database dependencies required');
 async function authorize(binding){
  const actor=await getActor(session);
  if(actor.userId!==binding.operatorId||actor.generation!==binding.generation)deny('Evidence session changed');
  const proof=await verifyCapture(session,binding);
  if(proof?.noticeAccepted!==true||proof.settled!==true||proof.source!=='camera')deny('Trusted capture proof required');
  return actor;
 }
 async function lockScope(tx,actor,b){
  if(!['captureId','programId','windowId','clubId','athleteId','operatorId','generation'].every(k=>safe(b[k]))||!['qr','nfc'].includes(b.method)||b.unit!=='lb'||!Number.isFinite(b.weight)||b.weight<=0||b.weight>800)deny('Invalid evidence binding');
  const program=(await tx.query(`select * from remote_reporting.programs where id=$1 and active and not coverage_revoked and covered_until>clock_timestamp() for update`,[b.programId])).rows[0];
  if(!program)deny('Coverage unavailable');
  const live=(await tx.query(`select u.id from auth.users u join auth.sessions s on s.user_id=u.id where u.id=$1::uuid and s.id=$2::uuid
   and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp())
   and (s.not_after is null or s.not_after>clock_timestamp()) for share of u,s`,[actor.userId,actor.sessionId])).rows;
  if(!live.length)deny('Session unavailable');
  const grant=(await tx.query(`select 1 from remote_reporting.assignments where program_id=$1 and user_id=$2::uuid and club_id=$3 and role='operator' and active for share`,[b.programId,actor.userId,b.clubId])).rows;
  if(!grant.length)deny('Operator unavailable');
  const club=(await tx.query('select 1 from remote_reporting.club_enrollments where program_id=$1 and club_id=$2 and active for share',[b.programId,b.clubId])).rows;
  if(!club.length)deny('Club unavailable');
  const window=(await tx.query(`select * from remote_reporting.windows where program_id=$1 and id=$2 and active
   and $3::timestamptz>=opens_at and $4::timestamptz<closes_at and $4::timestamptz>=$3::timestamptz
   and $4::timestamptz-$3::timestamptz<=interval '30 seconds' and $4::timestamptz<=clock_timestamp()
   and clock_timestamp()<=closes_at+sync_grace_ms*interval '1 millisecond' for share`,[b.programId,b.windowId,b.capturedAt,b.photoCapturedAt])).rows[0];
  if(!window||(program.kind==='tournament'&&window.event_id!==program.event_id))deny('Capture window unavailable');
  const roster=(await tx.query('select 1 from remote_reporting.roster where program_id=$1 and window_id=$2 and club_id=$3 and athlete_id=$4 and active and remote_consent for share',[b.programId,b.windowId,b.clubId,b.athleteId])).rows;
  if(!roster.length)deny('Roster consent unavailable');
 }
 const project=r=>r?{evidenceId:r.id,binding:r.binding,path:r.private_object_key,digest:r.digest,byteCount:Number(r.byte_count),confirmed:r.verified,revoked:r.revoked,expiresAt:new Date(r.expires_at).toISOString()}:null;
 return Object.freeze({
  async find(evidenceId){return project((await db.query('select * from remote_reporting.evidence where id=$1',[evidenceId])).rows[0]);},
  async reserve({evidenceId,binding,path,digest,byteCount}){
   if(!safe(evidenceId)||!/^([a-f0-9]{64})$/.test(digest)||!Number.isInteger(byteCount)||byteCount<1||byteCount>5*1024*1024||path!==`${binding.programId}/${binding.captureId}/${evidenceId}.jpg`)deny('Invalid evidence reservation');
   const actor=await authorize(binding),expiresAt=await expiresAtForCapture(binding);
   if(!Number.isFinite(Date.parse(expiresAt)))deny('Evidence retention policy required');
   return db.transaction(async tx=>{
    await lockScope(tx,actor,binding);
    const previous=(await tx.query('select * from remote_reporting.evidence where id=$1 for update',[evidenceId])).rows[0];
    if(previous){
     const equal=(await tx.query('select binding=$2::jsonb as same,expires_at>clock_timestamp() as live from remote_reporting.evidence where id=$1',[evidenceId,JSON.stringify(binding)])).rows[0];
     if(previous.revoked||!equal.live||!equal.same||previous.private_object_key!==path||previous.digest!==digest||Number(previous.byte_count)!==byteCount)deny('Evidence retry conflict');
     return project(previous);
    }
    const valid=(await tx.query('select $1::timestamptz>clock_timestamp() as valid',[expiresAt])).rows[0].valid;if(!valid)deny('Evidence retention expired');
    const row=(await tx.query(`insert into remote_reporting.evidence(id,program_id,binding,private_object_key,digest,verified,expires_at,notice_accepted,settled,source,byte_count)
     values($1,$2,$3::jsonb,$4,$5,false,$6::timestamptz,true,true,'camera',$7) returning *`,[evidenceId,binding.programId,JSON.stringify(binding),path,digest,expiresAt,byteCount])).rows[0];
    return project(row);
   });
  },
  async confirm({evidenceId,binding,digest,byteCount}){
   const actor=await authorize(binding);
   return db.transaction(async tx=>{
    await lockScope(tx,actor,binding);
    const r=(await tx.query(`update remote_reporting.evidence set verified=true where id=$1 and binding=$2::jsonb and digest=$3 and byte_count=$4 and not revoked and expires_at>clock_timestamp() returning *`,[evidenceId,JSON.stringify(binding),digest,byteCount])).rows[0];
    if(!r)deny('Evidence confirmation unavailable');return project(r);
   });
  },
  async revoke(evidenceId){return project((await db.query('update remote_reporting.evidence set revoked=true,verified=false where id=$1 returning *',[evidenceId])).rows[0]);}
 });
}
