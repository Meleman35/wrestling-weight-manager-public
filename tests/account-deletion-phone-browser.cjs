'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[],pass=s=>{passed.push(s);console.log('PASS',s);};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true}),page=await context.newPage(),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await context.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')+`\nfixture.authListeners=[];const create=window.supabase.createClient;window.supabase.createClient=(...args)=>{const c=create(...args);c.auth.onAuthStateChange=f=>{fixture.authListeners.push(f);return {data:{subscription:{unsubscribe(){}}}};};return c;};`});
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');await context.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await page.goto('https://theteammanager.app/');await page.waitForFunction(()=>window.wrestlingManagerSignInReady&&window.WMDeletionPhoneTest);
 await page.evaluate(()=>{
  session=fixture.session={user:{id:'phone-test'},access_token:'synthetic-token'};managedLogin=null;activeTeam={id:'team-test'};
  show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
  fixture.preflight={enabled:true,deletion_enabled:false,subject_id:'phone-test',checked_at:new Date().toISOString(),scope_version:1,scopes:{teams:[{id:'11111111-1111-4111-8111-111111111111',name:'Fixture team',direct_admin:true,inherited_admin:true,needs_handoff:true}],organizations:[{id:'22222222-2222-4222-8222-222222222222',name:'Fixture organization',needs_handoff:true,team_count:1,athlete_count:2}]},counts:{account_photos:1,wrestling_profile_photos:1,messages:2,message_attachments:1,team_posts:1,post_attachments:1,uploaded_objects:3,teams:1,teams_needing_handoff:1,guardian_links:0,organization_roles:0}};
  const rpc=client.rpc.bind(client);client.rpc=(name,args)=>{if(name!=='account_deletion_scope_preflight')return rpc(name,args);fixture.calls.push({name,args});const result=structuredClone({data:fixture.preflight,error:fixture.preflightError?{message:'private backend details'}:null});return fixture.holdPreflight?new Promise(resolve=>{fixture.releasePreflight=()=>resolve(result);}):Promise.resolve(result);};
 });
 await page.evaluate(()=>openAccountSheet());await page.locator('#deletionPhoneTestCard').waitFor();
 assert.equal(await page.locator('#deletionPhoneTestCard').evaluate(e=>e.tagName==='DETAILS'&&!e.open&&e.previousElementSibling.id==='signOutBtn'),true);
 assert.equal(await page.locator('[data-count="messages"]').isVisible(),false);
 await page.locator('#deletionPhoneTestCard summary').click();
 assert.match(await page.locator('#deletionPhoneTestCard').innerText(),/Deletion is not available yet/);
 assert.match(await page.locator('#deletionPhoneTestCard').innerText(),/another administrator/);
 assert.equal(await page.locator('[data-count="messages"]').innerText(),'2');assert.equal(await page.locator('#deletionPhoneTestCard button').count(),2);
 assert.equal(await page.locator('#deletionPhoneTestCard').evaluate(e=>e.lastElementChild.textContent),'Delete Account');
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 pass('Account deletion is collapsed at the bottom; expanding shows counts and the final Delete Account button at phone width');
 const rpcCount=await page.evaluate(()=>fixture.calls.length);
 await page.getByRole('button',{name:'Delete Account',exact:true}).click();
 const input=page.locator('#deletionConfirmInput'),confirm=page.getByRole('button',{name:'Confirm deletion',exact:true});
 assert.equal(await page.getByRole('dialog',{name:'Delete personal account',exact:true}).isVisible(),true);
 assert.match(await page.locator('#deletionConfirmWarning').innerText(),/permanent/);
 assert.match(await page.locator('#deletionConfirmUnavailable').innerText(),/Nothing will be deleted/);
 assert.equal(await confirm.isDisabled(),true);assert.equal(await input.evaluate(e=>e===document.activeElement),true);
 assert.equal(await page.locator('#deletionConfirmDialog').evaluate(e=>e.scrollWidth<=e.clientWidth&&e.getBoundingClientRect().width<=innerWidth),true);
 for(const text of ['dele','DELETE',' delete','delete ']){await input.fill(text);assert.equal(await confirm.isDisabled(),true);}
 await input.fill('delete');assert.equal(await confirm.isEnabled(),true);await input.press('Enter');
 await page.getByText('This action is not available yet. Nothing has been changed, deleted or scheduled for deletion.',{exact:true}).waitFor();
 assert.equal(await input.inputValue(),'');assert.equal(await confirm.isDisabled(),true);
 assert.equal(await page.evaluate(()=>fixture.calls.length),rpcCount);assert.equal(await page.evaluate(()=>fixture.writes.length),0);
 pass('Warning dialog requires exact lowercase delete; Enter reports unavailable without any request, deletion or saved consent');
 await input.fill('delete');await confirm.click();assert.match(await page.locator('#deletionConfirmStatus').innerText(),/Nothing has been changed, deleted or scheduled/);
 await input.fill('delete');await page.getByRole('button',{name:'Cancel',exact:true}).click();assert.equal(await page.locator('#deletionConfirmDialog').count(),0);
 assert.equal(await page.getByRole('button',{name:'Delete Account',exact:true}).evaluate(e=>e===document.activeElement),true);
 await page.getByRole('button',{name:'Delete Account',exact:true}).click();assert.equal(await input.inputValue(),'');await input.press('Escape');assert.equal(await page.locator('#deletionConfirmDialog').count(),0);
 await page.getByRole('button',{name:'Delete Account',exact:true}).click();await input.fill('delete');await page.evaluate(()=>fixture.authListeners.at(-1)('SIGNED_OUT',null));assert.equal(await page.locator('#deletionConfirmDialog').count(),0);assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);
 await page.evaluate(()=>openAccountSheet());await page.locator('#deletionPhoneTestCard').waitFor();assert.equal(await page.locator('#deletionPhoneTestCard').evaluate(e=>e.open),false);await page.locator('#deletionPhoneTestCard summary').click();
 pass('Button confirmation stays non-destructive; Cancel, Escape and auth changes clear typed text, and reopening is collapsed');
 await page.getByRole('button',{name:'Delete Account',exact:true}).click();
 assert.match(await page.locator('#deletionConfirmWarning').innerText(),/ALL teams and organizations/);
 assert.match(await page.locator('#deletionConfirmWarning').innerText(),/linked children’s profiles are not deleted/);
 assert.match(await page.locator('#deletionConfirmDialog').innerText(),/Fixture organization/);
 await input.press('Escape');
 const scopeType=page.locator('#deletionScopeType'),target=page.locator('#deletionScopeTarget');
 for(const [kind,value,button,title,kept] of [
  ['administrator','team:11111111-1111-4111-8111-111111111111','Remove administrator access','Remove administrator access',/personal account, sign-in and personal profile stay/],
  ['team','team:11111111-1111-4111-8111-111111111111','Delete Team','Delete team',/people who belong only to this team/],
  ['organization','organization:22222222-2222-4222-8222-222222222222','Delete Organization','Delete organization',/does not automatically delete them or shared athlete profiles/]
 ]){
  await scopeType.selectOption(kind);assert.equal(await page.getByRole('button',{name:button,exact:true}).isDisabled(),true);
  await target.selectOption(value);await page.getByRole('button',{name:button,exact:true}).click();
  assert.equal(await page.getByRole('dialog',{name:title,exact:true}).isVisible(),true);
  assert.match(await page.locator('#deletionConfirmWarning').innerText(),kept);
  if(kind==='administrator')assert.match(await page.locator('#deletionConfirmDialog').innerText(),/organization access/);
  if(kind==='organization')assert.match(await page.locator('#deletionConfirmDialog').innerText(),/2 linked athlete/);
  assert.equal(await input.inputValue(),'');await input.fill('delete');await input.press('Enter');
  assert.match(await page.locator('#deletionConfirmStatus').innerText(),/Nothing has been changed/);
  await input.press('Escape');
 }
 await scopeType.selectOption('administrator');await target.selectOption('organization:22222222-2222-4222-8222-222222222222');
 await page.getByRole('button',{name:'Remove administrator access',exact:true}).click();
 assert.match(await page.locator('#deletionConfirmDialog').innerText(),/last administrator/);
 await input.fill('delete');await page.evaluate(()=>{const s=document.getElementById('deletionScopeType');s.value='personal';s.dispatchEvent(new Event('change'));});
 assert.equal(await page.locator('#deletionConfirmDialog').count(),0);
 assert.equal(await page.evaluate(()=>fixture.calls.length),rpcCount+1); // reopening the account sheet refreshed once
 assert.equal(await page.evaluate(()=>fixture.writes.length),0);
 pass('Four separate scopes require a specific workspace, preserve other people’s profiles, explain inherited access and clear confirmation on scope changes');
 await page.evaluate(()=>{fixture.savedScopes=structuredClone(fixture.preflight.scopes);fixture.preflight.scopes={teams:[],organizations:[]};return WMDeletionPhoneTest.refresh();});
 assert.equal(await scopeType.inputValue(),'personal');assert.equal(await page.locator('#deletionScopeType option:disabled').count(),3);
 assert.equal(await page.getByRole('button',{name:'Delete Account',exact:true}).isEnabled(),true);
 await page.evaluate(()=>{fixture.preflight.scopes=fixture.savedScopes;return WMDeletionPhoneTest.refresh();});
 pass('Personal-only accounts keep the personal deletion option without administrator or workspace targets');

 await page.evaluate(()=>{fixture.preflight.counts.messages=4;});await page.getByRole('button',{name:'Refresh stored data'}).click();await page.waitForFunction(()=>document.querySelector('[data-count="messages"]').textContent==='4');
 assert.equal(await page.evaluate(()=>fixture.calls.filter(x=>x.name==='account_deletion_scope_preflight').every(x=>x.args===undefined)),true);
 pass('Refresh reads current own-account counts through the argument-free RPC');
 await page.evaluate(()=>{fixture.preflightError=true;});await page.getByRole('button',{name:'Refresh stored data'}).click();await page.getByText('Stored data could not be checked. Reconnect and try again.').waitFor();
 assert.equal(await page.locator('[data-count]').count(),0);assert.ok(!(await page.locator('#deletionPhoneTestCard').innerText()).includes('private backend details'));
 await page.evaluate(()=>{fixture.preflightError=false;fixture.preflight.subject_id='other-person';return WMDeletionPhoneTest.refresh();});assert.equal(await page.locator('[data-count]').count(),0);
 await page.evaluate(()=>{fixture.preflight.subject_id='phone-test';fixture.preflight.scope_version=999;return WMDeletionPhoneTest.refresh();});assert.equal(await page.locator('#deletionScopeType').count(),0);
 await page.evaluate(()=>{fixture.preflight.scope_version=1;});
 await page.evaluate(()=>{fixture.preflight.subject_id='phone-test';fixture.preflight.enabled=false;return WMDeletionPhoneTest.refresh();});assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);
 pass('Errors clear old counts; wrong identities and unenrolled accounts cannot display an inventory');
 await page.evaluate(()=>{fixture.preflight.enabled=true;fixture.holdPreflight=true;fixture.pendingPreflight=WMDeletionPhoneTest.refresh();});await page.waitForFunction(()=>!!fixture.releasePreflight);
 await page.evaluate(()=>{session={user:{id:'other-person'},access_token:'other-token'};WMDeletionPhoneTest.reset();fixture.releasePreflight();return fixture.pendingPreflight;});assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);
 await page.evaluate(()=>{session=fixture.session;fixture.holdPreflight=false;return WMDeletionPhoneTest.refresh();});await page.locator('#deletionPhoneTestCard').waitFor();
 await page.locator('#deletionPhoneTestCard summary').click();await page.getByRole('button',{name:'Delete Account',exact:true}).click();await input.fill('delete');
 await page.evaluate(()=>lockApp());assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);
 assert.equal(await page.locator('#deletionConfirmDialog').count(),0);
 pass('Account switching discards in-flight responses and app locking clears the inventory and confirmation immediately');
 await page.evaluate(()=>{show('appLockOverlay',false);managedLogin={id:'managed'};return WMDeletionPhoneTest.refresh();});assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);
 await page.evaluate(()=>{managedLogin=null;return WMDeletionPhoneTest.refresh();});await page.locator('#deletionPhoneTestCard').waitFor();
 await page.locator('#deletionPhoneTestCard summary').click();await page.getByRole('button',{name:'Delete Account',exact:true}).click();await input.fill('delete');
 await page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);
 assert.equal(await page.locator('#deletionConfirmDialog').count(),0);
 assert.deepEqual(errors,[]);assert.equal(await page.evaluate(()=>fixture.writes.length),0);
 pass('Managed login and page exit clear the view; no live calls, data writes or page errors occur');
 fs.writeFileSync(path.join(root,'validation/account-deletion-phone-browser.json'),JSON.stringify({passed,errors,engine:'Chromium actual bundled UI, synthetic responses, phone viewport',physicalPhoneTest:false,productionDataChanged:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
