import test from 'node:test';
import assert from 'node:assert/strict';
import {createRemoteAppleEvidenceAdapter} from './remote-apple-evidence.mjs';
import {createBillingRuntime} from './billing-runtime.mjs';
const config={environment:'Sandbox',bundleID:'com.damonmele.wrestlingmanager'},secret='a'.repeat(64),url='https://verifier.example/apple';
const evidence={...config,originalTransactionID:'123',appAccountToken:'11111111-1111-4111-8111-111111111111'};
function response(value,endpoint=url){const r=Response.json(value);Object.defineProperty(r,'url',{value:endpoint});return r;}
test('private verifier binds environment and request, trims refresh input, and rejects redirects',async()=>{
 let calls=0;
 const client=createRemoteAppleEvidenceAdapter({url,secret,config,fetchImpl:async(endpoint,options)=>{
  calls++;assert.equal(endpoint,url);assert.equal(options.redirect,'error');assert.equal(options.headers.Authorization,'Bearer '+secret);
  const request=JSON.parse(options.body);assert.equal(request.environment,'Sandbox');
  if(request.action==='refresh')assert.deepEqual(request.input,evidence);
  return response({requestID:request.requestID,environment:request.environment,result:evidence});
 }});
 assert.deepEqual(await client.resolve('signed'),evidence);assert.deepEqual(await client.refresh({...evidence,userID:'do not forward'}),evidence);assert.equal(calls,2);
});
test('unbound, oversized, mismatched and wrong-environment verifier results are rejected',async()=>{
 for(const modify of [x=>({...x,requestID:'old'}),x=>({...x,environment:'Production'}),x=>({...x,result:{...evidence,bundleID:'wrong'}}),x=>({...x,result:{...evidence,extra:'x'.repeat(66000)}})]){
  const client=createRemoteAppleEvidenceAdapter({url,secret,config,fetchImpl:async(_,options)=>{
   const request=JSON.parse(options.body);return response(modify({requestID:request.requestID,environment:'Sandbox',result:evidence}));
  }});await assert.rejects(client.resolve('signed'),/unavailable/);
 }
 const client=createRemoteAppleEvidenceAdapter({url,secret,config,fetchImpl:async()=>response({},'https://elsewhere.example/apple')});await assert.rejects(client.resolve('signed'));
 for(const other of ['http://verifier.example/apple','https://verifier.example/apple?redirect=1','https://user@verifier.example/apple'])assert.throws(()=>createRemoteAppleEvidenceAdapter({url:other,secret,config}));
});
test('Deno deployment can use the remote verifier without reading an Apple private key locally',async()=>{
 let read=false;
 const runtime=await createBillingRuntime({pool:{},publishableKey:'synthetic',environment:'Sandbox',readSecret:()=>{read=true;},
  remoteApple:{url,secret},verifyDeployment:async()=>true,allowNotification:async()=>false,authorizeWorker:async()=>false});
 assert.equal(read,false);assert.equal(typeof runtime.billing,'function');
 assert.equal((await runtime.reconcile(new Request('https://backend.example/worker',{method:'POST'}))).status,403);
});
