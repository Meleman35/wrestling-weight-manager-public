'use strict';
// Exercise the shipped HTML with synthetic auth/bridge and device-local records.
// No real account, server scoring session, or native file is changed.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),read=name=>fs.readFileSync(path.join(root,name),'utf8');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const passed=[],errors=[];
 async function setup(native=false,storage={}){
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,acceptDownloads:true});
  await context.addInitScript({content:read('tests/browser-fixture.js')});
  await context.addInitScript(({native,storage})=>{
   for(const [key,value] of Object.entries(storage))if(localStorage.getItem(key)===null)localStorage.setItem(key,value);
   window.matCalls=[];
   if(native)window.webkit={messageHandlers:{offlineMatMode:{postMessage:msg=>{if(window.failMatOpen)throw Error('Unavailable');matCalls.push(msg);}}}};
  },{native,storage});
  await context.route('**/*',route=>{
   const url=new URL(route.request().url());
   if(route.request().isNavigationRequest())return route.fulfill({contentType:'text/html',body:read(url.pathname.endsWith('mat-mode.html')?'mat-mode.html':'index.html')});
   return url.pathname.endsWith('supabase.js')?route.fulfill({contentType:'text/javascript',body:''}):route.abort();
  });
  const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.goto('https://theteammanager.app/');
  return {context,page};
 }
 try{
  const app=await setup(true),page=app.page;
  await page.waitForFunction(()=>window.wrestlingManagerSignInReady);
  await page.locator('.wm-info-links [data-wm-mat-mode]').click();
  assert.deepEqual(await page.evaluate(()=>matCalls),[{command:'open'}]);
  assert.equal(page.url(),'https://theteammanager.app/');
  await page.evaluate(()=>{openSheet('accountSheet');});
  await page.getByRole('link',{name:'Enter Mat Mode',exact:true}).click();
  assert.equal(await page.evaluate(()=>matCalls.length),2);
  passed.push('Sign-in and Account links open native Mat Mode without navigating the app');
  await page.evaluate(()=>{window.failMatOpen=true;});
  await page.getByRole('link',{name:'Enter Mat Mode',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Mat Mode could not open.'}).waitFor();
  assert.equal(page.url(),'https://theteammanager.app/');
  assert.equal(await page.evaluate(()=>matCalls.length),2);
  await page.evaluate(()=>{window.failMatOpen=false;});
  await page.getByRole('link',{name:'Enter Mat Mode',exact:true}).click();
  assert.equal(await page.locator('#wmMatEntryStatus').count(),0);
  passed.push('A failed bridge shows a retry message without falling into the old web scorebook');
  const bypass=await page.evaluate(()=>{
   // Observe whether the handler intercepted; stop the actual test navigation.
   let intercepted=false;const observer=e=>{intercepted=e.defaultPrevented;e.preventDefault();};window.addEventListener('click',observer);
   const a=document.createElement('a');a.setAttribute('data-wm-mat-mode','');a.href='./mat-mode.html';document.body.append(a);
   const click=(options={})=>{intercepted=false;a.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,button:0,...options}));return intercepted;};
   const out={modified:click({ctrlKey:true})};
   a.href='./mat-mode.html#'+encodeURIComponent(JSON.stringify({room:'fixture-room',token:'synthetic'}));out.connected=click();
   a.href='./mat-mode.html?room=fixture';out.query=click();
   a.href='https://example.invalid/mat-mode.html';out.external=click();
   a.href='./mat-mode.html';localStorage.setItem('wm-mat-session','active-web-session');out.activeSession=click();localStorage.removeItem('wm-mat-session');
   a.target='_blank';out.newTab=click();a.target='';
   a.remove();window.removeEventListener('click',observer);return out;
  });
  assert.deepEqual(bypass,{modified:false,connected:false,query:false,external:false,activeSession:false,newTab:false});
  assert.equal(await page.evaluate(()=>matCalls.length),3);
  assert.ok(read('src/tournaments.js').includes('href="./mat-mode.html" data-wm-mat-mode'));
  assert.ok(read('index.html').includes(read('src/tournaments.js').trim()));
  passed.push('Connected links, browser gestures, and active web sessions retain their original routes');
  await app.context.close();

  const web=await setup(),p=web.page;
  await p.waitForFunction(()=>window.wrestlingManagerSignInReady);
  await p.locator('.wm-info-links [data-wm-mat-mode]').click();
  await p.waitForURL('**/mat-mode.html');
  await p.locator('#pin').fill('2468');await p.locator('#pin2').fill('2468');
  await p.getByRole('button',{name:'Enter Mat Mode',exact:true}).click();
  await p.locator('#history').click();
  await p.getByText('No saved bouts on this device yet.',{exact:true}).waitFor();
  assert.equal(await p.locator('#export').isDisabled(),true);
  let downloads=0;p.on('download',()=>downloads++);
  await p.evaluate(()=>document.getElementById('export').onclick());
  assert.equal(downloads,0);assert.ok(p.url().endsWith('/mat-mode.html'));
  assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  passed.push('Browser fallback keeps PIN setup; empty history has a message and cannot open an empty download');
  const records=[{bout:'12 <test>',style:'folkstyle',result:'Points',ledger:[{corner:'red',points:3,scoring:true,label:'Takedown'}]}];
  await p.evaluate(records=>{localStorage.setItem('wm-mat-history',JSON.stringify(records));localStorage.setItem('unrelated-account-record','keep');},records);
  await p.locator('#menu').click();await p.locator('#history').click();
  assert.equal(await p.locator('article b').innerText(),'12 <test>');
  assert.equal(await p.locator('#export').isEnabled(),true);
  const downloadEvent=p.waitForEvent('download');await p.locator('#export').click();const download=await downloadEvent;
  assert.equal(download.suggestedFilename(),'mat-bout-history.json');
  assert.deepEqual(JSON.parse(fs.readFileSync(await download.path(),'utf8')),records);
  passed.push('Populated browser history renders safely and downloads the original records');
  for(const invalid of ['{broken','{}','[null]']){
   await p.evaluate(value=>localStorage.setItem('wm-mat-history',value),invalid);
   await p.locator('#menu').click();await p.locator('#history').click();
   await p.getByText(/Saved bouts could not be read/).waitFor();
   assert.equal(await p.locator('#export').isDisabled(),true);
   assert.equal(await p.evaluate(()=>localStorage.getItem('wm-mat-history')),invalid);
  }
  assert.equal(await p.evaluate(()=>localStorage.getItem('unrelated-account-record')),'keep');
  await p.evaluate(records=>localStorage.setItem('wm-mat-history',JSON.stringify(records)),records);
  const session=await p.evaluate(()=>localStorage.getItem('wm-mat-session'));
  await p.locator('#exit').click();await p.locator('#exitPin').fill('0000');await p.getByRole('button',{name:'End session & exit',exact:true}).click();
  await p.getByText('Incorrect PIN.',{exact:true}).waitFor();
  assert.ok(await p.evaluate(()=>localStorage.getItem('wm-mat-session')));
  await p.locator('#cancelExit').click();
  assert.ok(p.url().endsWith('/mat-mode.html'));
  await p.locator('#exit').click();await p.locator('#exitPin').fill('2468');await p.getByRole('button',{name:'End session & exit',exact:true}).click();
  await p.waitForURL('**/index.html');
  assert.equal(await p.evaluate(()=>localStorage.getItem('wm-mat-session')),null);
  assert.deepEqual(await p.evaluate(()=>JSON.parse(localStorage.getItem('wm-mat-history'))),records);
  passed.push('Unreadable history is preserved; Back, cancel, and the existing exit PIN still work');
  await web.context.close();
  const resumed=await setup(true,{'wm-mat-session':session});
  await resumed.page.waitForURL('**/mat-mode.html');await resumed.page.locator('#history').waitFor();
  assert.deepEqual(await resumed.page.evaluate(()=>matCalls),[]);
  assert.equal(await resumed.page.locator('#exit').isVisible(),true);
  passed.push('An active web session resumes its existing exit lock even in the native shell');
  await resumed.context.close();
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'validation/mat-mode-entry-browser.json'),JSON.stringify({passed,nativeBridge:'simulated',physicalDeviceTested:false,realAccountChanged:false},null,2)+'\n');
  for(const result of passed)console.log('PASS',result);
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
