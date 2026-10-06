// Synthetic browser only: public information must not require sign-in or mutate data.
const fs=require('fs'),path=require('node:path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));fs.mkdirSync('validation',{recursive:true});
 await ctx.addInitScript({content:fs.readFileSync('tests/browser-fixture.js','utf8')});
 await p.route('**/*',r=>{
  if(r.request().isNavigationRequest()){
   const path=new URL(r.request().url()).pathname;
   const file=path.endsWith('/privacy.html')?'privacy.html':path.endsWith('/support.html')?'support.html':'index.html';
   return r.fulfill({contentType:'text/html',body:fs.readFileSync(file,'utf8')});
  }
  if(r.request().url().includes('supabase-js')||r.request().url().includes('/vendor/supabase.js'))return r.fulfill({contentType:'text/javascript',body:''});
  const modulePath=new URL(r.request().url()).pathname;
  if(/^\/(src|billing-candidate)\/[a-z0-9-]+\.mjs$/.test(modulePath)){
   return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(path.join(process.cwd(),modulePath.slice(1)),'utf8')});
  }
  return r.abort();
 });
 for(const kind of ['support','privacy']){
  await p.goto('https://wm.example.test/'+kind+'.html');
  assert.equal(await p.locator('h1').count(),1);
  assert((await p.locator('main').innerText()).includes('Mele Sports Technologies LLC'));
  assert((await p.locator('main').innerText()).includes('October 5, 2026'));
  assert.equal(await p.locator('input,form').count(),0);
  assert.equal(await p.locator('script').count(),0);
  assert(await p.locator('a[href^="mailto:support@theteammanager.app"]').count()>0);
  for(const width of [320,390,768]){
   await p.setViewportSize({width,height:844});
   assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'overflow: '+kind+' '+width);
  }
  await p.setViewportSize({width:390,height:844});await p.screenshot({path:'validation/launch-'+kind+'-phone.png'});
 }
 console.log('PASS Public Support and Privacy have current contact, readable phone/tablet layouts and no forms/scripts');
 await p.goto('https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
 await p.waitForFunction(()=>!!window.WMSubscriptionPlans);
 assert.equal(await p.locator('#remoteReportingBtn,#remoteReportingSheet').count(),0);
 assert.equal(await p.evaluate(()=>typeof window.WMRemoteReporting),'undefined');
 assert.equal(await p.evaluate(()=>performance.getEntriesByType('resource').some(r=>/remote-weighins/.test(r.name))),false);
 console.log('PASS Core launch loads Plans without registering remote reporting or loading its client');
 for(const [kind,id] of [['support','wmSupportTemplate'],['privacy','wmPrivacyTemplate']]){
  const file=fs.readFileSync(kind+'.html','utf8'),expected=file.match(/<\/nav>([\s\S]*?)<footer class="wm-doc-footer">/)[1];
  assert.equal(await p.locator('#'+id).evaluate(el=>el.innerHTML),await p.evaluate(html=>{const t=document.createElement('template');t.innerHTML=html;return t.innerHTML},expected));
  await p.locator('#authView [data-wm-info="'+kind+'"]').click();
  await p.waitForSelector('#wmInfoOverlay:not([hidden])');
  const text=await p.locator('#wmInfoContent').innerText();
  assert(text.includes('My Account → Account deletion'));
  assert(text.includes('deployed'));
  assert(!text.includes('specifically enrolled'));
  assert(text.includes('Apple subscription'));
  if(kind==='privacy'){assert(text.includes('Render'));assert(text.includes('Production subscriptions remain disabled'));}
  assert(!text.includes('A complete in-app account-deletion workflow is not available yet'));
  assert.equal(await p.evaluate(()=>session),null);
  assert.equal(await p.evaluate(()=>fixture.writes.length),0);
  await p.locator('#wmInfoClose').click();
  assert.equal(await p.locator('#wmInfoOverlay').isVisible(),false);
 }
 console.log('PASS Sign-in links open synchronized information without sign-in, writes, accounts, or live records');
 await p.locator('#authView [data-wm-info="support"]').click();
 await p.locator('#wmInfoContent [data-wm-info="privacy"]').click();
 assert((await p.locator('#wmInfoContent').innerText()).includes('Younger athletes and guardian authority'));
 await ctx.setOffline(true);
 assert((await p.locator('#wmInfoContent').innerText()).includes('support@theteammanager.app'));
 await p.keyboard.press('Escape');assert.equal(await p.locator('#wmInfoOverlay').isVisible(),false);
 await ctx.setOffline(false);
 await p.locator('#authView [data-wm-info="support"]').click();
 await p.evaluate(()=>document.body.classList.add('kiosk-locked'));
 await p.waitForSelector('#wmInfoOverlay[hidden]',{state:'attached'});
 assert.equal(await p.evaluate(()=>fixture.writes.length),0);
 assert.deepEqual(errors,[]);
 console.log('PASS Cross-links, offline-readable loaded content, Escape, and app-lock dismissal preserve account state');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
