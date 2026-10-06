import test from 'node:test';
import assert from 'node:assert/strict';
import {PurchaseDeliveryService} from './purchase-delivery.mjs';
import {proposedProducts} from './subscription-policy.mjs';

const userID='11111111-1111-4111-8111-111111111111';
const otherID='22222222-2222-4222-8222-222222222222';
const teamID='33333333-3333-4333-8333-333333333333';
const token='44444444-4444-4444-8444-444444444444';
const productID=Object.keys(proposedProducts)[0];
const now=1800000000000;
function fixture() {
  let actor={userID,liveSession:true,confirmed:true};
  let committed={subscription:null,intent:{userID,teamID,token,productID,authorized:true},deliveries:[]};
  let queue=Promise.resolve();
  const flags={failCommit:false};
  const evidence={bundleID:'com.damonmele.wrestlingmanager',environment:'Sandbox',
    transactionID:'100',originalTransactionID:'100',appAccountToken:token,productID,
    snapshotSignedAt:now-1000,expiresAt:now+10000,status:1};
  const auth={async currentActor(){return {...actor};}};
  const apple={async resolve(){return {...evidence};}};
  // Test-only serial transaction model with rollback. NOT a storage adapter.
  const repository={transaction(keys,callback){
    const execute=async()=>{
      const staged=structuredClone(committed);
      const tx={currentActor:auth.currentActor,getSubscription:async()=>staged.subscription,
        getIntent:async()=>staged.intent,
        saveSubscription:async s=>{staged.subscription=s;},
        bindIntent:async(t,o)=>{if(staged.intent.boundOriginalTransactionID && staged.intent.boundOriginalTransactionID!==o)throw Error('token reused');staged.intent.boundOriginalTransactionID=o;},
        recordDelivery:async(e,t,o)=>{if(!staged.deliveries.some(d=>d[0]===e&&d[1]===t))staged.deliveries.push([e,t,o]);}};
      const result=await callback(tx);
      if(flags.failCommit)throw Error('database unavailable');
      committed=staged;return result;
    };
    const result=queue.then(execute);queue=result.catch(()=>{});return result;
  }};
  const service=new PurchaseDeliveryService({auth,apple,repository,
    config:{bundleID:evidence.bundleID,environment:'Sandbox',products:proposedProducts},clock:()=>now});
  return {service,auth,apple,evidence,flags,state:()=>committed,setActor:a=>actor=a};
}
const request={signedTransaction:'submitted.jws.signature'};
test('acknowledgement returned after durable transaction commit',async()=>{
  const f=fixture();assert.deepEqual(await f.service.deliver('session',request),{transactionID:'100',originalTransactionID:'100'});
  assert.equal(f.state().subscription.teamID,teamID);assert.equal(f.state().deliveries.length,1);
});
test('database failure returns no acknowledgement and rolls back binding',async()=>{
  const f=fixture();f.flags.failCommit=true;await assert.rejects(f.service.deliver('session',request));
  assert.equal(f.state().subscription,null);assert.equal(f.state().intent.boundOriginalTransactionID,undefined);
  f.flags.failCommit=false;await f.service.deliver('session',request);assert.equal(f.state().deliveries.length,1);
});
test('concurrent duplicate delivery creates one effective grant and one delivery',async()=>{
  const f=fixture();await Promise.all(Array.from({length:8},()=>f.service.deliver('session',request)));
  assert.equal(f.state().deliveries.length,1);assert.equal(f.state().subscription.teamID,teamID);
});
test('account/session revoked during Apple lookup prevents all writes',async()=>{
  const f=fixture();f.apple.resolve=async()=>{f.setActor({userID,liveSession:false,confirmed:true});return f.evidence;};
  await assert.rejects(f.service.deliver('session',request));assert.equal(f.state().subscription,null);
});
test('account changes during Apple lookup are rejected',async()=>{
  const f=fixture();f.apple.resolve=async()=>{f.setActor({userID:otherID,liveSession:true,confirmed:true});return f.evidence;};
  await assert.rejects(f.service.deliver('session',request),/session_changed/);assert.equal(f.state().subscription,null);
});
test('client cannot supply team, actor, acknowledgement or paid flag',async()=>{
  for(const field of ['teamID','actor','ack','paid']){
    const f=fixture();await assert.rejects(f.service.deliver('session',{...request,[field]:true}),/invalid_request/);
    assert.equal(f.state().subscription,null);
  }
});
test('failed Apple verification creates no records',async()=>{
  const f=fixture();f.apple.resolve=async()=>{throw Error('bad signature');};
  await assert.rejects(f.service.deliver('session',request));assert.equal(f.state().deliveries.length,0);
});
test('different app account cannot restore committed original purchase',async()=>{
  const f=fixture();await f.service.deliver('session',request);f.setActor({userID:otherID,liveSession:true,confirmed:true});
  await assert.rejects(f.service.deliver('other-session',request));assert.equal(f.state().subscription.userID,userID);
});
