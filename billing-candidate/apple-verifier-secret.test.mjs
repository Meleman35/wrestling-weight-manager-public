import test from 'node:test';
import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import {validAppleVerifierSecret} from './apple-verifier-secret.mjs';
import {createRemoteAppleEvidenceAdapter} from './remote-apple-evidence.mjs';

test('32-byte hex and canonical Render Base64 secrets are accepted without normalizing authorization',async()=>{
 const bytes=Buffer.alloc(32,251),url='https://verifier.example/apple';
 const config={environment:'Sandbox',bundleID:'com.damonmele.wrestlingmanager'};
 for(const secret of [bytes.toString('hex'),bytes.toString('base64')]){
  assert.equal(validAppleVerifierSecret(secret),true);
  const apple=createRemoteAppleEvidenceAdapter({url,secret,config,fetchImpl:async(_,options)=>{
   assert.equal(options.headers.Authorization,'Bearer '+secret);
   const request=JSON.parse(options.body),response=Response.json({requestID:request.requestID,environment:'Sandbox',result:config});
   Object.defineProperty(response,'url',{value:url});return response;
  }});
  assert.deepEqual(await apple.resolve('synthetic.signed.input'),config);
 }
});
test('short, malformed, whitespace and noncanonical secret encodings are rejected',()=>{
 const valid=Buffer.alloc(32,251).toString('base64');
 for(const value of [undefined,null,42,'','a'.repeat(63),'a'.repeat(65),Buffer.alloc(16).toString('base64'),
  ' '+valid,valid+'\n',valid.slice(0,-1),valid.slice(0,-2)+'t=',valid.replace('/','_')]){
  assert.equal(validAppleVerifierSecret(value),false);
 }
});
