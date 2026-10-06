import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {billingConnectionOptions,createBillingConnectionPool} from './billing-connection.mjs';
const secret='a'.repeat(64);
const url=`postgresql://wm_billing_service.vfocpoyexnjsjpxhhyqr:${secret}@aws-0-us-west-2.pooler.supabase.com:5432/postgres`;
const base={rolsuper:false,rolbypassrls:false,rolcreaterole:false,rolcreatedb:false,rolreplication:false};
const login={...base,login:'wm_billing_service',rolcanlogin:true,runtime_member:true};
const runtime={...base,role:'wm_billing_runtime',rolcanlogin:false};
test('hosted diagnostic uses the same reviewed connection adapter',async()=>{
 assert.equal(await readFile(new URL('./billing-connection.mjs',import.meta.url),'utf8'),await readFile(new URL('../supabase/functions/wm-billing-readiness/billing-connection.mjs',import.meta.url),'utf8'));
});
function mock(rows=[login,runtime],failure=null){
 const calls=[];let released=false,ended=false;
 const connection={query:async sql=>{calls.push(sql);if(failure)throw failure;return {rows:sql.startsWith('set role')?[]:[rows.shift()]};},release:value=>{released=value;}};
 class Pool{constructor(options){assert.equal(options.ssl.rejectUnauthorized,true);}on(name,fn){assert.equal(name,'error');fn(Error('private idle detail'));}async connect(){return connection;}async end(){ended=true;}}
 return {pool:createBillingConnectionPool({Pool,connectionURL:url}),connection,calls,get released(){return released;},get ended(){return ended;}};
}
test('billing pool accepts only the confirmed host, service login, session mode and strong generated credential',()=>{
 const options=billingConnectionOptions(url);assert.equal(options.max,1);assert.equal(options.port,5432);assert.equal(options.user,'wm_billing_service.vfocpoyexnjsjpxhhyqr');assert.deepEqual(options.ssl,{rejectUnauthorized:true});
 for(const bad of [null,'not a URL',url+'?sslmode=disable',url+'#x',url.replace(':5432/',':6543/'),url.replace('/postgres','/other'),
  url.replace('aws-0-us-west-2.pooler.supabase.com','attacker.invalid'),url.replace('wm_billing_service.vfocpoyexnjsjpxhhyqr','postgres.vfocpoyexnjsjpxhhyqr'),url.replace(secret,'short')])
  assert.throws(()=>billingConnectionOptions(bad),e=>e.message==='Private billing connection unavailable'&&!e.message.includes(secret));
});
test('the actual login is checked before role selection and the selected role is checked before use',async()=>{
 const f=mock();assert.equal(await f.pool.connect(),f.connection);assert.match(f.calls[0],/session_user/);assert.equal(f.calls[1],'set role wm_billing_runtime');assert.match(f.calls[2],/current_user/);await f.pool.end();assert.equal(f.ended,true);
});
test('privileged, unexpected and non-member logins are discarded without selecting a role',async()=>{
 for(const patch of [{login:'postgres'},{rolsuper:true},{rolbypassrls:true},{rolcreaterole:true},{rolcreatedb:true},{rolreplication:true},{rolcanlogin:false},{runtime_member:false}]){
  const f=mock([{...login,...patch},runtime]);await assert.rejects(f.pool.connect(),/unavailable/);assert.equal(f.released,true);assert.equal(f.calls.length,1);
 }
});
test('an unexpectedly privileged selected role and provider errors cannot leak a connection or secret',async()=>{
 for(const patch of [{role:'authenticated'},{rolsuper:true},{rolbypassrls:true},{rolcreaterole:true},{rolcreatedb:true},{rolreplication:true},{rolcanlogin:true}]){
  const f=mock([login,{...runtime,...patch}]);await assert.rejects(f.pool.connect(),/unavailable/);assert.equal(f.released,true);
 }
 const f=mock(undefined,Error(url));await assert.rejects(f.pool.connect(),e=>!e.message.includes(secret)&&!e.message.includes('postgresql'));assert.equal(f.released,true);
});
