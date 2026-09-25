const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const fixture=fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')+`
sessionStorage.setItem('wm-app-open-attempt','1');
window.oiFixture={admin:true,orgAccess:true,failCreate:false,failEmail:false,delay:0,writes:[],emails:[],previewError:null,rows:[],accepts:0};
const originalCreate=window.supabase.createClient;
window.supabase.createClient=()=>{
 const c=originalCreate(),baseRpc=c.rpc;
 c.functions={invoke:async(name,q)=>{oiFixture.emails.push(JSON.parse(JSON.stringify({name,...q})));return oiFixture.failEmail?{error:{message:'Simulated lost email response'}}:{data:{ok:true,sent:1},error:null}}};
 c.rpc=async(name,args)=>{
  const f=oiFixture,q=args?.p_request||{};
  if(name==='get_operations'){
   if(q.action==='context'&&!f.orgAccess)return {data:[],error:null};
   const result=await baseRpc(name,args);if(q.action==='hub')result.data.admin=f.admin;return result;
  }
  if(name!=='organization_leadership_invites')return baseRpc(name,args);
  if(q.action==='context'){
   const data={organization_id:q.organization_id,organization_name:'Example School District',administrators:[{user_id:'admin-test',name:'Example Administrator'}],positions:[{id:'position-1',title:'Secretary',division_name:'Girls program',revision:1,can_manage_meetings:false,can_manage_votes:false,voting_member:false}],invitations:structuredClone(f.rows)};
   if(f.delay)await new Promise(r=>setTimeout(r,f.delay));return f.admin?{data,error:null}:{error:{message:'Organization administrator access required.'}};
  }
  if(q.action==='create'){
   f.writes.push(structuredClone(q));if(!f.rows.some(x=>x.id===q.id))f.rows.push({id:q.id,invited_email:q.email,kind:q.kind,position_id:q.position_id,status:'pending',expires_at:'2026-10-09T00:00:00Z',access_summary:{title:q.kind==='administrator'?'Organization administrator':'Secretary',scope:'Girls program',access_role:q.access_role}});
   return f.failCreate?{error:{message:'Simulated lost creation response'}}:{data:{id:q.id,expires_at:'2026-10-09T00:00:00Z',access:f.rows.find(x=>x.id===q.id).access_summary}};
  }
  if(q.action==='revoke'){f.rows.find(x=>x.id===q.id).status='revoked';return {data:{revoked:true}}}
  if(q.action==='preview')return f.previewError?{error:{message:f.previewError}}:{data:{id:'invitation',organization_id:'org-a',organization_name:'Example School District',email:'leader@example.test',kind:'position',access:{title:'Secretary',scope:'Girls program',access_role:'board',voting_member:false,can_manage_meetings:false,can_manage_votes:false}}};
  if(q.action==='accept'){f.accepts++;f.orgAccess=true;f.writes.push(structuredClone(q));return {data:{organization_id:'org-a',accepted:true}}}
  return {data:{}};
 };
 return c;
};
`;
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const checks=[],pass=s=>{checks.push(s);console.log('PASS',s)},errors=[];
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage();p.on('pageerror',e=>errors.push(e.message));p.on('dialog',d=>d.accept());
 await ctx.addInitScript({content:fixture});
 await p.route('**/*',r=>r.request().isNavigationRequest()&&new URL(r.request().url()).hostname==='wm.example.test'?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 try{
  await p.goto('https://wm.example.test/');await p.waitForFunction(()=>typeof WMOrgInvites!=='undefined'&&!accountRefreshFlight);
  await p.evaluate(async()=>{session=fixture.session={user:{id:'admin-test',email:'admin@example.test'}};await refresh()});
  await p.waitForSelector('#setupOrganizations:not(.hidden)');assert.equal(await p.locator('#setupChoices').getAttribute('open'),null);assert.equal(await p.evaluate(()=>activeTeam),null);
  await p.locator('[data-oi-org="org-a"]').click();await p.waitForSelector('[data-ops-home="invitations"]');assert.equal(await p.locator('#opsSwitchTeams').isVisible(),false);
  await p.locator('[data-ops-home="invitations"]').click();await p.waitForSelector('#oiNew');pass('Organization-only account opens its hub and invite tools without a team or team switch prompt');
  await p.locator('#oiNew').click();await p.locator('#oiEmail').fill('leader@example.test');await p.locator('#oiPosition').selectOption('position-1');await p.locator('#oiAccess').selectOption('board');
  assert.match(await p.locator('#oiAccessSummary').innerText(),/Girls program/);assert.equal(await p.locator('#oiPermissions').isChecked(),false);
  await p.locator('#oiAdult').check();await p.locator('#oiPermissions').check();await p.screenshot({path:path.join(root,'validation/organization-invitation-form-phone.png')});
  assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));pass('Phone invite form separates title, scope and permissions without horizontal overflow');
  await p.evaluate(()=>oiFixture.failCreate=true);await p.locator('#oiCreate').click();await p.waitForFunction(()=>document.getElementById('oiStatus').textContent.includes('not yet confirmed'));
  assert.equal(await p.locator('#oiEmail').inputValue(),'leader@example.test');await p.evaluate(()=>oiFixture.failCreate=false);await p.locator('#oiCreate').click();await p.waitForSelector('#oiSend');
  const writes=await p.evaluate(()=>oiFixture.writes);assert.equal(writes[0].id,writes[1].id);assert.equal(writes[0].token,writes[1].token);assert.match(writes[0].token,/^WMO-[0-9a-f]{64}$/);assert.equal(await p.evaluate(()=>oiFixture.rows.length),1);pass('Lost creation response retains form and retries the same secure invitation');
  const link=await p.locator('#oiLink').inputValue();assert.match(link,/^https:\/\/meleman35.github.io\/wrestling-weight-manager-public\/\?invite=WMO-/);
  await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw Error('Denied')}}}));await p.locator('#oiCopy').click();assert.match(await p.locator('#oiStatus').innerText(),/Copy was unavailable/);
  await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async value=>window.copied=value}}));await p.locator('#oiCopy').click();assert.equal(await p.evaluate(()=>window.copied),link);pass('Share link uses public app URL; blocked copying shows manual fallback without false success');
  await p.evaluate(()=>oiFixture.failEmail=true);await p.locator('#oiSend').click();await p.waitForFunction(()=>document.getElementById('oiSend').textContent==='Retry email');assert.match(await p.locator('#oiStatus').innerText(),/not confirmed/);
  await p.evaluate(()=>oiFixture.failEmail=false);await p.locator('#oiSend').click();await p.waitForFunction(()=>document.getElementById('oiSend').textContent==='Email submitted');
  const emails=await p.evaluate(()=>oiFixture.emails);assert.equal(emails[0].body.request_id,emails[1].body.request_id);assert.equal(emails[0].body.token,emails[1].body.token);assert.equal(await p.locator('#oiSend').isDisabled(),true);pass('Email failure is visible; retry preserves link and request identity and reports submission only');
  await p.locator('#oiDone').click();await p.waitForSelector('[data-oi-revoke]');await p.locator('[data-oi-revoke]').click();await p.waitForFunction(()=>document.getElementById('opsContent').textContent.includes('revoked'));
  await p.locator('#oiNew').click();await p.locator('#oiKind').selectOption('administrator');assert.match(await p.locator('#oiAccessSummary').innerText(),/Full organization administration/);assert.equal(await p.locator('#oiPositionFields').isVisible(),false);await p.locator('#oiCancel').click();pass('Pending invitations can be revoked; full administrator access is explicit');
  await p.evaluate(()=>oiFixture.delay=150);await p.locator('#oiRefresh').click();await p.locator('[data-ops-tab="home"]').click();await p.waitForTimeout(220);assert.equal(await p.locator('#oiNew').count(),0);await p.evaluate(()=>oiFixture.delay=0);pass('Late invitation responses cannot overwrite another organization tab');
  await p.evaluate(async()=>{closeSheets();oiFixture.admin=false;oiFixture.orgAccess=false;session=fixture.session={user:{id:'leader-test',email:'leader@example.test'}};await refresh()});
  await p.locator('#inviteToken').fill(link);await p.locator('#acceptInviteBtn').click();await p.waitForSelector('#organizationInviteReview[open]');assert.equal(await p.evaluate(()=>oiFixture.accepts),0);assert.match(await p.locator('#organizationInviteReview').innerText(),/Girls program/);
  await p.locator('#oiReviewAccept').click();assert.equal(await p.evaluate(()=>oiFixture.accepts),0);await p.screenshot({path:path.join(root,'validation/organization-invitation-review-phone.png')});
  await p.locator('#oiReviewCancel').click();await p.waitForFunction(()=>!invitationBusy);assert.equal(await p.evaluate(()=>oiFixture.accepts),0);pass('Acceptance previews access, requires consent and can be cancelled without granting a role');
  await p.locator('#acceptInviteBtn').click();await p.waitForSelector('#organizationInviteReview[open]');await p.locator('#oiReviewAdult').check();await p.locator('#oiReviewAccess').check();await p.locator('#oiReviewAccept').click();await p.waitForFunction(()=>oiFixture.accepts===1&&!invitationBusy);
  assert.equal(await p.locator('#opsHubSheet').isVisible(),true);assert.equal(await p.locator('[data-ops-tab="invitations"]').count(),0);assert.equal(await p.evaluate(()=>activeTeam),null);assert.deepEqual(await p.evaluate(()=>teamMemberships),[]);
  await p.evaluate(()=>closeSheets());assert.equal(await p.locator('#setupOrganizations').isVisible(),true);await p.screenshot({path:path.join(root,'validation/organization-only-home-phone.png')});pass('Limited leader accepts directly into the organization without team membership or administrator invite tools');
  await p.evaluate(()=>{oiFixture.previewError='Sign in with the invited email.'});await p.locator('#setupChoices').evaluate(e=>e.open=true);await p.locator('#inviteToken').fill(link);await p.locator('#acceptInviteBtn').click();await p.waitForFunction(()=>!invitationBusy);assert.match(await p.locator('#setupInviteStatus').innerText(),/invited email/);assert.equal(await p.locator('#organizationInviteReview').isVisible(),false);pass('Wrong-email rejection appears in the invitation form and grants nothing');
  await p.evaluate(()=>{oiFixture.previewError=null;});await p.locator('#acceptInviteBtn').click();await p.waitForSelector('#organizationInviteReview[open]');await p.evaluate(()=>{closeSheets();session=fixture.session=null});await p.waitForFunction(()=>!invitationBusy);assert.equal(await p.locator('#organizationInviteReview').isVisible(),false);pass('Account change closes the consent dialog without granting access');
  await p.evaluate(async()=>{session=fixture.session={user:{id:'admin-test',email:'admin@example.test'}};oiFixture.admin=true;await refresh();await WMOperations.open('org-a',null,'invitations')});await p.setViewportSize({width:1024,height:900});await p.screenshot({path:path.join(root,'validation/organization-invitations-tablet.png')});
  const signupToken='WMO-'+'b'.repeat(64);
  await p.goto('https://wm.example.test/?invite='+signupToken);await p.waitForFunction(()=>typeof WMOrgInvites!=='undefined'&&!accountRefreshFlight);
  await p.evaluate(()=>fixture.confirmation=true);await p.locator('#signUpBtn').click();assert.equal(await p.locator('[data-signup-role="team_leader"]').getAttribute('aria-pressed'),'true');
  await p.locator('#signUpEmail').fill('newleader@example.test');await p.locator('#signUpPassword').fill('synthetic-test-password');await p.locator('#createPersonalAccountBtn').click();await p.waitForSelector('#confirmationNotice:not(.hidden)');
  assert.equal(await p.evaluate(()=>JSON.parse(localStorage.getItem('wm.onboarding.v1')).invite),signupToken);assert.equal(await p.evaluate(()=>oiFixture.accepts),0);
  await p.reload();await p.waitForSelector('#confirmationNotice:not(.hidden)');assert.equal(await p.evaluate(()=>pendingInviteToken),signupToken);
  await p.evaluate(async()=>{oiFixture.admin=false;oiFixture.orgAccess=false;session=fixture.session={user:{id:'new-leader',email:'newleader@example.test',user_metadata:{wm_onboarding_role:'team_leader'}}};await refresh()});
  await p.waitForSelector('#organizationInviteReview[open]');assert.equal(await p.evaluate(()=>oiFixture.accepts),0);await p.locator('#oiReviewCancel').click();await p.waitForFunction(()=>!invitationBusy);
  pass('WMO link selects leadership signup, survives email confirmation and reload, and resumes with explicit consent');
  assert.deepEqual(errors,[]);pass('Integrated app completes without JavaScript errors');
  fs.writeFileSync(path.join(root,'validation/organization-invitations-browser.json'),JSON.stringify({engine:'Chromium; complete HTML; isolated synthetic accounts and email transport',passed:checks.length,tests:checks},null,2));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
