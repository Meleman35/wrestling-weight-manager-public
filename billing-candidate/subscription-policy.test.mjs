import test from 'node:test';
import assert from 'node:assert/strict';
import {reconcileSubscription as reconcile, reconcileKnownSubscription, hasTeamSubscriptionAccess as access, proposedProducts} from './subscription-policy.mjs';

const userID = '11111111-1111-4111-8111-111111111111';
const otherID = '22222222-2222-4222-8222-222222222222';
const teamID = '33333333-3333-4333-8333-333333333333';
const token = '44444444-4444-4444-8444-444444444444';
const productID = Object.keys(proposedProducts)[0];
const now = 1_800_000_000_000;
const base = () => ({
  actor: {userID, liveSession:true, confirmed:true},
  intent: {userID, teamID, token, productID, authorized:true},
  evidence: {bundleID:'com.damonmele.wrestlingmanager', environment:'Sandbox',
    transactionID:'100000000000000001', originalTransactionID:'100000000000000001',
    appAccountToken:token, productID, status:1, snapshotSignedAt:now-1000, expiresAt:now+10000},
  config: {bundleID:'com.damonmele.wrestlingmanager', environment:'Sandbox', products:proposedProducts}, now
});
const denied = (input,code) => assert.throws(()=>reconcile(input), e=>e.code===code);
test('purchase binds only the authorized fixture team',()=>{
  const r=reconcile(base());
  assert.equal(access(r.subscription,{teamID,environment:'Sandbox',now}),true);
  assert.equal(access(r.subscription,{teamID:otherID,environment:'Sandbox',now}),false);
});
test('sandbox cannot grant production access',()=>{
  const b=base(); b.config.environment='Production'; denied(b,'app_or_environment_mismatch');
  assert.equal(access(reconcile(base()).subscription,{teamID,environment:'Production',now}),false);
});
test('wrong bundle or unknown product rejected',()=>{
  const b=base();b.evidence.bundleID='evil';denied(b,'app_or_environment_mismatch');
  b.evidence.bundleID=b.config.bundleID;b.evidence.productID='toString';denied(b,'unknown_product');
});
test('restore cannot claim another app account subscription',()=>{
  const b=base();b.existing=reconcile(b).subscription;b.actor.userID=otherID;denied(b,'different_owner');
});
test('restore preserves team despite unrelated new intent',()=>{
  const b=base();b.existing=reconcile(b).subscription;b.intent.teamID=otherID;
  assert.equal(reconcile(b).subscription.teamID,teamID);
});
test('token mismatch and reuse on another original purchase rejected',()=>{
  const b=base();b.existing=reconcile(b).subscription;b.evidence.appAccountToken=otherID;denied(b,'token_mismatch');
  const c=base();c.intent.boundOriginalTransactionID='999';denied(c,'intent_already_bound');
});
test('missing intent, unauthorized team and cancelled intent rejected',()=>{
  for(const alter of [b=>b.intent=null,b=>b.intent.authorized=false,b=>b.intent.cancelled=true]){
    const b=base();alter(b);denied(b,'missing_authorized_intent');
  }
});
test('dead sessions, deleted accounts and managed team logins rejected',()=>{
  for(const [field,value] of [['liveSession',false],['confirmed',false],['deleted',true],['banned',true],['managedTeamLogin',true],['deletionFrozen',true]]){
    const b=base();b.actor[field]=value;denied(b,'unauthorized');
  }
});
test('renewal extends expiry without moving license',()=>{
  const b=base();b.existing=reconcile(b).subscription;b.evidence.transactionID='100000000000000002';
  b.evidence.snapshotSignedAt=now;b.evidence.expiresAt=now+20000;
  const r=reconcile(b);assert.equal(r.subscription.teamID,teamID);assert.equal(r.subscription.expiresAt,now+20000);
});
test('older active snapshot cannot undo newer revocation',()=>{
  const b=base();b.evidence.revokedAt=now-500;b.evidence.status=5;b.evidence.snapshotSignedAt=now;
  b.existing=reconcile(b).subscription;delete b.evidence.revokedAt;b.evidence.status=1;b.evidence.snapshotSignedAt=now-1000;
  const r=reconcile(b);assert.equal(r.changed,false);assert.equal(access(r.subscription,{teamID,environment:'Sandbox',now}),false);
});
test('equal-version contradictions require reconciliation',()=>{
  const b=base();b.existing=reconcile(b).subscription;b.evidence.status=5;denied(b,'conflicting_snapshot');
});
test('expiry, billing retry, refund and grace boundaries',()=>{
  const s=reconcile(base()).subscription;
  assert.equal(access(s,{teamID,environment:'Sandbox',now:s.expiresAt}),false);
  for(const status of [2,3,5])assert.equal(access({...s,status},{teamID,environment:'Sandbox',now}),false);
  assert.equal(access({...s,revokedAt:now},{teamID,environment:'Sandbox',now}),false);
  assert.equal(access({...s,status:4,graceExpiresAt:now+1},{teamID,environment:'Sandbox',now}),true);
  assert.equal(access({...s,status:4,graceExpiresAt:now},{teamID,environment:'Sandbox',now}),false);
});
test('invalid and future timestamps and malformed transaction IDs rejected',()=>{
  for(const change of [e=>e.snapshotSignedAt=now+60001,e=>e.expiresAt='forever',e=>e.transactionID=1,e=>e.status=0]){
    const b=base();change(b.evidence);denied(b,'invalid_evidence');
  }
});
test('repeated evidence produces the same effective subscription',()=>{
  const b=base();const first=reconcile(b);b.existing=first.subscription;
  assert.deepEqual(reconcile(b).subscription,first.subscription);
});


test('notification updates a known binding without a fabricated user session',()=>{const b=base();const existing=reconcile(b).subscription;const evidence={...b.evidence,status:5,revokedAt:now-500,snapshotSignedAt:now};const result=reconcileKnownSubscription({existing,evidence,config:b.config,now});assert.equal(result.subscription.userID,userID);assert.equal(result.subscription.teamID,teamID);assert.equal(access(result.subscription,{teamID,environment:'Sandbox',now}),false);});
test('notification cannot create an ownership binding',()=>{const b=base();assert.throws(()=>reconcileKnownSubscription(b),/missing_existing_binding/);});
test('old notification cannot overwrite a newer refund',()=>{const b=base();const existing={...reconcile(b).subscription,status:5,revokedAt:now-500,snapshotSignedAt:now};assert.equal(reconcileKnownSubscription({...b,existing}).changed,false);});
