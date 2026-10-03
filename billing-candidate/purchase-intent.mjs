import {randomUUID} from 'node:crypto';
import {proposedProducts} from './subscription-policy.mjs';
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const allowedActor=a=>a&&uuid(a.userID)&&a.liveSession===true&&a.confirmed===true&&a.deleted!==true&&a.banned!==true&&a.managedTeamLogin!==true&&a.deletionFrozen!==true;
// Candidate ports only. The repository must lock the purchaser+subscription
// group durably, recheck the exact session, and return only after commit.
export class PurchaseIntentService {
 constructor({auth,repository,clock=Date.now,token=randomUUID}){this.auth=auth;this.repository=repository;this.clock=clock;this.token=token;}
 async prepare(authContext,request){
  if(!request||Object.keys(request).some(k=>!['productID','target'].includes(k))||!Object.hasOwn(proposedProducts,request.productID))throw Error('invalid_request');
  const target=request.target,plan=proposedProducts[request.productID],scope=plan.startsWith('team_')?'team':'family';
  if(!target||target.kind!==scope||Object.keys(target).some(k=>!['kind','teamID'].includes(k))||
     (scope==='team'?!uuid(target.teamID):target.teamID!==undefined))throw Error('invalid_target');
  const initial=await this.auth.currentActor(authContext);if(!allowedActor(initial))throw Error('unauthorized');
  return this.repository.intentTransaction({userID:initial.userID,scope},async tx=>{
   const actor=await tx.currentActor(authContext);if(!allowedActor(actor))throw Error('unauthorized');
   if(actor.userID!==initial.userID)throw Error('session_changed');
   if(scope==='team'){
    if(await tx.canPurchaseTeam(actor.userID,target.teamID)!==true)throw Error('team_purchase_forbidden');
    // The initial two Apple products belong to one group. Renewal/restore must
    // keep the original team, even after expiry. Pending choices also lock it.
    const bound=await tx.getTeamPurchaseBinding(actor.userID);
    if(bound&&bound.teamID!==target.teamID)throw Error('team_already_bound');
   }else if(await tx.canPurchaseFamily(actor.userID)!==true)throw Error('family_purchase_forbidden');
   const token=this.token(),createdAt=this.clock();if(!uuid(token)||!Number.isSafeInteger(createdAt)||createdAt<0)throw Error('invalid_configuration');
   const intent={userID:actor.userID,productID:request.productID,teamID:scope==='team'?target.teamID:null,
    ...(scope==='family'?{familyOwnerID:actor.userID}:{}),token,createdAt,authorized:true,cancelled:false};
   await tx.saveIntent(intent);
   return {appAccountToken:token};
  });
 }
}
