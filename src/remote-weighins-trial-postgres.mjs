import {activateTrialTournament,trialTournamentEntitlement} from './remote-weighins-trial.mjs';
const id=x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,160}$/.test(x);
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const iso=x=>new Date(x).toISOString();
// authorizeOrganization must take the existing actor-deletion advisory lock and
// verify the live personal session and current organization director/admin rights.
export function createRemoteTrialPostgresStore({db,authorizeOrganization}) {
 if(![db?.query,db?.transaction,authorizeOrganization].every(f=>typeof f==='function'))throw Error('Trusted trial database adapters required');
 async function state(tx,organizationId){
  const trial=(await tx.query('select * from private.remote_director_trials where organization_id=$1 for share',[organizationId])).rows[0];if(!trial)return null;
  const events=(await tx.query('select event_id from private.remote_trial_tournaments where organization_id=$1 order by slot',[organizationId])).rows;
  return {organizationId,startedAt:iso(trial.started_at),expiresAt:iso(trial.expires_at),revoked:trial.revoked,tournamentIds:events.map(r=>r.event_id)};
 }
 async function clock(tx){return Number((await tx.query('select floor(extract(epoch from clock_timestamp())*1000)::bigint as time')).rows[0].time);}
 return Object.freeze({
  async activate(session,{organizationId,programId}){
   if(!uuid(organizationId)||!id(programId))throw Error('Canonical trial scope required');organizationId=organizationId.toLowerCase();
   return db.transaction(async tx=>{
    if(await authorizeOrganization({tx,session,organizationId,action:'activate_remote_trial'})!==true)throw Error('Organization trial activation denied');
    // Organization row exists before the first trial and serializes absent-row races.
    if(!(await tx.query('select id from public.organizations where id=$1 for update',[organizationId])).rows.length)throw Error('Organization unavailable');
    const program=(await tx.query(`select p.* from remote_reporting.programs p join private.remote_program_organizations o on o.program_id=p.id
     where p.id=$1 and o.organization_id=$2 and p.kind='tournament' and p.active for update of p`,[programId,organizationId])).rows[0];
    if(!program||!id(program.event_id))throw Error('Organization tournament unavailable');
    const prior=await state(tx,organizationId),next=activateTrialTournament({state:prior,organizationId,tournamentId:program.event_id,now:await clock(tx)});
    if(!prior)await tx.query('insert into private.remote_director_trials(organization_id,started_at,expires_at) values($1,$2,$3)',[organizationId,next.startedAt,next.expiresAt]);
    if(!prior?.tournamentIds.includes(program.event_id))await tx.query('insert into private.remote_trial_tournaments(organization_id,event_id,slot) values($1,$2,$3)',[organizationId,program.event_id,next.tournamentIds.length]);
    return {startedAt:next.startedAt,expiresAt:next.expiresAt,tournamentsUsed:next.tournamentIds.length,tournamentLimit:4,autoCharge:false};
   });
  },
  // Internal billing reader, never a client-facing trial lookup.
  async entitlement(programId){
   if(!id(programId))throw Error('Invalid reporting program');
   return db.transaction(async tx=>{
    const p=(await tx.query(`select p.*,o.organization_id from remote_reporting.programs p join private.remote_program_organizations o on o.program_id=p.id where p.id=$1 and p.active and p.kind='tournament'`,[programId])).rows[0];
    if(!p)return null;const trial=await state(tx,p.organization_id);if(!trial)return null;
    return trialTournamentEntitlement({state:trial,organizationId:p.organization_id,tournamentId:p.event_id,programId,now:await clock(tx)});
   });
  }
 });
}
