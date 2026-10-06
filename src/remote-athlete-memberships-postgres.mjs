import {normalizeMemberships} from './remote-athlete-memberships.mjs';
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
// authorize must verify live personal session and current athlete/guardian/coach
// rights INSIDE tx and take the existing actor deletion advisory lock (91347).
export function createAthleteMembershipPostgresStore({db,authorize}) {
 if(![db?.transaction,authorize].every(f=>typeof f==='function'))throw Error('Trusted transactional membership adapters required');
 const access=async(tx,session,athleteId,action)=>{if(!uuid(athleteId)||await authorize({tx,session,athleteId,action})!==true)throw Error('Athlete membership access denied');const r=(await tx.query('select profile_id from public.athletes where id=$1 for update',[athleteId])).rows[0];if(!r?.profile_id)throw Error('Canonical athlete profile required');return r.profile_id;};
 return Object.freeze({
  async read(session,athleteId){return db.transaction(async tx=>{const profile=await access(tx,session,athleteId,'read');const r=(await tx.query('select usaw_id as "usawId",aau_number as "aauNumber" from private.athlete_membership_identifiers where profile_id=$1',[profile])).rows[0];return normalizeMemberships(r??{});});},
  async write({session,athleteId,values}){const m=normalizeMemberships(values);return db.transaction(async tx=>{const profile=await access(tx,session,athleteId,'edit');await tx.query(`insert into private.athlete_membership_identifiers(profile_id,usaw_id,aau_number) values($1,$2,$3)
   on conflict(profile_id) do update set usaw_id=excluded.usaw_id,aau_number=excluded.aau_number,verification='unverified',updated_at=clock_timestamp()`,[profile,m.usawId,m.aauNumber]);});}
 });
}
// Called after remote service authority, with canonical active, consented roster.
export function createRosterMembershipResolver({db}) {
 if(typeof db?.query!=='function')throw Error('Trusted membership database required');
 return async pairs=>{
  if(!Array.isArray(pairs)||pairs.length>20000||pairs.some(r=>!uuid(r.clubId)||!uuid(r.athleteId)))throw Error('Canonical roster pairs required');
  if(!pairs.length)return [];
  return (await db.query(`with requested as(select distinct "clubId"::uuid as club_id,"athleteId"::uuid as athlete_id from jsonb_to_recordset($1::jsonb) r("clubId" text,"athleteId" text))
   select t.id::text as "clubId",a.id::text as "athleteId",m.usaw_id as "usawId",m.aau_number as "aauNumber"
   from requested r join public.teams t on t.id=r.club_id
   join public.athletes a on a.id=r.athlete_id and a.organization_id=t.organization_id
   join private.athlete_membership_identifiers m on m.profile_id=a.profile_id
   where exists(select 1 from public.roster_memberships rm join public.seasons s on s.id=rm.season_id where rm.athlete_id=a.id and rm.active and s.active and s.team_id=t.id)`,[JSON.stringify(pairs)])).rows;
 };
}
