// Server-only gate: entitlement readers must query verified private billing state.
// Neither a client plan label nor a team purchase establishes network coverage.
const id=x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,160}$/.test(x);
const teamPlans=new Set(['team_pro_year','team_pro_month']);
export function createRemoteCoverageGate({getNetworkEntitlement,getTeamEntitlement,getEnrollment,now=Date.now}) {
 if(![getNetworkEntitlement,getTeamEntitlement,getEnrollment,now].every(f=>typeof f==='function'))throw Error('Trusted independent coverage readers required');
 const live=(e,time)=>e?.revoked!==true&&e?.active===true&&Number.isFinite(Date.parse(e.coveredUntil))&&Date.parse(e.coveredUntil)>time;
 const clock=()=>{const t=now();if(!Number.isSafeInteger(t)||t<0)throw Error('Invalid coverage clock');return t;};
 async function read({programId}){
  if(!id(programId))throw Error('Invalid reporting program');
  const e=await getNetworkEntitlement(programId);
  if(!e||e.scope!=='remote_network'||e.programId!==programId||!live(e,clock()))throw Error('Separate network coverage required');
  return true;
 }
 async function capture({programId,clubId}){
  await read({programId});
  if(!id(clubId))throw Error('Invalid reporting club');
  const enrolled=await getEnrollment(programId,clubId);
  if(enrolled?.active!==true||enrolled.programId!==programId||enrolled.clubId!==clubId||!id(enrolled.teamId))throw Error('Current club enrollment required');
  const e=await getTeamEntitlement(enrolled.teamId);
  if(!e||e.scope!=='team'||e.teamId!==enrolled.teamId||!teamPlans.has(e.plan)||!live(e,clock()))throw Error('Participating team coverage required');
  // Recheck network after the team lookup in case it expired between awaits.
  await read({programId});return true;
 }
 return Object.freeze({read,capture});
}
