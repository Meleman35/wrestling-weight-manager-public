const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const allowed=a=>a&&uuid(a.userID)&&a.liveSession===true&&a.confirmed===true&&
 a.deleted!==true&&a.banned!==true&&a.managedTeamLogin!==true&&a.deletionFrozen!==true;

// Selection is not an entitlement. A verified, active family subscription and
// the event's current recording permissions are evaluated separately on read.
export class FamilyCoverageService {
 constructor({auth,repository}){Object.assign(this,{auth,repository});}
 async options(context,request){
  if(!request||Array.isArray(request)||Object.keys(request).length)throw Error('invalid_request');
  const initial=await this.auth.currentActor(context);if(!allowed(initial))throw Error('unauthorized');
  return this.repository.coverageTransaction({userID:initial.userID},async tx=>{
   const actor=await tx.currentActor(context);if(!allowed(actor)||actor.userID!==initial.userID)throw Error('unauthorized');
   const athletes=await tx.familyCoverageOptions(actor.userID);
   const finalActor=await tx.currentActor(context);if(!allowed(finalActor)||finalActor.userID!==actor.userID)throw Error('unauthorized');
   if(!Array.isArray(athletes)||athletes.length>1000||athletes.some(a=>!uuid(a.athlete_id)||!uuid(a.profile_id)||typeof a.display_name!=='string'||a.display_name.length>240||typeof a.selected!=='boolean')||new Set(athletes.map(a=>a.profile_id)).size!==athletes.length)throw Error('coverage_unconfirmed');
   return {athletes:athletes.map(({athlete_id,profile_id,display_name,selected})=>({athlete_id,profile_id,display_name,selected}))};
  });
 }
 async select(context,request){
  if(!request||Array.isArray(request)||Object.keys(request).some(k=>k!=='athleteIDs')||
   !Array.isArray(request.athleteIDs)||request.athleteIDs.length>2||request.athleteIDs.some(x=>!uuid(x)))throw Error('invalid_request');
  const athleteIDs=request.athleteIDs.map(x=>x.toLowerCase());
  if(new Set(athleteIDs).size!==athleteIDs.length)throw Error('invalid_request');
  const initial=await this.auth.currentActor(context);if(!allowed(initial))throw Error('unauthorized');
  return this.repository.coverageTransaction({userID:initial.userID},async tx=>{
   const actor=await tx.currentActor(context);
   if(!allowed(actor)||actor.userID!==initial.userID)throw Error('unauthorized');
   const result=await tx.replaceFamilyCoverage(actor.userID,athleteIDs);
   const finalActor=await tx.currentActor(context);
   if(!allowed(finalActor)||finalActor.userID!==actor.userID)throw Error('unauthorized');
   if(!result||result.selectedCount!==athleteIDs.length)throw Error('coverage_unconfirmed');
   return {selectedCount:result.selectedCount};
  });
 }
}
