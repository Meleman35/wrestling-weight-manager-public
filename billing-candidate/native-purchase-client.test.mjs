import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativePurchaseClient as create} from './native-purchase-client.mjs';
const family = 'com.damonmele.wrestlingmanager.familyvideo.monthly';
const team = 'com.damonmele.wrestlingmanager.teampro.annual';
const teamID = '11111111-1111-4111-8111-111111111111';
function setup(postMessage) { return create({handler:{postMessage},currentSession:()=> 'account-a',sessionGeneration:'account-a'}); }
test('client routes purchase and restore with no credentials or restore target', async()=>{
 const calls=[];const client=setup(async body=>{calls.push(body);return {outcome:'delivered'}});
 await client.purchase(family,{kind:'family'});await client.purchase(team,{kind:'team',teamID});await client.restore();await client.recover();
 assert.deepEqual(calls,[{command:'purchase',productID:family,target:{kind:'family'}},{command:'purchase',productID:team,target:{kind:'team',teamID}},{command:'restore'},{command:'recover'}]);
 assert.throws(()=>client.purchase(family,{kind:'team',teamID}),/invalid_purchase_target/);
 assert.throws(()=>client.purchase(family,{kind:'family',ownerID:teamID}),/invalid_purchase_target/);
});
test('native responses cannot introduce a paid flag or unknown outcome', async()=>{
 for(const response of [{outcome:'delivered',paid:true},{outcome:'paid'},null])
  await assert.rejects(setup(async()=>response).restore(),/invalid_native_purchase_response/);
});
test('account change during pending native request rejects late response', async()=>{
 let generation='a',resolve;
 const client=create({handler:{postMessage:()=>new Promise(r=>resolve=r)},currentSession:()=>generation,sessionGeneration:'a'});
 const pending=client.restore();generation='b';resolve({outcome:'delivered'});
 await assert.rejects(pending,/purchase_session_ended/);
 await assert.rejects(client.restore(),/purchase_session_ended/);
});
test('stop is irreversible and concurrent requests cannot start twice', async()=>{
 let resolve;const client=setup(()=>new Promise(r=>resolve=r));const pending=client.restore();
 await assert.rejects(client.recover(),/purchase_request_busy/);
 client.stop();resolve({outcome:'pending'});await assert.rejects(pending,/purchase_session_ended/);
 await assert.rejects(client.restore(),/purchase_session_ended/);
});
test('product metadata rejects duplicates, foreign products and local paid fields', async()=>{
 const product={id:family,displayPrice:'€14,99',type:'autoRenewable'};
 const valid=await setup(async()=>({products:[product]})).loadProducts();assert.equal(valid[0].displayPrice,'€14,99');
 for(const list of [[product,product],[{...product,id:'other'}],[{...product,paid:true}]])
  await assert.rejects(setup(async()=>({products:list})).loadProducts(),/invalid_native_product_response/);
});
test('native errors are sanitized',async()=>{
 await assert.rejects(setup(async()=>{throw new Error('private provider detail')}).restore(),{message:'purchase_request_unconfirmed'});
});
