import test from 'node:test';
import assert from 'node:assert/strict';
import {createBillingHandler} from './billing-handler.mjs';
import {launchProductIDs} from './launch-products.mjs';
const request=(data={})=>new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'capabilities',data})});
test('native purchase activation requires enabled service and a currently authorized personal actor',async()=>{
 let actor={userID:'owner',liveSession:true,confirmed:true};
 const auth={authenticate:async()=>({}),currentActor:async()=>actor};
 assert.equal((await createBillingHandler({auth})(request())).status,503);
 const handler=createBillingHandler({enabled:true,auth});
 assert.deepEqual(await (await handler(request())).json(),{ready:true,productIDs:[...launchProductIDs].sort()});
 for(const changed of [null,{...actor,liveSession:false},{...actor,confirmed:false},{...actor,deleted:true},{...actor,banned:true},{...actor,managedTeamLogin:true},{...actor,deletionFrozen:true}]){
  const before=actor;actor=changed;assert.equal((await handler(request())).status,401);actor=before;
 }
 assert.equal((await handler(request({enabled:true}))).status,400);
});
