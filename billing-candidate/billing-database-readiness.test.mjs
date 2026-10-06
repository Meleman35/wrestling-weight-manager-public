import test from 'node:test';import assert from 'node:assert/strict';
import {createBillingDatabaseReadiness} from '../supabase/functions/wm-billing-readiness/database-check.mjs';
const url='postgresql://wm_billing_service.vfocpoyexnjsjpxhhyqr:'+'a'.repeat(64)+'@aws-0-us-west-2.pooler.supabase.com:5432/postgres';
const flags={rolsuper:false,rolbypassrls:false,rolcreaterole:false,rolcreatedb:false,rolreplication:false};
function setup({value=url,badRole=false,fail=false}={}){
 let connects=0,ends=0,releases=0;
 class Pool {
  on(){}async connect(){connects++;if(fail)throw Error(url);return {query:async sql=>{
   if(sql.includes('session_user as login'))return {rows:[{...flags,login:badRole?'postgres':'wm_billing_service',rolcanlogin:true,runtime_member:true}]};
   if(sql.includes('current_user as role'))return {rows:[{...flags,role:'wm_billing_runtime',rolcanlogin:false}]};
   return {rows:[{expected_database:true,expected_role:true}]};
  },release(){releases++;}};}async end(){ends++;}
 }
 return {handler:createBillingDatabaseReadiness({readSecret:name=>{assert.equal(name,'BILLING_DATABASE_URL');return value;},Pool}),get connects(){return connects;},get ends(){return ends;},get releases(){return releases;}};
}
const request=()=>new Request('https://example.invalid/check',{method:'POST'});
test('database diagnostic coalesces requests, closes the connection and returns only readiness flags',async()=>{
 const f=setup();const rs=await Promise.all([f.handler(request()),f.handler(request())]);
 for(const r of rs)assert.deepEqual(await r.json(),{databaseURLConfigured:true,databaseConnected:true,restrictedDatabaseIdentity:true,billingEnabled:false});
 assert.equal(f.connects,1);assert.equal(f.ends,1);assert.equal(f.releases,1);
});
test('missing credentials, a privileged identity and database errors cannot enable billing or expose secrets',async()=>{
 for(const options of [{value:undefined},{value:'malformed'},{badRole:true},{fail:true}]){
  // Explicit undefined is represented by an empty secret for this fixture.
  if(options.value===undefined&&!options.badRole&&!options.fail)options.value='';
  const f=setup(options),r=await f.handler(request()),body=await r.json();assert.equal(body.databaseConnected,false);assert.equal(body.restrictedDatabaseIdentity,false);assert.equal(body.billingEnabled,false);assert.equal(JSON.stringify(body).includes('a'.repeat(64)),false);
  if(options.value!==undefined)assert.equal(f.connects,0);
  else assert.equal(f.ends,1);
 }
});
test('database diagnostic rejects browser origins and non-POST requests without opening connections',async()=>{
 const f=setup();assert.equal((await f.handler(new Request('https://example.invalid/check'))).status,405);
 assert.equal((await f.handler(new Request('https://example.invalid/check',{method:'POST',headers:{Origin:'https://theteammanager.app'}}))).status,403);assert.equal(f.connects,0);
});
