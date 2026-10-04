import test from 'node:test';
import assert from 'node:assert/strict';
import {AppleEvidenceAdapter} from './apple-evidence.mjs';
import {proposedProducts} from './subscription-policy.mjs';
const token='44444444-4444-4444-8444-444444444444';
const bundleID='com.damonmele.wrestlingmanager';
const productId=Object.keys(proposedProducts)[0];
function fixture() {
  const transaction={bundleId:bundleID,environment:'Sandbox',productId,transactionId:'100',
    originalTransactionId:'100',appAccountToken:token,type:'Auto-Renewable Subscription',
    expiresDate:1800000010000,signedDate:1800000000000};
  const current={...transaction,transactionId:'101'};
  const renewal={environment:'Sandbox',originalTransactionId:'100',productId,
    appAccountToken:token,signedDate:1800000000001};
  const item={originalTransactionId:'100',status:1,signedTransactionInfo:'current.jws.signature',signedRenewalInfo:'renewal.jws.signature'};
  const response={bundleId:bundleID,environment:'Sandbox',data:[{lastTransactions:[item]}]};
  let calls=0;
  const verifier={
    async verifyAndDecodeTransaction(s){ if(s==='submitted.jws.signature')return transaction; if(s==='current.jws.signature')return current;throw Error('signature rejected'); },
    async verifyAndDecodeRenewalInfo(){return renewal;},
    async verifyAndDecodeNotification(){return {notificationUUID:token,data:{bundleId:bundleID,environment:'Sandbox',signedTransactionInfo:'submitted.jws.signature'}};}
  };
  const api={async getAllSubscriptionStatuses(id){calls++;assert.equal(id,'100');return response;}};
  const adapter=new AppleEvidenceAdapter({verifier,api,bundleID,environment:'Sandbox',products:proposedProducts});
  return {adapter,transaction,current,renewal,item,response,verifier,calls:()=>calls};
}
test('canonical renewal state used while original submitted transaction is acknowledged',async()=>{
  const f=fixture();f.current.expiresDate+=1000;
  const e=await f.adapter.resolve('submitted.jws.signature');
  assert.equal(e.transactionID,'100');assert.equal(e.expiresAt,f.current.expiresDate);assert.equal(f.calls(),1);
});
test('signature failure cannot reach Apple status lookup',async()=>{
  const f=fixture();await assert.rejects(f.adapter.resolve('forged.jws.signature'));assert.equal(f.calls(),0);
});
test('malformed and oversized payloads rejected',async()=>{
  const f=fixture();for(const s of ['plain JSON', 'x'.repeat(65537)])await assert.rejects(f.adapter.resolve(s));assert.equal(f.calls(),0);
});
test('wrong bundle, environment, product or type rejected after verification',async()=>{
  for(const [k,v] of [['bundleId','evil'],['environment','Production'],['productId','unknown'],['type','Consumable']]){
    const f=fixture();f.transaction[k]=v;await assert.rejects(f.adapter.resolve('submitted.jws.signature'));assert.equal(f.calls(),0);
  }
});
test('ambiguous or absent original subscription rejected',async()=>{
  for(const duplicate of [false,true]){
    const f=fixture();f.response.data[0].lastTransactions=duplicate?[f.item,f.item]:[];
    await assert.rejects(f.adapter.resolve('submitted.jws.signature'));
  }
});
test('unsigned renewal or invalid status response cannot grant access',async()=>{
  const f=fixture();delete f.item.signedRenewalInfo;await assert.rejects(f.adapter.resolve('submitted.jws.signature'));
  const g=fixture();g.response.environment='Production';await assert.rejects(g.adapter.resolve('submitted.jws.signature'));
});
test('changed token, mismatched renewal identity and mismatched renewal environment rejected',async()=>{
  for(const alter of [f=>f.current.appAccountToken='55555555-5555-4555-8555-555555555555',f=>f.renewal.originalTransactionId='999',f=>f.renewal.environment='Production']){
    const f=fixture();alter(f);await assert.rejects(f.adapter.resolve('submitted.jws.signature'));
  }
});
test('grace status requires a verified grace expiry',async()=>{
  const f=fixture();f.item.status=4;await assert.rejects(f.adapter.resolve('submitted.jws.signature'));
  f.renewal.gracePeriodExpiresDate=f.current.expiresDate+1000;
  assert.equal((await f.adapter.resolve('submitted.jws.signature')).graceExpiresAt,f.renewal.gracePeriodExpiresDate);
});
test('notification verified before canonical lookup',async()=>{
  const f=fixture();const n=await f.adapter.notificationTransaction('notification.jws.signature');
  assert.equal(n.notificationID,token);assert.equal(n.evidence.originalTransactionID,'100');
});
test('invalid notification signature and missing transaction payload rejected',async()=>{
  const f=fixture();f.verifier.verifyAndDecodeNotification=async()=>{throw Error('bad signature');};
  await assert.rejects(f.adapter.notificationTransaction('notification.jws.signature'));assert.equal(f.calls(),0);
  const g=fixture();g.verifier.verifyAndDecodeNotification=async()=>({notificationUUID:token});
  await assert.rejects(g.adapter.notificationTransaction('notification.jws.signature'));assert.equal(g.calls(),0);
});
test('verified Apple TEST is acknowledged without transaction lookup',async()=>{
 const f=fixture();f.verifier.verifyAndDecodeNotification=async()=>({notificationUUID:token,notificationType:'TEST',data:{bundleId:bundleID,environment:'Sandbox'}});
 assert.deepEqual(await f.adapter.notificationTransaction('notification.jws.signature'),{notificationID:token,kind:'test'});assert.equal(f.calls(),0);
});
test('TEST for a different app or environment still fails',async()=>{
 for(const data of [{bundleId:'other',environment:'Sandbox'},{bundleId:bundleID,environment:'Production'}]){
 const f=fixture();f.verifier.verifyAndDecodeNotification=async()=>({notificationUUID:token,notificationType:'TEST',data});await assert.rejects(f.adapter.notificationTransaction('notification.jws.signature'));assert.equal(f.calls(),0);}
});
test('worker refresh verifies current status and immutable original/token binding',async()=>{
 const f=fixture();const e=await f.adapter.resolve('submitted.jws.signature');f.item.status=5;
 assert.equal((await f.adapter.refresh(e)).status,5);
 const g=fixture();g.current.appAccountToken='55555555-5555-4555-8555-555555555555';
 await assert.rejects(g.adapter.refresh(e));
});
