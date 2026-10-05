// Runs on pinned Deno 2.1.4 without network permission or production secrets.
// npm ci supplies the pinned dependency tree from package-lock.json.
// This checks the remote-verifier path and records why local Apple verification
// is blocked; it does not establish valid receipts or hosted billing readiness.
import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import pg from 'pg';
import {appleTrustRoots} from '../apple-trust-roots.mjs';
import {createRemoteAppleEvidenceAdapter} from '../remote-apple-evidence.mjs';
import {SupabaseBillingAuth} from '../supabase-billing-auth.mjs';
import {createBillingRuntime} from '../billing-runtime.mjs';
import {createBillingDatabaseReadiness} from '../../supabase/functions/wm-billing-readiness/database-check.mjs';

Deno.test('Deno loads the PostgreSQL adapter without connecting as a privileged identity',async()=>{
 const pool=new pg.Pool({max:1}); // No connection or credentials are used.
 await pool.end();
});
Deno.test('Deno database readiness stays disabled without a private credential',async()=>{
 const handler=createBillingDatabaseReadiness({Pool:pg.Pool,readSecret:()=>undefined});
 const response=await handler(new Request('https://example.invalid/check',{method:'POST'}));
 assert.deepEqual(await response.json(),{databaseURLConfigured:false,databaseConnected:false,restrictedDatabaseIdentity:false,billingEnabled:false});
});
Deno.test('Deno 2.1.4 blocks local Apple verification at the unsupported certificate API',()=>{
 assert.equal(Deno.version.deno,'2.1.4');
 assert.throws(()=>appleTrustRoots(),/Not implemented: crypto.X509Certificate.prototype.verify/);
});
Deno.test('Deno auth verifies the same structured JWT before constructing a context',async()=>{
 const projectURL='https://vfocpoyexnjsjpxhhyqr.supabase.co';
 const claims={sub:'11111111-1111-4111-8111-111111111111',session_id:'22222222-2222-4222-8222-222222222222',
  exp:Math.floor(Date.now()/1000)+60,aud:'authenticated',role:'authenticated',iss:projectURL+'/auth/v1'};
 const authorization='Bearer e30.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.c2ln';
 let calls=0;
 const auth=new SupabaseBillingAuth({projectURL,publishableKey:'synthetic',pool:{},fetchImpl:async(url,options)=>{
  calls++;assert.equal(url,projectURL+'/auth/v1/user');assert.equal(options.headers.Authorization,authorization);
  return {ok:true,json:async()=>({id:claims.sub})};
 }});
 const context=await auth.authenticate(authorization);
 assert.equal(calls,1);assert.equal(auth.claims(context).userID,claims.sub);
 assert.throws(()=>auth.claims({}));
});
Deno.test('Deno runtime still refuses an unapproved deployment before reading secrets',async()=>{
 let read=false;
 await assert.rejects(createBillingRuntime({pool:{},publishableKey:'synthetic',readSecret:()=>{read=true;},environment:'Sandbox',
  verifyDeployment:async()=>false,allowNotification:async()=>true,authorizeWorker:async()=>true}),/not approved/);
 assert.equal(read,false);
});
Deno.test('Deno composes the remote-verifier runtime without a local Apple key or certificate operations',async()=>{
 let read=false;
 const runtime=await createBillingRuntime({pool:{},publishableKey:'synthetic',environment:'Sandbox',
  readSecret:()=>{read=true;throw Error('Apple key must stay on Node');},
  remoteApple:{url:'https://verifier.example/apple',secret:Buffer.alloc(32,251).toString('base64')},
  verifyDeployment:async()=>true,allowNotification:async()=>false,authorizeWorker:async()=>false});
 assert.equal(read,false);assert.equal(typeof runtime.billing,'function');
 assert.equal((await runtime.reconcile(new Request('https://backend.example/worker',{method:'POST'}))).status,403);
});
Deno.test('Deno remote transport accepts only evidence bound to this request, environment and app',async()=>{
 const url='https://verifier.example/apple',config={environment:'Sandbox',bundleID:'com.damonmele.wrestlingmanager'};
 let wrongEnvironment=false;
 const apple=createRemoteAppleEvidenceAdapter({url,secret:'a'.repeat(64),config,fetchImpl:async(endpoint,options)=>{
  assert.equal(endpoint,url);assert.equal(options.redirect,'error');
  const request=JSON.parse(options.body);
  assert.equal(request.environment,config.environment);assert.equal(request.action,'resolve');
  const response=Response.json({requestID:request.requestID,environment:wrongEnvironment?'Production':'Sandbox',result:{...config}});
  Object.defineProperty(response,'url',{value:url});return response;
 }});
 assert.deepEqual(await apple.resolve('synthetic.signed.input'),config);
 wrongEnvironment=true;await assert.rejects(apple.resolve('synthetic.signed.input'),/unavailable/);
});
