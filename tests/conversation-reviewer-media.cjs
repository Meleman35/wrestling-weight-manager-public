const assert=require('node:assert/strict'),fs=require('fs'),path=require('path');
(async()=>{
 const {createHandler}=await import('../supabase/functions/conversation-review-media/handler.ts');
 const tid='00000000-0000-0000-0000-000000000001',aid='00000000-0000-0000-0000-000000000002';
 const media=tid+'/'+tid+'/'+aid+'/photo with spaces.jpg',calls=[],passed=[];
 let denied=false,invalidAuth=false,removed=false,storageFails=false,fail=false;
 const h=createHandler({env:k=>({SUPABASE_URL:'https://db.example.invalid',SUPABASE_ANON_KEY:'fake-anon',SUPABASE_SERVICE_ROLE_KEY:'fake-service'}[k]),fetch:async(url,o)=>{
  calls.push({url,...o,body:o.body?JSON.parse(o.body):null});
  if(fail)throw Error('private provider failure');
  if(url.endsWith('/auth/v1/user'))return new Response(JSON.stringify({id:aid}),{status:invalidAuth?401:200});
  if(url.endsWith('/rpc/conversation_review_request'))return new Response(JSON.stringify({path:media}),{status:denied||removed?403:200});
  if(url.includes('/storage/v1/object/sign/'))return new Response(JSON.stringify({signedURL:'/object/sign/communication-media/'+media+'?token=test-signature'}),{status:storageFails?500:200});
  throw Error('Unexpected HTTP request');
 }});
 const req=(body={thread_id:tid,attachment_id:aid},authorization='Bearer user-token',origin='https://theteammanager.app')=>new Request('https://edge.example.invalid',{method:'POST',headers:{Authorization:authorization,Origin:origin,'Content-Type':'application/json'},body:JSON.stringify(body)});
 const pass=s=>{passed.push(s);console.log('PASS',s)};
 assert.equal((await h(new Request('https://edge.example.invalid'))).status,405);
 assert.equal((await h(req(undefined,'','https://evil.invalid'))).status,403);
 assert.equal((await h(req(undefined,''))).status,401);
 for(const body of [{thread_id:tid},{thread_id:tid,attachment_id:aid,expiresIn:999999},{thread_id:tid,attachment_id:aid,path:media},{thread_id:'../other',attachment_id:aid}])assert.equal((await h(req(body))).status,400);
 assert.equal(calls.length,0);pass('Rejects unauthenticated, wrong-origin, arbitrary-path and caller-selected-expiry requests before accessing services');
 let r=await h(req());assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');
 assert.deepEqual(await r.json(),{signedUrl:'https://db.example.invalid/storage/v1/object/sign/communication-media/'+media+'?token=test-signature',expiresIn:60});
 assert.equal(calls[0].headers.Authorization,'Bearer user-token');
 assert.deepEqual(calls[1].body,{p_action:'media',p_data:{thread_id:tid,attachment_id:aid}});assert.equal(calls[1].headers.Authorization,'Bearer user-token');
 assert.deepEqual(calls[2].body,{expiresIn:60});assert.equal(calls[2].headers.Authorization,'Bearer fake-service');assert(calls[2].url.endsWith('/photo%20with%20spaces.jpg'));
 pass('Verifies Auth and attachment permission as the caller before server signing a fixed 60-second URL');
 for(const mode of ['auth','denied','removed','storage','network']){
  calls.length=0;invalidAuth=mode==='auth';denied=mode==='denied';removed=mode==='removed';storageFails=mode==='storage';fail=mode==='network';
  r=await h(req());assert.equal(r.status,mode==='auth'?401:mode==='storage'?502:mode==='network'?503:403);
  const body=JSON.stringify(await r.json());assert(!body.includes('private')&&!body.includes('fake-service')&&!body.includes('signedUrl'));
  if(['auth','denied','removed','network'].includes(mode))assert(!calls.some(c=>c.url.includes('/storage/')));
 }
 pass('Revocation, removed media, invalid sessions and upstream failures cannot issue a link or leak provider details');
 fs.writeFileSync(path.join(__dirname,'../validation/conversation-reviewer-media.json'),JSON.stringify({passed,engine:'Node injected HTTP transport; synthetic accounts and objects only'},null,2));
})().catch(e=>{console.error(e);process.exit(1)});
