import test from 'node:test';import assert from 'node:assert/strict';
import {createRemoteReportingClient} from '../src/remote-weighins-client.mjs';
const session=(id='session-a',suffix='sig')=>({user:{id:'user'},access_token:'header.'+Buffer.from(JSON.stringify({sub:'user',session_id:id})).toString('base64url')+'.'+suffix});
const fixture=(fetch,options={})=>{let current=session();const client=createRemoteReportingClient({initialSession:current,getSession:async()=>current,isCurrent:()=>true,publishableKey:'public',fetch,...options});return {client,replace:s=>current=s};};
test('client uses fixed endpoint and permits token refresh within the same session',async()=>{
 const f=fixture(async(url,options)=>{assert.equal(url,'https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/remote-weighins/report');assert.equal(options.redirect,'error');assert.equal(options.credentials,'omit');assert.ok(options.signal);f.replace(session('session-a','refreshed'));return Response.json({rows:[]});});
 assert.deepEqual(await f.client.report({programId:'p'}),{rows:[]});f.client.stop();await assert.rejects(f.client.context(),/closed/);
});
test('same-account replacement and replacement while reading a response are rejected',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;return Response.json({});});f.replace(session('session-b'));await assert.rejects(f.client.context(),/changed/);assert.equal(calls,0);
 const g=fixture(async()=>{g.replace(session('session-b'));return Response.json({});});await assert.rejects(g.client.context(),/changed/);
});
test('client bounds content length and streamed response bytes',async()=>{
 for(const response of [new Response('{}',{headers:{'Content-Type':'application/json','Content-Length':String(5*1024*1024)}}),new Response(new Uint8Array(4*1024*1024+1),{headers:{'Content-Type':'application/json'}})]){
  const f=fixture(async()=>response);await assert.rejects(f.client.context(),/too large/);
 }
});
test('stop cancels a pending body read and prevents response delivery',async()=>{
 let cancelled=false,started;const ready=new Promise(r=>started=r);
 const f=fixture(async()=>new Response(new ReadableStream({start(){started();},cancel(){cancelled=true;}}),{headers:{'Content-Type':'application/json'}}));
 const pending=f.client.context();await ready;await new Promise(r=>setTimeout(r,0));f.client.stop();await assert.rejects(pending,/cancelled|closed/);assert.equal(cancelled,true);
});
test('stalled responses time out and unexpected MIME or invalid JPEG fail closed',async()=>{
 const stalled=fixture(async()=>new Response(new ReadableStream(),{headers:{'Content-Type':'application/json'}}),{timeoutMs:5});await assert.rejects(stalled.client.context(),/cancelled/);
 const html=fixture(async()=>new Response('<html>',{headers:{'Content-Type':'text/html'}}));await assert.rejects(html.client.context(),/type/);
 const photo=fixture(async()=>new Response('bad',{headers:{'Content-Type':'image/jpeg'}}));await assert.rejects(photo.client.photo({submissionId:'s'}),/photo/);
});
