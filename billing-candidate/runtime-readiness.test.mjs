import test from 'node:test';
import assert from 'node:assert/strict';
import {createRuntimeReadiness} from '../supabase/functions/wm-runtime-readiness/remote-check.mjs';
const url = 'https://wm-apple-verifier.onrender.com/apple';
const secret = 'ab'.repeat(32);
const post = () => new Request('https://example.test/readiness',{method:'POST'});
const env = (endpoint=url,value=secret) => name => name==='APPLE_VERIFIER_URL'?endpoint:value;

test('remote diagnostic proves auth with a non-actionable request and never enables billing',async()=>{
  let calls = 0;
  const handle = createRuntimeReadiness({readSecret:env(),fetchImpl:async(endpoint,options)=>{
    calls++; assert.equal(endpoint,url); assert.equal(options.redirect,'error');
    assert.equal(options.headers.Authorization,'Bearer '+secret); assert.equal(options.body,'{}');
    return Response.json({error:'invalid_request'},{status:400});
  }});
  const responses = await Promise.all([handle(post()),handle(post())]);
  assert.equal(calls,1);
  for (const response of responses) {
    const text = await response.text(); assert.equal(text.includes(secret),false);
    const result = JSON.parse(text);
    assert.equal(result.remoteVerifierAuthenticated,true);
    assert.equal(result.remoteVerifierReachable,true);
    assert.equal(result.appleCertificateVerification,false);
    assert.equal(result.billingEnabled,false);
  }
});

test('diagnostic never transmits secrets to other URLs or with invalid secret configuration',async()=>{
  for (const [endpoint,value] of [[url+'/extra',secret],['http://wm-apple-verifier.onrender.com/apple',secret],['https://other.example/apple',secret],[url,'short'],[url,secret+'\n']]) {
    let calls=0;
    const handle=createRuntimeReadiness({readSecret:env(endpoint,value),fetchImpl:async()=>{calls++;throw Error('must not fetch');}});
    const result=await (await handle(post())).json();
    assert.equal(calls,0); assert.equal(result.remoteVerifierAuthenticated,false);
  }
});

test('denied, redirected, malformed, oversized, and unavailable responses cannot pass authentication',async()=>{
  const cases=[()=>Response.json({error:'not_authorized'},{status:403}),
    ()=>new Response(null,{status:302,headers:{Location:'https://other.example'}}),
    ()=>Response.json({ready:true}),()=>new Response('not JSON',{status:400}),
    ()=>new Response('x'.repeat(1025),{status:400}),()=>{throw Error('private detail '+secret);}];
  for (const result of cases) {
    const handle=createRuntimeReadiness({readSecret:env(),fetchImpl:async()=>result()});
    const text=await (await handle(post())).text();
    assert.equal(text.includes(secret),false); assert.equal(JSON.parse(text).remoteVerifierAuthenticated,false);
  }
});

test('diagnostic rejects browser origins and methods without making outbound calls',async()=>{
  let calls=0;
  const handle=createRuntimeReadiness({readSecret:env(),fetchImpl:async()=>{calls++;throw Error('unexpected');}});
  assert.equal((await handle(new Request('https://example.test'))).status,405);
  assert.equal((await handle(new Request('https://example.test',{method:'POST',headers:{Origin:'https://example.test'}}))).status,403);
  assert.equal(calls,0);
});
