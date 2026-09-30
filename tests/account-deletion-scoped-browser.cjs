'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222',T='33333333-3333-4333-8333-333333333333',J='44444444-4444-4444-8444-444444444444';
const hash=id=>createHash('sha256').update(id).digest('hex');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const passed=[];
 async function setup({personal=false,lost=false,wrong=false}={}){
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  await context.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')});
  const page=await context.newPage(),calls=[],errors=[];page.on('pageerror',e=>errors.push(e.message));
  await context.route('**/*',async route=>{
   if(route.request().isNavigationRequest())return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')});
   if(route.request().url().endsWith('/functions/v1/scoped-deletion')){
    const input=route.request().postDataJSON();calls.push(input);
    if(input.action==='begin'){if(lost)return route.abort();return route.fulfill({status:202,contentType:'application/json',body:JSON.stringify({id:J,state:'planning'})});}
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:J,state:'completed',personal,subjectHash:hash(wrong?B:A)})});
   }
   return route.request().url().includes('supabase')?route.fulfill({contentType:'text/javascript',body:''}):route.abort();
  });
  await page.goto('https://theteammanager.app/');await page.waitForFunction(()=>window.WMScopedDeletion&&window.WMOfflineStore);
  await page.evaluate(({A,B})=>{
   session=fixture.session={user:{id:A},access_token:'synthetic-token'};managedLogin=null;show('appLockOverlay',false);
   fixture.signouts=0;fixture.refreshes=0;client.auth.signOut=async()=>{fixture.signouts++;session=null;fixture.session=null;return {error:null};};
   refreshAccountView=async()=>{fixture.refreshes++;};
   localStorage.setItem('unrelated','keep');localStorage.setItem('wm-match-draft-v1:'+A+':team','own');localStorage.setItem('wm-match-draft-v1:'+B+':team','other');
  },{A,B});
  return {context,page,calls,errors};
 }
 try{
  let x=await setup();
  await x.page.evaluate(T=>WMScopedDeletion.begin({kind:'team',targetKind:'team',id:T}),T);
  await x.page.getByText('The selected workspace has been deleted. Personal accounts and profiles remain.',{exact:true}).waitFor();
  assert.equal(x.calls.length,2);assert.deepEqual(x.calls[0].teamIds,[T]);assert.deepEqual(x.calls[0].organizationIds,[]);assert.equal(x.calls[0].confirmation,'delete');assert.equal(x.calls[1].requestId,x.calls[0].requestId);assert.equal(x.calls[1].receipt,x.calls[0].receipt);
  assert.equal(await x.page.evaluate(()=>fixture.signouts),0);assert.equal(await x.page.evaluate(()=>fixture.refreshes),1);
  assert.equal(await x.page.evaluate(()=>localStorage.getItem('unrelated')),'keep');assert.deepEqual(x.errors,[]);await x.context.close();passed.push('Workspace completion preserves the login and other local accounts, refreshes membership state, and sends only the selected scope');
  x=await setup({personal:true});
  await x.page.evaluate(async({A,B})=>{await WMOfflineStore.update(A,b=>{b.drafts.own='Erase me';});await WMOfflineStore.update(B,b=>{b.drafts.other='Keep me';});},{A,B});
  await x.page.evaluate(()=>WMScopedDeletion.begin({kind:'personal'}));
  await x.page.getByText(/Your server account, selected records and files have been deleted/).waitFor();
  assert.equal(await x.page.evaluate(()=>fixture.signouts),1);
  assert.equal(await x.page.evaluate(async B=>(await WMOfflineStore.get(B)).drafts.other,B),'Keep me');
  assert.equal(await x.page.evaluate(A=>localStorage.getItem('wm-match-draft-v1:'+A+':team'),A),null);
  assert.equal(await x.page.evaluate(B=>localStorage.getItem('wm-match-draft-v1:'+B+':team'),B),'other');
  assert.equal(await x.page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('wm-deletion-resume-v1:'))),false);
  assert.deepEqual(x.errors,[]);await x.context.close();passed.push('Matched personal completion erases only its encrypted offline slot and local drafts, keeps another account’s drafts and signs out locally');
  x=await setup({personal:true,wrong:true});
  await x.page.evaluate(()=>WMScopedDeletion.begin({kind:'personal'}));
  await x.page.getByText('The deletion receipt did not match this account.',{exact:true}).waitFor();assert.equal(await x.page.evaluate(()=>fixture.signouts),0);
  assert.equal(await x.page.evaluate(A=>localStorage.getItem('wm-match-draft-v1:'+A+':team'),A),'own');await x.context.close();passed.push('A mismatched completion receipt cannot erase local data or sign out another account');
  x=await setup({lost:true});
  await x.page.evaluate(T=>WMScopedDeletion.begin({kind:'team',targetKind:'team',id:T}),T);
  assert.equal(await x.page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('wm-deletion-resume-v1:')).length),1);
  await x.page.getByRole('button',{name:'Resume deletion',exact:true}).click();await x.page.getByText('The selected workspace has been deleted. Personal accounts and profiles remain.',{exact:true}).waitFor();
  assert.equal(x.calls.filter(x=>x.action==='begin').length,1);assert.equal(x.calls[1].requestId,x.calls[0].requestId);await x.context.close();passed.push('A lost start response retains the original receipt and recovers the same job without a second deletion request');
  x=await setup();
  const native=await x.page.evaluate(async()=>{window.wrestlingManagerNativeShellVersion='synthetic';try{await WMScopedDeletion.begin({kind:'personal'});return '';}catch(e){return e.message;}});
  assert.match(native,/Use Safari/);assert.equal(x.calls.length,0);await x.context.close();passed.push('Native builds without verified file cleanup are blocked before a request or receipt is created');
  fs.writeFileSync(path.join(root,'validation/account-deletion-scoped-browser.json'),JSON.stringify({passed,width:390,realAccountChanged:false},null,2));for(const p of passed)console.log('PASS',p);
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
