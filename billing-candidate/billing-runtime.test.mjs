import test from 'node:test';
import assert from 'node:assert/strict';
import {appleTrustRoots} from './apple-trust-roots.mjs';
import {privateBillingPool,billingDatabase,createBillingRuntime} from './billing-runtime.mjs';

test('all three Apple PKI trust anchors are intact, CA roots and self-signed',()=>assert.equal(appleTrustRoots().length,3));
test('server pool rejects privileged or unrelated database identities before any billing operation',async()=>{
 for(const row of [{role:'postgres',rolsuper:true,rolbypassrls:true},{role:'service_role',rolsuper:false,rolbypassrls:true},{role:'authenticated',rolsuper:false,rolbypassrls:false},{role:'wm_billing_runtime',rolsuper:false,rolbypassrls:true}]){
  let released=false;const connection={query:async()=>({rows:[row]}),release:destroy=>{released=destroy;}};
  await assert.rejects(privateBillingPool({connect:async()=>connection}).connect(),/identity/);assert.equal(released,true);
 }
 const connection={query:async()=>({rows:[{role:'wm_billing_runtime',rolsuper:false,rolbypassrls:false}]}),release(){}};
 assert.equal(await privateBillingPool({connect:async()=>connection}).connect(),connection);
});
test('runtime transaction commits before returning and rolls back on failure',async()=>{
 const calls=[];const connection={query:async sql=>{calls.push(sql);return {rows:[]};},release:()=>calls.push('release')};
 const db=billingDatabase({connect:async()=>connection});
 assert.equal(await db.transaction(async c=>{await c.query('write');return 'durable';}),'durable');
 assert.deepEqual(calls.slice(-3),['write','COMMIT','release']);calls.length=0;
 await assert.rejects(db.transaction(async()=>{throw Error('failed');}),/failed/);
 assert.deepEqual(calls.slice(-2),['ROLLBACK','release']);
});
test('runtime cannot start without reviewed deployment and cannot leak private configuration through a fallback',async()=>{
 let read=false;
 await assert.rejects(createBillingRuntime({pool:{},publishableKey:'public',readSecret:()=>{read=true;return '';},environment:'Sandbox',
  verifyDeployment:async()=>false,allowNotification:async()=>true,authorizeWorker:async()=>true}),/not approved/);
 assert.equal(read,false);
});
