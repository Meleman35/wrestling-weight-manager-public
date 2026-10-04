// Privileged server-only canonical name resolver. Call only after remote authority.
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
export function createCanonicalRemoteRosterResolver({db}) {
 if(typeof db?.query!=='function')throw Error('Trusted roster database required');
 return async requested=>{
  if(!Array.isArray(requested)||requested.length>20000||requested.some(r=>!uuid(r.clubId)||!uuid(r.athleteId)))throw Error('Canonical team and athlete IDs required');
  if(!requested.length)return [];
  const pairs=[...new Map(requested.map(r=>[`${r.clubId.toLowerCase()}:${r.athleteId.toLowerCase()}`,{clubId:r.clubId.toLowerCase(),athleteId:r.athleteId.toLowerCase()}])).values()];
  const result=await db.query(`with requested as (
   select distinct "clubId"::uuid as team_id,"athleteId"::uuid as athlete_id
   from jsonb_to_recordset($1::jsonb) as r("clubId" text,"athleteId" text)
  ) select t.id::text as "clubId",a.id::text as "athleteId",t.name as "clubName",
   trim(concat_ws(' ',a.first_name,a.last_name)) as "athleteName",
   a.first_name as "firstName",a.last_name as "lastName"
  from requested r join public.teams t on t.id=r.team_id
  join public.athletes a on a.id=r.athlete_id and a.organization_id=t.organization_id
  where exists(select 1 from public.roster_memberships m join public.seasons s on s.id=m.season_id
   where m.athlete_id=a.id and m.active and s.active and s.team_id=t.id)
  order by t.id,a.id`,[JSON.stringify(pairs)]);
  if(result.rows.length!==pairs.length)throw Error('Canonical active roster unavailable');
  return result.rows;
 };
}
