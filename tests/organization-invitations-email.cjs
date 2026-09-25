const assert=require('node:assert/strict'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
(async()=>{
 const {createHandler}=await import('../supabase/functions/send-organization-invitation/handler.ts');
 const checks=[],calls=[];const pass=s=>{checks.push(s);console.log('PASS',s)};
 let deny=false,providerFail=false,timeout=false;
 const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
 const body={organization_id:id(1),id:id(2),request_id:id(3),token:'WMO-'+'a'.repeat(64)};
 const handler=createHandler({env:name=>({SUPABASE_URL:'https://database.example.test',SUPABASE_ANON_KEY:'fake-anon',RESEND_API_KEY:'fake-email-key'}[name]),fetch:async(url,options)=>{
  calls.push({url,options});
  if(url.includes('/rpc/'))return new Response(JSON.stringify(deny?{message:'denied'}:{id:body.id,request_id:body.request_id,email:'leader@example.test',organization_name:'<img onerror="alert(1)"> Org',access:{title:'Secretary',scope:'Girls program',access_role:'board'},expires_at:'2026-10-09T00:00:00Z'}),{status:deny?403:200});
  if(timeout)throw Error('Simulated timeout');
  return new Response(JSON.stringify(providerFail?{message:'Failed',secret:'do not expose'}:{id:'fake-email-id'}),{status:providerFail?500:200});
 }});
 const request=(data=body,auth='Bearer fake-user')=>new Request('https://edge.example.test',{method:'POST',headers:{Authorization:auth,'Content-Type':'application/json'},body:JSON.stringify(data)});
 assert.equal((await handler(request(body,''))).status,401);assert.equal(calls.length,0);pass('Missing authentication never reaches email transport');
 assert.equal((await handler(request({...body,token:'invalid'}))).status,400);assert.equal(calls.length,0);pass('Malformed token rejected before database or provider calls');
 deny=true;assert.equal((await handler(request())).status,403);assert.equal(calls.length,1);deny=false;pass('Database authorization failure prevents sending');
 let result=await handler(request({...body,email:'attacker@example.test',to:['attacker@example.test'],subject:'Override',html:'Override',url:'https://attacker.example.test'}));
 assert.deepEqual(await result.json(),{ok:true,sent:1,id:'fake-email-id'});
 const sent=JSON.parse(calls.at(-1).options.body);assert.deepEqual(sent.to,['leader@example.test']);assert.ok(!sent.subject.includes('Override'));assert.ok(!sent.html.includes('<img'));assert.ok(!sent.text.includes('attacker.example.test'));assert.match(sent.text,/https:\/\/meleman35.github.io\/wrestling-weight-manager-public\/\?invite=WMO-/);
 assert.equal(calls.at(-2).options.headers.Authorization,'Bearer fake-user');assert.equal(calls.at(-2).options.headers.apikey,'fake-anon');pass('Fixed template, saved recipient and public app link ignore caller overrides and escape HTML');
 const key=calls.at(-1).options.headers['Idempotency-Key'];await handler(request());assert.equal(calls.at(-1).options.headers['Idempotency-Key'],key);pass('Uncertain-send retry reuses the provider idempotency key');
 providerFail=true;result=await handler(request());assert.equal(result.status,502);assert.ok(!JSON.stringify(await result.json()).includes('do not expose'));providerFail=false;timeout=true;assert.equal((await handler(request())).status,502);pass('Provider errors and timeouts never claim success or expose upstream details');
 const unconfigured=createHandler({env:()=>undefined,fetch:async()=>{throw Error('must not call')}});assert.equal((await unconfigured(request())).status,503);pass('Missing configuration offers copy-link fallback');
 fs.writeFileSync(path.join(root,'validation/organization-invitations-email.json'),JSON.stringify({engine:'Node 24; injected fake HTTP transport; zero real messages',passed:checks.length,tests:checks},null,2));
})().catch(e=>{console.error(e);process.exit(1)});
