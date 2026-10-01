'use strict';
// Actual embedded page; synthetic Auth and native transport. No real deletion.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222';
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true}),page=await context.newPage(),errors=[],passed=[];
 page.on('pageerror',e=>errors.push(e.message));
 await context.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')});
 let serverWrites=0;
 await context.route('**/*',route=>{
  if(route.request().url().includes('/functions/v1/scoped-deletion'))serverWrites++;
  return route.request().isNavigationRequest()?route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):route.request().url().includes('supabase')?route.fulfill({contentType:'text/javascript',body:''}):route.abort();
 });
 try{
  await page.goto('https://theteammanager.app/');await page.waitForFunction(()=>window.wrestlingManagerSignInReady&&window.WMScopedDeletion);
  await page.evaluate(({A,B})=>{
   session=fixture.session={user:{id:A,email:'disposable@example.invalid'},access_token:'synthetic-token'};managedLogin=null;activeTeam=null;
   show('authView',false);show('appView',false);show('setupView',true);show('appLockOverlay',false);
   fixture.preflight={enabled:true,deletion_enabled:true,subject_id:A,checked_at:new Date().toISOString(),scope_version:1,scopes:{teams:[],organizations:[]},actions:{personal:true,administrator:true,team:true,organization:true,all:true},counts:{account_photos:0,wrestling_profile_photos:0,messages:0,message_attachments:0,team_posts:0,post_attachments:0,uploaded_objects:0,teams:0,teams_needing_handoff:0,guardian_links:0,organization_roles:0}};
   const rpc=client.rpc.bind(client);client.rpc=(name,args)=>name==='account_deletion_scope_preflight'?Promise.resolve({data:structuredClone(fixture.preflight),error:null}):rpc(name,args);
   fixture.nativeCalls=[];fixture.nativeCancel=true;fixture.signouts=0;
   client.auth.signOut=async()=>{fixture.signouts++;session=fixture.session=null;return {error:null};};
   const digest=async text=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),x=>x.toString(16).padStart(2,'0')).join('');
   window.wrestlingManagerNativeShellVersion='synthetic';
   window.webkit={messageHandlers:{wmAccountDeletion:{postMessage:async msg=>{
    fixture.nativeCalls.push(msg);const respond=value=>wrestlingManagerDeletionResponse({id:msg.id,ok:true,value});
    if(msg.command==='begin'){
     if(fixture.nativeCancel)return wrestlingManagerDeletionResponse({id:msg.id,ok:false,error:'Deletion cancelled.',code:'native_not_started'});
     fixture.nativeJob=msg.job;return respond({state:'planning'});
    }
    if(msg.command==='recover')return respond({state:'completed',personal:true,subjectHash:await digest(A),nativeComplete:true,loginEmailHash:await digest('disposable@example.invalid')});
    if(msg.command==='acknowledge')return respond({acknowledged:true});
    if(msg.command==='pending')return respond({jobs:[]});
   }}}};
   localStorage.setItem('wm_login_email','disposable@example.invalid');
   localStorage.setItem('wm.profile-pin.v1:'+A,'own');localStorage.setItem('wm.profile-pin.v1:'+B,'other');
  },{A,B});
  await page.getByRole('button',{name:'My Account',exact:true}).click();
  await page.locator('#deletionPhoneTestCard').waitFor();await page.locator('#deletionPhoneTestCard summary').click();
  assert.match(await page.locator('#deletionPhoneTestCard').innerText(),/enabled for this test account in this app/);
  assert.equal(await page.locator('[data-count="teams"]').innerText(),'0');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  passed.push('A teamless account opens My Account from setup and reviews native test counts at phone width');
  await page.getByRole('button',{name:'Delete Account',exact:true}).click();
  await page.locator('#deletionConfirmInput').fill('delete');await page.getByRole('button',{name:'Confirm deletion',exact:true}).click();
  await page.getByText('Deletion cancelled.',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>fixture.signouts),0);
  assert.equal(await page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('wm-deletion-resume-v1:'))),false);
  passed.push('Cancelling native confirmation retains the account and clears the unstarted browser intent');
  await page.evaluate(()=>fixture.preflight.enabled=false);
  await page.locator('#deletionConfirmInput').fill('delete');await page.getByRole('button',{name:'Confirm deletion',exact:true}).click();
  await page.getByText('Deletion has not been enabled for this account.',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>fixture.nativeCalls.filter(c=>c.command==='begin').length),1);
  passed.push('Enrollment revoked after opening the dialog blocks intake at submission');
  await page.evaluate(async({A,B})=>{fixture.preflight.enabled=true;fixture.nativeCancel=false;await WMOfflineStore.update(A,b=>{b.drafts.own='erase';});await WMOfflineStore.update(B,b=>{b.drafts.other='keep';});},{A,B});
  await page.locator('#deletionConfirmInput').fill('delete');await page.getByRole('button',{name:'Confirm deletion',exact:true}).click();
  await page.getByText(/This app removed the account’s saved sign-in/).waitFor();
  assert.equal(await page.evaluate(()=>fixture.signouts),1);
  assert.equal(await page.evaluate(()=>fixture.nativeJob.actorId),A);
  assert.equal(await page.evaluate(()=>fixture.nativeJob.kind),'personal');
  assert.deepEqual(await page.evaluate(()=>fixture.nativeJob.teamIds),[]);
  assert.equal(await page.evaluate(()=>fixture.nativeCalls.at(-1).command),'acknowledge');
  assert.equal(await page.evaluate(A=>localStorage.getItem('wm.profile-pin.v1:'+A),A),null);
  assert.equal(await page.evaluate(B=>localStorage.getItem('wm.profile-pin.v1:'+B),B),'other');
  assert.equal(await page.evaluate(async B=>(await WMOfflineStore.get(B)).drafts.other,B),'keep');
  assert.equal(await page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('wm-deletion-resume-v1:'))),false);
  assert.equal(await page.evaluate(()=>localStorage.getItem('wm_login_email')),null);
  assert.equal(serverWrites,0);assert.deepEqual(errors,[]);
  passed.push('Native owns server transport; verified completion clears the matching account, preserves another account and acknowledges');
  fs.writeFileSync(path.join(root,'validation/account-deletion-native-browser.json'),JSON.stringify({passed,width:390,nativeTransport:'simulated',physicalDeviceTested:false,realAccountChanged:false},null,2));
  for(const p of passed)console.log('PASS',p);
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
