import {hasTeamSubscriptionAccess,hasFamilyVideoAccess} from './subscription-policy.mjs';
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const allowed=a=>a&&uuid(a.userID)&&a.liveSession===true&&a.confirmed===true&&
 a.deleted!==true&&a.banned!==true&&a.managedTeamLogin!==true&&a.deletionFrozen!==true;

// Server-only candidate. Repository accessTransaction must use a consistent
// permission/subscription snapshot coordinated with deletion and revocation.
// resolveAccess returns canonical server relationships, never request claims.
export class SubscriptionAccessService {
 constructor({auth,repository,environment,clock=Date.now}) {
  if(!['Sandbox','Production'].includes(environment))throw Error('invalid_configuration');
  Object.assign(this,{auth,repository,environment,clock});
 }
 async read(context,request){
  if(!request||Array.isArray(request)||Object.keys(request).some(k=>!['teamID','athleteID'].includes(k))||
    !uuid(request.teamID)||(request.athleteID!==undefined&&!uuid(request.athleteID)))throw Error('invalid_request');
  const initial=await this.auth.currentActor(context);if(!allowed(initial))throw Error('unauthorized');
  return this.repository.accessTransaction({userID:initial.userID,teamID:request.teamID},async tx=>{
   const actor=await tx.currentActor(context);
   if(!allowed(actor)||actor.userID!==initial.userID)throw Error('unauthorized');
   const state=await tx.resolveAccess(actor.userID,request.teamID,request.athleteID??null);
   if(state?.teamAuthorized!==true)throw Error('access_forbidden');
   const now=this.clock();if(!Number.isSafeInteger(now)||now<0)throw Error('invalid_clock');
   const teamPro=(state.teamSubscriptions||[]).some(s=>hasTeamSubscriptionAccess(s,{teamID:request.teamID,environment:this.environment,now}));
   const familyVideo=!!request.athleteID&&state.athleteAuthorized===true&&(state.familyCoverage||[]).some(c=>
    hasFamilyVideoAccess(c.subscription,{athleteID:request.athleteID,familyOwnerID:c.familyOwnerID,
     linkedAthleteIDs:c.linkedAthleteIDs,recorderAuthorized:state.recorderAuthorized===true,environment:this.environment,now}));
   // Recheck after awaited relationship resolution. Return no purchaser IDs,
   // receipts, family roster, credentials or unrelated subscriptions.
   const finalActor=await tx.currentActor(context);
   if(!allowed(finalActor)||finalActor.userID!==actor.userID)throw Error('unauthorized');
   return {teamID:request.teamID,athleteID:request.athleteID??null,teamPro,familyVideo,checkedAt:now};
  });
 }
}
