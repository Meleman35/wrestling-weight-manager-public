import test from 'node:test';
import assert from 'node:assert/strict';
import {createSandboxBillingHost} from './sandbox-billing-host.mjs';
const base='https://edge.invalid/wrestling-manager-billing';
const request=(method='POST',headers={},path='')=>new Request(base+path,{method,headers:{Authorization:'Bearer a.b.c',...headers}});
function fixture(){
 let ready=true,connections=0,calls=0;
 const host=createSandboxBillingHost({readSecret:name=>name==='APPLE_VERIFIER_URL'?'https://wm-apple-verifier.onrender.com/apple':undefined,
  makePool:()=>({connect:async()=>{connections++;return {query:async sql=>({rows:[sql.includes('current_user')?{role:'wm_billing_runtime',rolsuper:false,rolbypassrls:false,login:'wm_billing_service',login_super:false,login_bypass:false,can_login:true}:{ready}]}),release(){}};}}),
  makeApple:options=>{assert.equal(options.config.environment,'Sandbox');return {};},makeAuth:()=>({}),makeRepository:()=>({}),
  makeHandler:options=>{assert.equal(options.purchaseEnvironment,'Sandbox');return async()=>{calls++;return Response.json({synthetic:true});};}});
 return {host,counts:()=>({connections,calls}),setReady:x=>ready=x};
}
test('sandbox host rejects other paths, origins, methods and missing user authorization before database access',async()=>{
 const f=fixture();for(const [req,status] of [[request('POST',{},'/production'),404],[request('POST',{},'?environment=Production'),404],[request('POST',{Origin:'https://elsewhere.invalid'}),403],[request('GET'),405],[request('POST',{Authorization:''}),401]])assert.equal((await f.host(req)).status,status);
 const preflight=await f.host(request('OPTIONS',{Origin:'https://theteammanager.app'}));assert.equal(preflight.status,204);assert.equal(preflight.headers.get('Access-Control-Allow-Origin'),'https://theteammanager.app');assert.deepEqual(f.counts(),{connections:0,calls:0});
});
test('host fixes the Apple environment and rechecks deployment readiness on every request',async()=>{
 const f=fixture();assert.equal((await f.host(request())).status,200);f.setReady(false);assert.equal((await f.host(request())).status,503);assert.equal(f.counts().calls,1);
});
