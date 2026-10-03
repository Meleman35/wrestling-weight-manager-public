'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
 await context.addCookies([{name:'update-test-cookie',value:'must-not-send',domain:'theteammanager.app',path:'/'}]);
 await context.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')+`\nObject.defineProperty(navigator,'serviceWorker',{value:{register:()=>Promise.reject(Error('Synthetic registration disabled'))}});`});
 const page=await context.newPage(),errors=[],requests=[];let mode='current',release=null;
 page.on('pageerror',e=>errors.push(e.message));
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 await context.route('**/*',async route=>{
  const req=route.request();
  if(req.isNavigationRequest())return route.fulfill({contentType:'text/html',body:html});
  if(new URL(req.url()).pathname==='/sw.js'){
   requests.push({url:req.url(),headers:await req.allHeaders()});const selected=mode;
   if(selected==='hold'||selected==='timeout')await new Promise(resolve=>{release=resolve;});
   try{return await route.fulfill({status:selected==='error'?503:200,contentType:'text/javascript',body:selected==='malformed'?"private backend text":`const CACHE='wm-shell-${selected==='newer'?'0.20.120':selected==='major'?'1.0.0':selected==='older'?'0.20.99':'0.20.119'}';`});}catch{return;}
  }
  if(req.url().includes('supabase'))return route.fulfill({contentType:'text/javascript',body:''});
  return route.abort();
 });
 await page.goto('https://theteammanager.app/');await page.waitForFunction(()=>window.wrestlingManagerSignInReady&&window.WMWebUpdates);
 assert.equal(requests.length,0,'No update poll or initial network request before Account opens');
 await page.evaluate(()=>{session=fixture.session={user:{id:'update-test'},access_token:'synthetic'};managedLogin=null;show('appLockOverlay',false);localStorage.setItem('synthetic.unsynced.draft','keep this work');openAccountSheet();});
 const card=page.locator('#webUpdatesCard'),status=page.locator('#webUpdatesStatus'),button=page.locator('#webUpdatesCheck');
 await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='current');
 assert.match(await status.innerText(),/matches the published web version/);
 const baseline=await page.evaluate(()=>({calls:fixture.calls.length,writes:fixture.writes.length}));
 if(!(await page.locator('.account-profile-editor').evaluate(e=>e.open)))await page.locator('.account-profile-editor summary').click();
 await page.locator('#accountDisplayName').fill('Unsaved synthetic edit');
 mode='newer';await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='available');
 assert.match(await status.innerText(),/0.20.120/);assert.match(await status.innerText(),/Save unfinished work/);assert.match(await status.innerText(),/close all/);
 for(const width of [320,390,768]){await page.setViewportSize({width,height:844});await card.scrollIntoViewIfNeeded();assert.equal(await card.evaluate(e=>e.scrollWidth<=e.clientWidth),true);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);}
 await page.setViewportSize({width:390,height:844});await card.screenshot({path:path.join(root,'validation/web-updates-phone.png')});
 assert.equal(await page.locator('#accountDisplayName').inputValue(),'Unsaved synthetic edit');
 assert.equal(await page.evaluate(()=>localStorage.getItem('synthetic.unsynced.draft')),'keep this work');
 assert.deepEqual(await page.evaluate(()=>({calls:fixture.calls.length,writes:fixture.writes.length})),baseline);
 assert.equal(requests.every(x=>!x.headers.cookie&&!x.headers.authorization),true);
 mode='major';await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesStatus').textContent.includes('1.0.0'));
 mode='older';await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='unconfirmed');
 assert.match(await status.innerText(),/older/);
 for(const value of ['malformed','error']){mode=value;await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='error');assert.ok(!(await status.innerText()).includes('private backend'));assert.equal(await button.isEnabled(),true);}
 const count=requests.length;await context.setOffline(true);await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='offline');assert.equal(requests.length,count);await context.setOffline(false);
 mode='current';await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='current');
 mode='hold';release=null;await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='checking');
 while(!release)await page.waitForTimeout(20);
 await page.evaluate(()=>closeSheets());release();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='idle');
 assert.equal(await button.isEnabled(),true);
 mode='current';await page.evaluate(()=>openAccountSheet());await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='current');
 if(!(await page.locator('.account-profile-editor').evaluate(e=>e.open)))await page.locator('.account-profile-editor summary').click();
 await page.locator('#accountDisplayName').fill('Unsaved synthetic edit');
 await page.evaluate(()=>{const original=window.setTimeout;window.setTimeout=(f,ms,...args)=>original(f,ms===8000?80:ms,...args);});
 mode='timeout';release=null;await button.click();await page.waitForFunction(()=>document.getElementById('webUpdatesCard').dataset.updateState==='error');assert.match(await status.innerText(),/timed out/);release?.();
 assert.equal(await page.locator('#accountDisplayName').inputValue(),'Unsaved synthetic edit');
 assert.equal(await page.evaluate(()=>localStorage.getItem('synthetic.unsynced.draft')),'keep this work');
 assert.deepEqual(errors,[]);
 const source=fs.readFileSync(path.join(root,'src/web-updates.js'),'utf8');
 for(const forbidden of ['location.reload','skipWaiting','postMessage','localStorage.','indexedDB.','client.rpc','caches.delete','setInterval'])assert.ok(!source.includes(forbidden),forbidden);
 fs.writeFileSync(path.join(root,'validation/web-updates-browser.json'),JSON.stringify({passed:['current/newer/major/older version states','no initial polling or credentials','retry after malformed/server/offline errors','timeout and late-result cancellation','sheet-close cancellation','typed edit/draft preservation','320/390/768 layouts'],errors,physicalPhoneTest:false,productionDataChanged:false},null,2));
 console.log('PASS bundled web-update status, lifecycle, preserved work and phone layouts');await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
