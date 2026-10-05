const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),referral='https://join.zeffy.com/ahiq6lm6xo6a';
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 try{
  const context=await browser.newContext({viewport:{width:390,height:844}}),page=await context.newPage(),errors=[],outgoing=[];
  page.on('pageerror',e=>errors.push(e.message));
  await context.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')});
  await context.route('**/*',async route=>{
   const request=route.request(),url=new URL(request.url());
   if(url.href===referral){outgoing.push({url:url.href,headers:await request.allHeaders()});return route.fulfill({contentType:'text/html',body:'<h1>Synthetic Zeffy destination</h1>'});}
   if(url.origin==='https://wm.example.test'&&request.isNavigationRequest())return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,url.pathname==='/welcome.html'?'welcome.html':'index.html'),'utf8')});
   if(url.href.includes('supabase'))return route.fulfill({contentType:'text/javascript',body:''});
   return route.abort();
  });
  await page.goto('https://wm.example.test/');
  await page.waitForFunction(()=>window.WMFundraising&&window.WMClipboard&&!accountRefreshFlight);
  await page.evaluate(()=>{
   session=fixture.session={user:{id:'synthetic-coach',email:'coach@example.test'},access_token:'synthetic-private-token'};
   activeTeam={id:'synthetic-team',name:'Synthetic Team'};isStaff=actualIsStaff=isTeamAdmin=actualIsTeamAdmin=true;isManager=false;managedLogin=null;viewMode='staff';
   show('authView',false);show('appView',true);show('appLockOverlay',false);applyRoleUI();setTab('more');
  });
  const writes=await page.evaluate(()=>fixture.writes.length);
  await page.locator('[data-clipboard-category="fundraising"]').click();
  assert.equal(await page.locator('#fundraisingSheet').isVisible(),true);
  async function checkCard(container){
   const link=container.getByRole('link',{name:'Start fundraising with Zeffy'});
   assert.equal(await link.getAttribute('href'),referral);
   assert.match(await container.innerText(),/Referral disclosure: Mele Sports Technologies LLC may earn a commission/);
   for(const width of [320,390,768]){
    await page.setViewportSize({width,height:950});
    assert.equal(await container.evaluate(e=>e.scrollWidth<=e.clientWidth+1),true);
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);
   }
   const popupPromise=context.waitForEvent('page');await link.click();const popup=await popupPromise;
   await popup.getByRole('heading',{name:'Synthetic Zeffy destination'}).waitFor();
   assert.equal(await popup.evaluate(()=>window.opener),null);await popup.close();
   assert.equal(page.url().startsWith('https://wm.example.test/'),true);
  }
  await checkCard(page.locator('#fundraisingContent'));
  await page.locator('#fundraisingContent summary').click();
  assert.equal(await page.getByRole('textbox',{name:'Zeffy referral link'}).inputValue(),referral);
  await page.locator('#fundraisingSheet').screenshot({path:path.join(root,'validation/fundraising-clipboard.png')});
  await page.evaluate(()=>{closeSheets();managedLogin={id:'synthetic-device'};WMFundraising.open()});
  assert.equal(await page.locator('#fundraisingSheet').isVisible(),false);
  await page.evaluate(()=>{managedLogin=null;isStaff=actualIsStaff=isTeamAdmin=actualIsTeamAdmin=false;viewMode='athlete';applyRoleUI();WMFundraising.open()});
  assert.equal(await page.locator('#fundraisingSheet').isVisible(),false);
  assert.equal(await page.locator('#clipboardCategories').isVisible(),false);
  await page.evaluate(async()=>{isStaff=actualIsStaff=true;viewMode='staff';await WMOperations.open('org-a')});
  await page.locator('[data-ops-home="fundraising"]').click();
  assert.equal(await page.locator('[data-ops-section="programs"]').getAttribute('aria-current'),'page');
  await checkCard(page.locator('#opsContent'));
  await page.locator('#opsHubSheet').screenshot({path:path.join(root,'validation/fundraising-board-room.png')});
  await page.locator('[data-ops-section="home"]').click();
  await page.locator('[data-ops-section="programs"]').click();await page.locator('[data-ops-tab="fundraising"]').click();
  assert.equal(await page.locator('#opsContent .wm-fundraising-link').isVisible(),true);
  assert.equal(await page.evaluate(()=>fixture.writes.length),writes);
  await page.goto('https://wm.example.test/welcome.html');await checkCard(page.locator('#fundraising'));
  assert.equal(outgoing.length,3);
  assert.equal(outgoing.every(x=>x.url===referral&&!x.headers.referer&&!x.headers.authorization),true);
  assert.deepEqual(errors,[]);
  console.log('PASS website, Clipboard and both Board Room entry paths; 320/390/768 layouts; disclosed exact referral links; preserved app window; no account data or writes; old-build copy fallback. Zeffy destination is intercepted, no signup is performed.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
