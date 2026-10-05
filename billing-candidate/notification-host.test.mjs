import test from 'node:test';
import assert from 'node:assert/strict';
import {createNotificationHost} from './notification-host.mjs';
const base='https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-apple-notifications';
const req=(path='/production',headers={},method='POST')=>new Request(base+path,{method,headers});
function fixture(){
 const calls=[];let ready=true,authorized=true,time=60000;
 const query=async(sql,args)=>{calls.push({sql,args});return {rows:[{ready,allowed:authorized&&ready}]};};
 const host=createNotificationHost({readSecret:()=>undefined,clock:()=>time,
  makePool:()=>({connect:async()=>({query,release(){calls.push('release');}})}),
  makeRuntime:async config=>{
   calls.push({environment:config.environment});assert.equal(await config.verifyDeployment({query}),true);
   return {billing:()=>{throw Error('Purchase endpoint exposed');},
    notification:async()=>Response.json({environment:config.environment},{status:await config.allowNotification()?200:429}),
    reconcile:async request=>Response.json({status:'idle'},{status:await config.authorizeWorker(request)?200:403})};
  }});
 return {host,calls,setReady:value=>ready=value,setAuthorized:value=>authorized=value,tick:()=>time+=60000};
}
test('notification host rejects user purchase paths, origins, methods and missing worker credentials before connecting',async()=>{
 const {host,calls}=fixture();
 for(const [request,status] of [[req(''),404],[req('/billing'),404],[req('/production?action=prepare'),404],[req('/production',{Origin:'https://theteammanager.app'}),403],[req('/production',{},'GET'),405],[req('/sandbox/reconcile'),403]])assert.equal((await host(request)).status,status);
 assert.equal(calls.length,0);
});
test('separate environment routes reuse their runtime and recheck deployment before every notification',async()=>{
 const f=fixture();
 for(const env of ['production','sandbox','production'])assert.equal((await f.host(req('/'+env))).status,200);
 assert.deepEqual(f.calls.filter(c=>c?.environment).map(c=>c.environment),['Production','Sandbox']);
 f.setReady(false);const response=await f.host(req('/production'));assert.equal(response.status,503);
 assert.deepEqual(await response.json(),{error:'notifications_unavailable'});
});
test('worker requests require the database-backed capability and current deployment; credentials never enter responses',async()=>{
 const f=fixture(),token='a'.repeat(64),request=()=>req('/production/reconcile',{Authorization:'Bearer '+token});
 assert.equal((await f.host(request())).status,200);assert(f.calls.some(c=>c?.args?.[0]===token));
 f.setAuthorized(false);assert.equal((await f.host(request())).status,403);
 f.setAuthorized(true);f.setReady(false);assert.equal((await f.host(request())).status,403);
 assert(f.calls.includes('release'));
});
test('burst limiting returns retry responses and resets without acknowledging unprocessed work',async()=>{
 const f=fixture();for(let i=0;i<30;i++)assert.equal((await f.host(req())).status,200);
 assert.equal((await f.host(req())).status,429);f.tick();assert.equal((await f.host(req())).status,200);
});
test('runtime initialization failures are redacted and can recover',async()=>{
 let tries=0;const host=createNotificationHost({readSecret:()=>undefined,makePool:()=>({}),makeRuntime:async()=>{if(++tries===1)throw Error('private connection details');return {notification:async()=>new Response('',{status:200})};}});
 const failed=await host(req());assert.equal(failed.status,503);assert.equal((await failed.text()).includes('private'),false);
 assert.equal((await host(req())).status,200);
});

test('Supabase function-prefixed internal URLs use the same strict route allowlist',async()=>{
 const {host}=fixture();
 assert.equal((await host(new Request('https://edge.invalid/wrestling-manager-apple-notifications/sandbox',{method:'POST'}))).status,200);
 assert.equal((await host(new Request('https://edge.invalid/unrelated/wrestling-manager-apple-notifications/sandbox',{method:'POST'}))).status,404);
});
