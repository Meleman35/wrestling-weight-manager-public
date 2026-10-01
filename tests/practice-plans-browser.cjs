const fs=require('fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']}),ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));fs.mkdirSync('validation',{recursive:true});
 await ctx.addInitScript({content:fs.readFileSync('tests/browser-fixture.js','utf8')});const html=fs.readFileSync('index.html','utf8');
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
 await p.evaluate(()=>{
  session=fixture.session={user:{id:'coach',email:'coach@example.test'}};activeTeam={id:'team',name:'Sample School Team',timezone:'America/Denver'};managedLogin=null;isStaff=true;
  show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
  window.practiceTest={covered:false,rows:[],calls:[],delay:0,loseSave:false,event:{id:'event',title:'Afternoon practice',plan_date:'2026-10-01',start_time:'15:30',target_minutes:90}};
  const old=client.rpc;client.rpc=async(name,args)=>{
   if(name!=='practice_plans_request')return old(name,args);
   const c=practiceTest;c.calls.push(structuredClone(args));if(c.delay)await new Promise(r=>setTimeout(r,c.delay));const a=args.p_action,d=args.p_data;
   const info={team_name:'Sample School Team',timezone:'America/Denver'};
   if(a==='context')return {data:{...info,covered:c.covered}};
   if(!c.covered)return {error:{code:'PT402',message:'Practice Plans require active Team Pro access for this team.'}};
   if(a==='list')return {data:{...info,plans:c.rows.filter(x=>x.plan_date.startsWith(d.month)).map(x=>({...x,block_count:x.blocks.length,total_minutes:x.blocks.reduce((s,b)=>s+b.minutes,0)}))}};
   if(a==='event')return {data:{...info,event:c.event,plan:c.rows.find(x=>x.event_id===d.event_id)||null}};
   if(a==='read')return {data:{...info,plan:structuredClone(c.rows.find(x=>x.id===d.id)),event:c.event}};
   if(a==='save'){
    let row=c.rows.find(x=>x.id===d.id);
    if(row?.last_request===d.request_id)return {data:{plan:structuredClone(row),saved:true}};
    if(row&&row.revision!==d.revision)return {error:{message:'Another coach changed this plan. Reopen it.'}};
    const next={...structuredClone(d),revision:d.revision+1,last_request:d.request_id};if(row)c.rows[c.rows.indexOf(row)]=next;else c.rows.push(next);
    if(c.loseSave){c.loseSave=false;throw Error('Lost response')}
    return {data:{plan:structuredClone(next),saved:true}};
   }
   if(a==='delete'){c.rows=c.rows.filter(x=>x.id!==d.id);return {data:{deleted:true}}}
  };
 });
 p.on('dialog',d=>d.accept());
 await p.evaluate(()=>WMPracticePlans.open());await p.waitForSelector('#ppSample');assert.equal(await p.locator('#ppNew').count(),0);assert.equal(await p.evaluate(()=>practiceTest.calls.some(c=>c.p_action!=='context')),false);
 await p.locator('#ppSample').click();assert.match(await p.locator('#ppBody').innerText(),/Fictional practice/);assert.equal(await p.locator('#ppSave').count(),0);await p.screenshot({path:'validation/practice-plans-paid-preview.png'});
 console.log('PASS Free coaches see a labeled sample with no real reads, editor, or save controls');
 await p.evaluate(()=>{practiceTest.covered=true;return WMPracticePlans.open('event')});await p.waitForSelector('#ppTitle');assert.equal(await p.locator('#ppDate').inputValue(),'2026-10-01');assert.equal(await p.locator('#ppStart').inputValue(),'15:30');assert.equal(await p.locator('#ppTarget').inputValue(),'90');
 await p.locator('#ppTitle').fill('Daily practice: single-leg finishes');await p.locator('#ppFocus').fill('Create angles and finish through resistance');
 await p.locator('#ppAdd').click();await p.locator('[data-key="label"]').fill('Warm-up');await p.locator('[data-key="category"]').selectOption('warmup');await p.locator('[data-key="minutes"]').fill('10');
 await p.locator('#ppAdd').click();await p.locator('[data-key="label"]').nth(1).fill('Single-leg finishes');await p.locator('[data-key="category"]').nth(1).selectOption('technique');await p.locator('[data-key="minutes"]').nth(1).fill('20');await p.locator('[data-key="notes"]').nth(1).fill('Partner reps · 2 finishes each side');
 assert.match(await p.locator('#ppSummary').innerText(),/30 min planned · 60 min under/);assert.equal(await p.locator('[data-pp-time]').nth(1).innerText(),'3:40 PM – 4:00 PM');
 await p.locator('[data-move="-1"]').nth(1).click();assert.equal(await p.locator('[data-key="label"]').first().inputValue(),'Single-leg finishes');await p.locator('[data-move="1"]').first().click();
 for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));assert(await p.locator('#practicePlansSheet').evaluate(el=>el.scrollWidth<=el.clientWidth+1))}
 await p.setViewportSize({width:390,height:844});await p.locator('#practicePlansSheet').evaluate(el=>el.scrollTop=0);await p.screenshot({path:'validation/practice-plans-phone-top.png'});await p.locator('[data-block-id]').first().scrollIntoViewIfNeeded();await p.screenshot({path:'validation/practice-plans-phone-blocks.png'});
 console.log('PASS Scheduled practice uses team-local date/time; timed blocks reorder and total correctly at phone and tablet widths');
 await p.evaluate(()=>practiceTest.loseSave=true);await p.locator('#ppSave').click();await p.waitForFunction(()=>document.querySelector('#ppStatus').textContent.includes('Completion is not confirmed'));assert.equal(await p.evaluate(()=>practiceTest.rows.length),1);
 await p.locator('#ppSave').click();await p.waitForFunction(()=>document.querySelector('#ppStatus').textContent.includes('saved with your team'));assert.equal(await p.evaluate(()=>practiceTest.rows.length),1);assert.equal(await p.evaluate(()=>practiceTest.rows[0].revision),1);
 const saves=await p.evaluate(()=>practiceTest.calls.filter(c=>c.p_action==='save'));assert.equal(saves[0].p_data.request_id,saves[1].p_data.request_id);
 await p.locator('#ppNotes').fill('<img src=x onerror="window.planInjection=true">');assert.equal(await p.evaluate(()=>window.planInjection),undefined);
 await p.locator('#ppSave').click();await p.waitForFunction(()=>practiceTest.rows[0].revision===2);await p.waitForFunction(()=>!document.querySelector('#ppSave').disabled);
 await p.locator('summary').filter({hasText:'Reuse this practice'}).click();await p.locator('#ppCopyDate').fill('2026-10-02');await p.locator('#ppCopy').click();assert.equal(await p.locator('#ppDate').inputValue(),'2026-10-02');assert.equal(await p.locator('#ppUnlink').count(),0);
 await p.locator('#ppSave').click();await p.waitForFunction(()=>practiceTest.rows.length===2);assert.equal(await p.evaluate(()=>practiceTest.rows[0].plan_date),'2026-10-01');assert.equal(await p.evaluate(()=>practiceTest.rows[1].event_id),null);
 console.log('PASS Saving survives a lost response without duplication; copies have new IDs and leave the original schedule link untouched');
 await p.waitForFunction(()=>!document.querySelector('#ppSave').disabled);await p.locator('#ppNotes').fill('Offline draft');await ctx.setOffline(true);await p.locator('#ppSave').click();await p.waitForFunction(()=>document.querySelector('#ppStatus').textContent.includes('Reconnect'));assert.match(await p.evaluate(()=>practiceTest.rows[1].notes),/<img/);
 await ctx.setOffline(false);await p.locator('#ppClose').click();assert.equal(await p.locator('#ppBody').innerText(),'');await p.evaluate(()=>WMPracticePlans.open());await p.waitForSelector('#ppResume');await p.locator('#ppResume').click();assert.equal(await p.locator('#ppNotes').inputValue(),'Offline draft');
 await p.evaluate(()=>practiceTest.rows[1].revision++);await p.locator('#ppSave').click();await p.waitForFunction(()=>document.querySelector('#ppStatus').textContent.includes('Another coach'));assert.equal(await p.locator('#ppNotes').inputValue(),'Offline draft');
 console.log('PASS Offline edits are visibly unsaved and can resume in memory; a stale save retains the draft and warns the coach');
 await p.evaluate(()=>practiceTest.covered=false);await p.locator('#ppSave').click();await p.waitForSelector('#ppSample');assert.equal(await p.locator('#ppForm').count(),0);
 console.log('PASS Coverage loss removes real plan content and prevents saving');
 await p.evaluate(()=>{practiceTest.covered=true;return WMPracticePlans.open()});await p.waitForSelector('#ppNew');await p.locator('#ppNew').click();await p.locator('#ppNotes').fill('Private draft');await p.evaluate(()=>show('appLockOverlay',true));await p.waitForSelector('#practicePlansSheet.hidden',{state:'attached'});assert.equal(await p.locator('#ppBody').innerText(),'');
 await p.evaluate(()=>{show('appLockOverlay',false);return WMPracticePlans.open()});await p.waitForSelector('#ppNew');assert.equal(await p.locator('#ppResume').count(),0);
 await p.evaluate(()=>{practiceTest.delay=700;WMPracticePlans.open('event')});await p.evaluate(()=>{activeTeam={id:'other-team',name:'Other',timezone:'UTC'}});await p.waitForTimeout(1000);assert.equal(await p.locator('#ppBody').innerText(),'');
 await p.evaluate(()=>{practiceTest.delay=0;isStaff=false;WMPracticePlans.sync()});assert(await p.locator('#practicePlansBtn').evaluate(el=>el.classList.contains('hidden')));await p.evaluate(()=>WMPracticePlans.open());assert(await p.locator('#practicePlansSheet').evaluate(el=>el.classList.contains('hidden')));
 console.log('PASS Lock, team changes, stale replies and non-coach contexts cannot expose a saved plan or draft');
 assert.deepEqual(errors,[]);await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
