import test from 'node:test';
import assert from 'node:assert/strict';
import {createAppleNotificationDiagnostic} from '../tests/hosted/apple-notification-diagnostic.mjs';
const token='a'.repeat(64),secret='b'.repeat(64),body={action:'testRequest',environment:'Sandbox',input:null};
function fixture(){
 let now=1000,allowed=true,calls=0,connections=0,override;
 const handler=createAppleNotificationDiagnostic({expiresAt:2000,clock:()=>now,readSecret:name=>({APPLE_VERIFIER_URL:'https://wm-apple-verifier.onrender.com/apple',APPLE_VERIFIER_SHARED_SECRET:secret})[name],
  makePool:()=>({connect:async()=>{connections++;return {query:async()=>({rows:[{allowed}]}),release(){}};}}),
  fetchImpl:async(url,options)=>{calls++;assert.equal(options.redirect,'error');assert.equal(options.headers.Authorization,'Bearer '+secret);const input=JSON.parse(options.body);const response=Response.json({requestID:input.requestID,environment:input.environment,result:override??{state:'requested',testNotificationToken:'test-token'}});Object.defineProperty(response,'url',{value:url});return response;}});
 const request=(data=body,headers={})=>new Request('https://edge.invalid/wm-apple-notification-test',{method:'POST',headers:{Authorization:'Bearer '+token,...headers},body:JSON.stringify(data)});
 return {handler,request,setAllowed:x=>allowed=x,expire:()=>now=2000,setResult:x=>override=x,counts:()=>({calls,connections})};
}
test('temporary diagnostic requires private capability, rejects browser calls and closes at its deadline',async()=>{
 const f=fixture();for(const headers of [{Authorization:'Bearer wrong'},{Origin:'https://theteammanager.app'}])assert.equal((await f.handler(f.request(body,headers))).status,403);
 assert.deepEqual(f.counts(),{calls:0,connections:0});f.setAllowed(false);assert.equal((await f.handler(f.request())).status,403);assert.equal(f.counts().calls,0);
 f.expire();assert.equal((await f.handler(f.request())).status,410);
});
test('diagnostic permits only test commands and returns bounded matched safe responses without secrets',async()=>{
 const f=fixture();for(const data of [{...body,action:'resolve',input:'a.b.c'},{...body,url:'https://outside.invalid'},{...body,input:'x'.repeat(5000)}])assert.equal((await f.handler(f.request(data))).status,400);
 const response=await f.handler(f.request());assert.equal(response.status,200);assert.deepEqual(await response.json(),{environment:'Sandbox',state:'requested',testNotificationToken:'test-token'});
 f.setResult({state:'requested',testNotificationToken:'test-token',private:secret});const rejected=await f.handler(f.request());assert.equal(rejected.status,503);assert.equal((await rejected.text()).includes(secret),false);
});
