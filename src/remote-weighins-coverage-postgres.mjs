import {createRemoteCoverageGate} from './remote-weighins-coverage.mjs';
// Team entitlement and canonical club->team mapping remain independent trusted
// billing/enrollment readers. SQL network coverage also supports activated trials.
export function createRemotePostgresCoverageGate({db,getTeamEntitlement,getEnrollment,now=Date.now}) {
 if(typeof db?.query!=='function')throw Error('Trusted coverage database required');
 return createRemoteCoverageGate({getTeamEntitlement,getEnrollment,now,getNetworkEntitlement:async programId=>{
  const row=(await db.query('select remote_reporting.program_coverage_until($1) as expires_at',[programId])).rows[0];
  if(!row?.expires_at)return null;
  return {scope:'remote_network',programId,active:true,coveredUntil:new Date(row.expires_at).toISOString()};
 }});
}
