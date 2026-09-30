const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']}),ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[],checks=[];p.on('pageerror',e=>errors.push(e.message));
const html=fs.readFileSync('index.html','utf8');await ctx.addInitScript({content:fs.readFileSync('tests/browser-fixture.js','utf8')});
await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
await p.goto('https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
await p.evaluate(()=>{
 session={user:{id:'coach',email:'coach@example.test'}};fixture.session=session;activeTeam={id:'team-a',name:'School Team'};availableTeams=[activeTeam,{id:'team-b',name:'Club Team'}];viewMode='coach';actualIsStaff=true;
 show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
 window.statsTest={covered:false,delay:0,calls:[]};const old=client.rpc;
 client.rpc=async(name,args)=>{if(name!=='wrestler_statistics_request')return old(name,args);statsTest.calls.push(args);const d=args.p_data;
 if(args.p_action==='context')return {data:{covered:statsTest.covered,athletes:[{id:'athlete-a',name:'Example Wrestler'}],seasons:[{id:'season-a',name:'2026–2027'}]},error:null};
 if(statsTest.delay)await new Promise(r=>setTimeout(r,statsTest.delay));
 return {data:{athlete_ids:['athlete-a'],matches:[{id:'match-a',team_id:d.team_id,season_id:'season-a',created_at:'2026-09-30',data:{style:d.style,status:'complete',winner:'red',result:'Decision',red_id:'athlete-a',other_id:null,other_name:'Test Opponent',ledger:[{id:'score',corner:'red',points:d.style==='folkstyle'?3:2,action_id:'td',period:1}]}}]},error:null};};
 WMOperations.download=(name,text)=>{window.statsExport={name,text};};
 });
const pass=s=>{checks.push(s);console.log('PASS',s);};
await p.evaluate(()=>WMStatistics.open());assert.match(await p.locator('#wsBody').innerText(),/part of Team Pro/);assert.equal(await p.evaluate(()=>statsTest.calls.filter(x=>x.p_action==='read').length),0);await p.locator('#wsPreview').click();await p.waitForSelector('#wsExport');assert.match(await p.locator('.ws-preview').innerText(),/Fictional/);assert.equal(await p.evaluate(()=>statsTest.calls.filter(x=>x.p_action==='read').length),0);pass('Unpaid access shows an explicit sample preview without fetching real matches');
await p.locator('#wsStyle').selectOption('freestyle');await p.locator('#wsSeason').selectOption('sample-current');assert.match(await p.locator('.ws-metrics').innerText(),/66.7%/);await p.locator('#wsExport').click();assert.match(await p.evaluate(()=>statsExport.name),/^Sample_/);pass('Sample style/season filters and CSV export remain clearly marked as examples');
for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));}
await p.setViewportSize({width:390,height:844});await p.screenshot({path:'validation/wrestler-statistics-preview-phone.png',fullPage:true});
await p.evaluate(()=>{statsTest.covered=true;return WMStatistics.open('athlete-a');});await p.waitForSelector('#wsExport');assert.equal(await p.locator('.ws-preview').count(),0);assert.match(await p.locator('.ws-metrics').innerText(),/100.0%/);
await p.locator('#wsStyle').selectOption('greco');await p.waitForFunction(()=>statsTest.calls.at(-1).p_data.style==='greco');await p.locator('#wsTeam').selectOption('team-b');await p.waitForFunction(()=>statsTest.calls.at(-1).p_data.team_id==='team-b');await p.waitForSelector('#wsExport');
await p.locator('#wsSeason').selectOption('season-a');await p.waitForFunction(()=>statsTest.calls.at(-1).p_data.season_id==='season-a');await p.locator('#wsExport').click();assert(!await p.evaluate(()=>statsExport.name.startsWith('Sample_')));pass('Authorized real report requests carry the selected wrestler, team, style and season');
await p.evaluate(()=>statsTest.delay=700);await p.locator('#wsStyle').selectOption('freestyle');assert.equal(await p.locator('#wsExport').count(),0);await p.evaluate(()=>{session={user:{id:'different'}};fixture.session=session;});await p.waitForSelector('#wrestlerStatisticsSheet.hidden',{state:'attached'});await p.waitForTimeout(800);assert.equal(await p.locator('#wsBody').innerText(),'');pass('Changing filters removes stale results; account changes discard delayed responses and clear report/export data');
assert.deepEqual(errors,[]);fs.writeFileSync('validation/wrestler-statistics-browser.json',JSON.stringify({checks,nativeDeviceVerified:false},null,2));await browser.close();})().catch(e=>{console.error(e);process.exit(1)});
