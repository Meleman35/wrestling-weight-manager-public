import test from 'node:test';
import assert from 'node:assert/strict';
import {reconcileSubscription as reconcile,hasFamilyVideoAccess as access,hasTeamSubscriptionAccess,proposedProducts} from './subscription-policy.mjs';
const userID='11111111-1111-4111-8111-111111111111',athleteID='22222222-2222-4222-8222-222222222222',otherID='33333333-3333-4333-8333-333333333333',token='44444444-4444-4444-8444-444444444444',now=1800000000000;
const productID='com.damonmele.wrestlingmanager.familyvideo.annual';
const base=()=>({actor:{userID,liveSession:true,confirmed:true},intent:{userID,familyOwnerID:userID,token,productID,authorized:true},evidence:{bundleID:'com.damonmele.wrestlingmanager',environment:'Sandbox',transactionID:'1001',originalTransactionID:'1001',appAccountToken:token,productID,status:1,snapshotSignedAt:now-1000,expiresAt:now+10000},config:{bundleID:'com.damonmele.wrestlingmanager',environment:'Sandbox',products:proposedProducts},now});
const request=()=>({athleteID,familyOwnerID:userID,linkedAthleteIDs:[athleteID],recorderAuthorized:true,environment:'Sandbox',now});
const denied=(input,code)=>assert.throws(()=>reconcile(input),e=>e.code===code);
test('four created products are allowlisted',()=>assert.equal(Object.keys(proposedProducts).length,4));
test('family grant follows athlete without granting team access',()=>{
 const s=reconcile(base()).subscription;assert.equal(s.teamID,null);assert.equal(access(s,request()),true);
 assert.equal(hasTeamSubscriptionAccess(s,{teamID:otherID,environment:'Sandbox',now}),false);
});
test('authorized team device can film a covered athlete; unauthorized device cannot',()=>{
 const s=reconcile(base()).subscription;assert.equal(access(s,request()),true);
 assert.equal(access(s,{...request(),recorderAuthorized:false}),false);
});
test('family access requires current server-resolved coverage and owner',()=>{
 const s=reconcile(base()).subscription;
 for(const patch of [{linkedAthleteIDs:[]},{linkedAthleteIDs:[otherID]},{familyOwnerID:otherID},{linkedAthleteIDs:[athleteID,athleteID]},{linkedAthleteIDs:[athleteID,otherID,token]},{environment:'Production'}])assert.equal(access(s,{...request(),...patch}),false);
 assert.equal(access(s,{...request(),linkedAthleteIDs:[athleteID,otherID]}),true);
});
test('family restore cannot be redirected to another owner or team',()=>{
 const b=base();b.existing=reconcile(b).subscription;b.intent={...b.intent,familyOwnerID:otherID,teamID:otherID};
 assert.equal(reconcile(b).subscription.familyOwnerID,userID);
 b.actor.userID=otherID;denied(b,'different_owner');
});
test('family purchase refuses a client-selected team or another family owner',()=>{
 for(const patch of [{teamID:otherID},{familyOwnerID:otherID},{familyOwnerID:null}]){const b=base();Object.assign(b.intent,patch);denied(b,'missing_authorized_intent');}
});
test('renewal may change family period but cannot cross to team product',()=>{
 const b=base();b.existing=reconcile(b).subscription;b.evidence.snapshotSignedAt=now;b.evidence.productID='com.damonmele.wrestlingmanager.familyvideo.monthly';
 assert.equal(reconcile(b).subscription.plan,'family_video_month');
 b.evidence.productID='com.damonmele.wrestlingmanager.teampro.monthly';denied(b,'scope_mismatch');
});
test('expired, refunded and billing-retry family subscriptions grant no video access',()=>{
 const s=reconcile(base()).subscription;assert.equal(access(s,{...request(),now:s.expiresAt}),false);
 for(const status of [2,3,5])assert.equal(access({...s,status},request()),false);
 assert.equal(access({...s,revokedAt:now},request()),false);
 assert.equal(access({...s,status:4,graceExpiresAt:now+1},request()),true);
 assert.equal(access({...s,status:4,graceExpiresAt:now},request()),false);
});
test('team plan cannot be used as family video grant',()=>{
 const b=base();b.evidence.productID=b.intent.productID='com.damonmele.wrestlingmanager.teampro.annual';delete b.intent.familyOwnerID;b.intent.teamID=otherID;
 assert.equal(access(reconcile(b).subscription,request()),false);
});
