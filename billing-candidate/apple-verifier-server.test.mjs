import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {generateKeyPairSync} from 'node:crypto';
import {createAppleVerifierServer,runAppleVerification,validateAppleVerifierStartup} from './apple-verifier-server.mjs';
const secret='a'.repeat(64),requestID='11111111-1111-4111-8111-111111111111';
const body={requestID,environment:'Sandbox',action:'resolve',input:'e30.eyJmYWtlIjp0cnVlfQ.c2ln'};
async function withServer(verify,callback){
 const server=createAppleVerifierServer({secret,verify,maxConcurrent:1});server.listen(0,'127.0.0.1');await once(server,'listening');
 const url='http://127.0.0.1:'+server.address().port;
 const send=(data=body,headers={})=>fetch(url+'/apple',{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json',...headers},body:JSON.stringify(data)});
 try {await callback({send,url});}finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
}
test('verifier rejects unauthorized/browser/malformed requests before Apple work',async()=>{
 let calls=0;await withServer(async()=>{calls++;return {};},async({send,url})=>{
  for(const headers of [{Authorization:'Bearer wrong'},{Origin:'https://theteammanager.app'}])assert.equal((await send(body,headers)).status,403);
  for(const data of [{...body,environment:'Xcode'},{...body,input:'unsigned'},{...body,input:'a'.repeat(196609)},{...body,requestID:'-'.repeat(36)},{...body,url:'https://elsewhere.invalid'},{...body,action:'arbitrary'}])assert.equal((await send(data)).status,400);
  assert.equal((await fetch(url+'/health')).status,200);assert.equal(calls,0);
 });
});
test('verified result binds to the request and environment, with no caching',async()=>{
 await withServer(async call=>{assert.deepEqual(call,body);return {transactionID:'123'};},async({send})=>{
  const response=await send();assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');
  assert.deepEqual(await response.json(),{requestID,environment:'Sandbox',result:{transactionID:'123'}});
 });
});
test('concurrent work is bounded and verifier failures reveal no internals',async()=>{
 let release,started;const active=new Promise(r=>{started=r;});
 await withServer(async()=>{started();await new Promise(r=>{release=r;});throw Error('private diagnostic');},async({send})=>{
  const first=send();await active;assert.equal((await send()).status,429);release();
  const result=await first;assert.equal(result.status,503);assert.deepEqual(await result.json(),{error:'verification_unavailable'});
 });
});
test('real verifier worker fails closed without the server signing key',async()=>{
 const previous=process.env.APPLE_IAP_PRIVATE_KEY;delete process.env.APPLE_IAP_PRIVATE_KEY;
 try {await assert.rejects(runAppleVerification(body),/unavailable/);}finally{if(previous!==undefined)process.env.APPLE_IAP_PRIVATE_KEY=previous;}
});
test('Node startup validates key type and the real Apple worker rejects fabricated signed evidence',async()=>{
 const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 const pem=privateKey.export({format:'pem',type:'pkcs8'}).toString();
 validateAppleVerifierStartup(()=>pem);
 const other=generateKeyPairSync('ec',{namedCurve:'secp384r1'}).privateKey.export({format:'pem',type:'pkcs8'}).toString();
 assert.throws(()=>validateAppleVerifierStartup(()=>other),/configuration/);
 const previous=process.env.APPLE_IAP_PRIVATE_KEY;process.env.APPLE_IAP_PRIVATE_KEY=pem;
 try {await assert.rejects(runAppleVerification(body),/unavailable/);}
 finally{if(previous===undefined)delete process.env.APPLE_IAP_PRIVATE_KEY;else process.env.APPLE_IAP_PRIVATE_KEY=previous;}
});
