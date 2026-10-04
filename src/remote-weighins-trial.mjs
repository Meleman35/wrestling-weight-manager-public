// Server-only policy. Persist the returned state under a canonical organization
// key in a serialized transaction; never accept trial state from a client.
export const REMOTE_DIRECTOR_OFFER = Object.freeze({monthlyUSD:24.99,annualUSD:199,tournamentLimit:4});
const id = x => typeof x === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(x);
export function calendarMonthAfter(time) {
 if (!Number.isSafeInteger(time) || time < 0) throw Error('Invalid trial clock');
 const d=new Date(time), day=d.getUTCDate();
 d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()+1);
 const last=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).getUTCDate();
 d.setUTCDate(Math.min(day,last));
 return d.toISOString();
}
function validate(state,organizationId) {
 if(!state || state.organizationId!==organizationId || !Number.isFinite(Date.parse(state.startedAt)) || state.expiresAt!==calendarMonthAfter(Date.parse(state.startedAt)) || !Array.isArray(state.tournamentIds) || state.tournamentIds.length<1 || state.tournamentIds.length>4 || state.tournamentIds.some(x=>!id(x)) || new Set(state.tournamentIds).size!==state.tournamentIds.length) throw Error('Invalid private trial state');
}
export function activateTrialTournament({state=null,organizationId,tournamentId,now}) {
 if(!id(organizationId)||!id(tournamentId))throw Error('Canonical organization and tournament required');
 calendarMonthAfter(now);
 if(state===null)return {organizationId,startedAt:new Date(now).toISOString(),expiresAt:calendarMonthAfter(now),tournamentIds:[tournamentId]};
 validate(state,organizationId);
 if(state.revoked===true||now<Date.parse(state.startedAt)||now>=Date.parse(state.expiresAt))throw Error('Trial expired; authorized paid access required');
 if(state.tournamentIds.includes(tournamentId))return {...state,tournamentIds:[...state.tournamentIds]};
 if(state.tournamentIds.length>=4)throw Error('Four tournament trial limit reached');
 return {...state,tournamentIds:[...state.tournamentIds,tournamentId]};
}
export function trialTournamentEntitlement({state,organizationId,tournamentId,programId,now}) {
 validate(state,organizationId);calendarMonthAfter(now);
 if(!id(programId)||!id(tournamentId))throw Error('Canonical event mapping required');
 if(now<Date.parse(state.startedAt)||now>=Date.parse(state.expiresAt)||!state.tournamentIds.includes(tournamentId)||state.revoked===true)return null;
 return {scope:'remote_network',programId,active:true,coveredUntil:state.expiresAt,source:'organization_trial'};
}
