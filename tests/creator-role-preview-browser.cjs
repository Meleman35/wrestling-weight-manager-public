const fs=require('fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']}),ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[],requests=[];
 p.on('pageerror',e=>errors.push(e.message));ctx.on('request',r=>requests.push(r.url()));fs.mkdirSync('validation',{recursive:true});
 await ctx.addInitScript({content:'if(window===window.top){'+fs.readFileSync('tests/browser-fixture.js','utf8')+'}'});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync('index.html','utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto(process.env.WM_TEST_ORIGIN||'https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
 await p.evaluate(()=>{
  session=fixture.session={user:{id:'creator-fixture-id',email:'creator-fixture@example.test'},access_token:'sentinel-private-token'};managedLogin=null;activeTeam=null;
  show('authView',false);show('appView',true);show('setupView',false);show('appLockOverlay',false);
  window.previewTest={allowed:false,delay:0,calls:[]};const old=client.rpc;
  client.rpc=async(name,args)=>{if(name!=='creator_offers_request')return old(name,args);const allowed=previewTest.allowed;previewTest.calls.push(structuredClone(args));if(previewTest.delay)await new Promise(r=>setTimeout(r,previewTest.delay));return {data:args.p_action==='access'?{creator:allowed}:{creator:allowed,offers:[],events:[],trial:{requested:true,revision:1}}}};
 });
 await p.evaluate(()=>WMCreatorRolePreview.open());assert.equal(await p.locator('#creatorRolePreviewFrame').count(),0);assert.match(await p.locator('#creatorRolePreviewStatus').innerText(),/could not be confirmed/);await p.evaluate(()=>closeSheets());
 console.log('PASS Unprivileged direct entry does not load a preview or impersonate a role');
 await p.evaluate(()=>{previewTest.allowed=true;return refresh()});await p.waitForSelector('#creatorHomeRolePreviewBtn:not(.hidden)');
 await p.locator('#creatorHomeRolePreviewBtn').click();await p.waitForSelector('#creatorRolePreviewFrame');const fl=()=>p.frameLocator('#creatorRolePreviewFrame');await fl().locator('#demoRole').waitFor();
 assert.equal(await p.locator('#creatorRolePreviewFrame').getAttribute('sandbox'),'allow-scripts');
 assert.equal(await p.evaluate(()=>document.getElementById('creatorRolePreviewFrame').contentDocument),null);
 const source=await p.locator('#creatorRolePreviewFrame').getAttribute('srcdoc');assert(!source.includes('sentinel-private-token'));assert(!source.includes('creator-fixture-id'));assert(!source.includes('creator-fixture@example.test'));
 const child=()=>p.frames().find(f=>f.parentFrame());
 assert.equal(await child().evaluate(()=>{try{return !!parent.document}catch{return false}}),false);
 assert.equal(await child().evaluate(()=>{try{localStorage.getItem('secret');return true}catch{return false}}),false);
 assert.equal(await child().evaluate(()=>typeof window.supabase),'undefined');
 const beforeNetwork=requests.length;assert.equal(await child().evaluate(async()=>{try{await fetch('https://blocked.example.test/no-request');return false}catch{return true}}),true);assert.equal(requests.length,beforeNetwork);
 console.log('PASS Opaque sandbox gets no app client, credentials or parent/storage access, and CSP blocks network requests');
 for(const role of ['athlete','coach','trainer','team_mom','parent','admin']){
  await fl().locator('#demoRole').selectOption(role);assert.match(await fl().locator('.notice').first().innerText(),/DEMO ONLY/);
  await fl().locator('[data-demo-page="profile"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/FICTIONAL PROFILE/);
  await fl().locator('#demoPublic').check();assert.match(await fl().locator('#demoScreen').innerText(),/Shared-profile example/);
  await fl().locator('[data-demo-page="access"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/Not automatically included/);
  await fl().locator('[data-demo-page="schedule"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/Fictional events/);
 }
 console.log('PASS Six role choices each open a sample profile, sharing example, schedule and scoped access explanation');
 await fl().locator('#demoRole').selectOption('trainer');await fl().locator('#demoAccepted').uncheck();assert.equal(await fl().locator('.metric').count(),0);assert.match(await fl().locator('#demoScreen').innerText(),/Accept trainer access/);
 await fl().locator('[data-demo-action="accept"]').click();assert.equal(await fl().locator('.metric').count(),4);
 await fl().locator('[data-demo-action="health:baseline"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/Avery Demo/);assert(!/Rowan Demo/.test(await fl().locator('#demoScreen').innerText()));
 await fl().locator('[data-demo-action="care-record"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/Private care update/);
 await fl().locator('#demoRole').selectOption('coach');await fl().locator('[data-demo-action="coach-health"]').click();assert(!/Private care update/.test(await fl().locator('#demoScreen').innerText()));
 await fl().locator('#demoRole').selectOption('team_mom');await fl().locator('[data-demo-action="messages"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/Reviewer access is separate/);
 await fl().locator('#demoReviewer').check();assert.match(await fl().locator('#demoScreen').innerText(),/Read only/);assert.equal(await fl().locator('#demoMessage').count(),0);
 console.log('PASS Trainer acceptance and filtered sample care are separate from coach updates and optional read-only Team Mom review');
 await fl().locator('#demoRole').selectOption('athlete');await fl().locator('[data-demo-action="messages"]').click();assert.match(await fl().locator('#demoScreen').innerText(),/Family permission required/);
 await fl().locator('#demoAge').selectOption('child');assert(await fl().locator('#demoMessaging').isDisabled());assert.equal(await fl().locator('#demoMessage').count(),0);
 await fl().locator('#demoAge').selectOption('teen');await fl().locator('#demoMessaging').check();await fl().locator('#demoMessage').fill('<img src=x onerror="alert(1)"> fictional only');await fl().locator('[data-demo-action="send"]').click();
 assert.equal(await fl().locator('#demoScreen img').count(),0);assert.match(await fl().locator('#demoStatus').innerText(),/No message was sent/);
 await fl().locator('#demoReset').click();await fl().locator('[data-demo-action="messages"]').click();assert.equal(await fl().locator('#demoMessage').count(),0);
 console.log('PASS Age/permission examples do not grant rights; demo messages are escaped, memory-only and resettable');
 for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));assert(await child().evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1))}
 await p.setViewportSize({width:390,height:844});await fl().locator('#demoRole').selectOption('trainer');await child().evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));await p.screenshot({path:'validation/creator-role-preview-trainer-phone.png'});
 await fl().locator('[data-demo-page="profile"]').click();await child().evaluate(()=>scrollTo(0,0));await child().evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));await p.screenshot({path:'validation/creator-role-preview-profile-phone.png'});
 assert.equal(await p.evaluate(()=>fixture.writes.length),0);assert(await p.evaluate(()=>previewTest.calls.every(c=>c.p_action==='access')));
 await p.locator('#creatorRolePreviewClose').click();assert.equal(await p.locator('#creatorRolePreviewFrame').count(),0);assert.equal(await p.locator('#creatorHomePanel').isVisible(),true);assert.equal(await p.locator('#sheetBackdrop').isVisible(),false);
 console.log('PASS Phone/tablet widths fit; exit destroys the demo and returns to the signed-in Creator with no data writes');
 await p.evaluate(()=>{
  activeTeam={id:'team-sentinel',name:'Never copy this real-context name'};activeSeason={id:'season-sentinel'};availableTeams=[activeTeam];actualIsStaff=isStaff=true;
  window.previewBefore=JSON.stringify([session,activeTeam,activeSeason,availableTeams,actualIsStaff,isStaff]);return WMCreatorRolePreview.open();
 });await p.waitForSelector('#creatorRolePreviewFrame');assert(!(await p.locator('#creatorRolePreviewFrame').getAttribute('srcdoc')).includes('team-sentinel'));
 await p.evaluate(()=>closeSheets());assert.equal(await p.evaluate(()=>JSON.stringify([session,activeTeam,activeSeason,availableTeams,actualIsStaff,isStaff])===previewBefore),true);
 await p.evaluate(()=>WMCreatorRolePreview.open());await p.waitForSelector('#creatorRolePreviewFrame');await p.evaluate(()=>show('appLockOverlay',true));await p.waitForFunction(()=>!document.getElementById('creatorRolePreviewFrame'));await p.evaluate(()=>show('appLockOverlay',false));
 await p.evaluate(()=>{previewTest.delay=600;WMCreatorRolePreview.open()});await p.evaluate(()=>{session=fixture.session={user:{id:'other-context'}};previewTest.allowed=false});await p.waitForTimeout(850);assert.equal(await p.locator('#creatorRolePreviewFrame').count(),0);
 await p.evaluate(()=>{previewTest.delay=0;previewTest.allowed=true;return WMCreatorRolePreview.open()});await p.waitForSelector('#creatorRolePreviewFrame');await ctx.setOffline(true);await p.waitForFunction(()=>!document.getElementById('creatorRolePreviewFrame'));await ctx.setOffline(false);
 await p.evaluate(()=>WMCreatorRolePreview.open());await p.waitForSelector('#creatorRolePreviewFrame');await p.evaluate(()=>{activeTeam={id:'different-team'}});await p.waitForFunction(()=>!document.getElementById('creatorRolePreviewFrame'));
 await p.evaluate(()=>WMCreatorRolePreview.open());await p.waitForSelector('#creatorRolePreviewFrame');await p.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'))});assert.equal(await p.locator('#creatorRolePreviewFrame').count(),0);await p.evaluate(()=>{delete document.hidden});
 console.log('PASS Account, team, lock, background, offline and late-response checks destroy previews without touching the original account');
 await p.evaluate(()=>WMCreatorRolePreview.open());await p.waitForSelector('#creatorRolePreviewFrame');await p.evaluate(()=>{previewTest.allowed=false});await p.waitForFunction(()=>!document.getElementById('creatorRolePreviewFrame'),{},{timeout:20000});assert.match(await p.locator('#creatorRolePreviewStatus').innerText(),/could not be confirmed/);
 console.log('PASS Open preview rechecks server access and closes its sandbox after revocation');
 assert.equal(await p.evaluate(()=>fixture.writes.length),0);assert.deepEqual(errors,[]);await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
