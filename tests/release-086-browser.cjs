const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),checks=[],pass=s=>{checks.push(s);console.log('PASS',s)};
(async()=>{
 const b=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']}),c=await b.newContext({viewport:{width:390,height:844},hasTouch:true,timezoneId:'America/Denver'}),p=await c.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await c.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')});await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());await p.goto('https://wm.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady);
 await p.evaluate(()=>{
  session=fixture.session={user:{id:'coach'}};managedLogin=null;activeTeam={id:'a',name:'Lyman Girls'};activeSeason={id:'season',name:'2026–27'};show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);isStaff=actualIsStaff=isTeamAdmin=true;viewMode='staff';applyRoleUI();
  rosterRows=[{athlete_id:'1',first_name:'Alex',last_name:'West',current_lineup_class:100,roster_status:'varsity'},{athlete_id:'2',first_name:'Taylor',last_name:'Adams',current_lineup_class:95,roster_status:'jv'},{athlete_id:'3',first_name:'Casey',last_name:'Baker',current_lineup_class:235,roster_status:'varsity'},{athlete_id:'4',first_name:'Morgan',last_name:'Carter',current_lineup_class:null,roster_status:'unassigned'},{athlete_id:'5',first_name:'Sam',last_name:'Removed',active:false,roster_status:'removed'},{athlete_id:'6',first_name:'Pat',last_name:'Standby',active:true,roster_status:'standby'}];
  rosterManagementRows=rosterRows.map(r=>({active:true,...r}));
  fixture.eligibility=rosterRows.map(r=>({athlete_id:r.athlete_id,eligible:true,competition_allowed:true,practice_allowed:true,timezone:'America/Denver',rules_version:2,revision:0}));
  const old=client.rpc;client.rpc=async(name,args)=>{
   if(name==='roster_eligibility_request'){
    if(args.p_action==='save'){fixture.eligibilitySave=args.p_data;const r=fixture.eligibility.find(r=>r.athlete_id===args.p_data.athlete_id);Object.assign(r,args.p_data,{competition_allowed:args.p_data.eligible,revision:r.revision+1});return {data:r};}
    return {data:structuredClone(fixture.eligibility)};
   }
   if(name==='attendance_summary_request'){
    if(fixture.delayAttendance)await new Promise(r=>setTimeout(r,300));
    return {data:{can_manage:true,athletes:rosterRows.map(r=>({athlete_id:r.athlete_id,name:`${r.first_name} ${r.last_name}`,active:r.active!==false,roster_status:r.roster_status})),events:[],settings:{event_types:['practice','dual','tournament'],excused_counts:false,modified_counts:true,revision:0}}};
   }
   return old(name,args);
  };
  WMRoster.render();openSheet('rosterSheet');
 });
 await p.evaluate(()=>WMEligibility.load());
 const order=()=>p.locator('#rosterList [data-roster-athlete]').evaluateAll(es=>es.map(e=>e.dataset.rosterAthlete));
 await p.locator('#rosterSort').selectOption('first');assert.deepEqual(await order(),['1','3','4','2']);
 await p.locator('#rosterSort').selectOption('last');assert.deepEqual(await order(),['2','3','4','1']);
 await p.locator('#rosterSort').selectOption('weight');assert.deepEqual(await order(),['2','1','3','4']);
 assert.equal(await p.evaluate(()=>localStorage.getItem('wm-roster-sort:'+WMRoster.key())),'weight');pass('First/last/numeric weight sorting and saved preference');
 await p.evaluate(()=>closeSheets());await p.locator('#lockerAttendanceTab').click();await p.locator('#attendanceStatsAthlete').waitFor();
 assert.deepEqual(await p.locator('#attendanceStatsAthlete option').evaluateAll(es=>es.map(e=>e.value)),['','1','2','3','4']);
 assert(await p.locator('#lockerAttendanceTab').evaluate(e=>e.classList.contains('active')));assert.equal(await p.locator('[data-locker-section="board"]').evaluate(e=>e.classList.contains('active')),false);
 await p.locator('#attendanceStatsClose').click();assert(await p.locator('#attendanceStatsSheet').isHidden());assert(await p.locator('#sheetBackdrop').isHidden());assert.equal(await p.evaluate(()=>document.body.style.overflow),'');assert(await p.locator('[data-locker-section="board"]').evaluate(e=>e.classList.contains('active')));pass('Active-only attendance picker; X closes sheet/backdrop and restores Team Board highlight');
 await p.locator('#lockerAttendanceTab').click();await p.locator('#attendanceStatsSheet [data-sheet-back]').click();assert(await p.locator('#attendanceStatsSheet').isHidden());assert(await p.locator('#sheetBackdrop').isHidden());pass('Back from Attendance returns to Locker Room');
 await p.evaluate(()=>{openSheet('rosterSheet');WMAttendance.open('1');});await p.locator('#attendanceStatsAthlete').waitFor();await p.locator('#attendanceStatsSheet [data-sheet-back]').click();assert(await p.locator('#rosterSheet').isVisible());assert(await p.locator('#attendanceStatsSheet').isHidden());pass('Back from roster attendance restores roster');
 await p.evaluate(()=>WMAttendance.open('1'));await p.locator('#attendanceStatsSchedule').click();assert(await p.locator('#attendanceStatsSheet').isHidden());assert(await p.locator('#sheetBackdrop').isHidden());assert(await p.locator('#scheduleTab').isVisible());pass('Manage attendance closes panel and opens Schedule');
 await p.evaluate(()=>{fixture.delayAttendance=true;WMAttendance.open();});await p.locator('#attendanceStatsClose').click();await p.waitForTimeout(400);assert(await p.locator('#attendanceStatsSheet').isHidden());assert.equal(await p.locator('#attendanceStatsBody').innerHTML(),'');await p.evaluate(()=>fixture.delayAttendance=false);pass('Delayed attendance response cannot reopen a closed screen');
 await p.evaluate(()=>{activeEvent={id:'event',event_type:'practice',title:'Practice',counts_toward_season_attendance:true};return openAttendance();});assert.equal(await p.locator('#attendanceList .attendance-card').count(),4);await p.evaluate(()=>closeSheets());pass('Event attendance excludes standby/removed, includes all active wrestlers');
 await p.evaluate(()=>{openSheet('rosterSheet');WMEligibility.change('1',fixture.eligibility[0]);});assert.equal(await p.locator('#eligibilityPractice').inputValue(),'yes');await p.locator('#eligibilityCompetition').selectOption('no');await p.locator('#eligibilityFrom').fill('2026-09-01');await p.locator('#eligibilityEndMode').selectOption('date');await p.locator('#eligibilityThrough').fill('2026-10-02');
 for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.locator('#eligibilitySheet').evaluate(e=>e.scrollWidth<=e.clientWidth+1));}
 await p.setViewportSize({width:390,height:844});await p.locator('#eligibilityForm button[type=submit]').click();await p.locator('#eligibilityStatus').getByText('Eligibility restrictions saved.').waitFor();assert.equal(await p.evaluate(()=>fixture.eligibilitySave.practice_allowed),true);assert.equal(await p.evaluate(()=>fixture.eligibilitySave.restricted_through),'2026-10-02');await p.screenshot({path:path.join(root,'validation/eligibility-086-phone.png')});
 assert.deepEqual(await p.evaluate(()=>['2026-09-28T12:00:00Z','2026-10-03T05:59:59Z','2026-10-03T06:00:00Z'].map(t=>WMEligibility.effective(fixture.eligibility[0],t).eligible)),[false,false,true]);
 assert.equal(await p.evaluate(()=>WMEligibility.forEvent(rosterRows,{event_type:'dual',starts_at:'2026-09-28T12:00:00Z'}).some(a=>a.athlete_id==='1')),false);
 assert.equal(await p.evaluate(()=>WMEligibility.forEvent(rosterRows,{event_type:'practice',starts_at:'2026-09-28T12:00:00Z'}).some(a=>a.athlete_id==='1')),true);
 assert.equal(await p.evaluate(()=>WMEligibility.forEvent(rosterRows,{event_type:'dual',starts_at:'2026-10-03T12:00:00Z'}).some(a=>a.athlete_id==='1')),true);pass('Dated restrictions save, preserve practice by default and expire at local midnight; upcoming events use event dates');
 await p.locator('#eligibilityPractice').selectOption('no');await p.locator('#eligibilityEndMode').selectOption('manual');await p.locator('#eligibilityForm button[type=submit]').click();await p.waitForFunction(()=>fixture.eligibilitySave.practice_allowed===false&&fixture.eligibilitySave.restricted_through===null);await p.locator('#eligibilityStatus').getByText('Eligibility restrictions saved.').waitFor();
 assert.equal(await p.evaluate(()=>WMEligibility.forEvent(rosterRows,{event_type:'practice',starts_at:'2026-10-03T12:00:00Z'}).some(a=>a.athlete_id==='1')),false);pass('School/coach can also restrict practice until clearance');
 await p.locator('#eligibilityClear').click();await p.locator('#eligibilityStatus').getByText('Competition and practice eligibility restored.').waitFor();assert.equal(await p.evaluate(()=>fixture.eligibilitySave.eligible),true);assert.equal(await p.evaluate(()=>fixture.eligibilitySave.practice_allowed),true);assert.equal(await p.evaluate(()=>fixture.eligibilitySave.restricted_from),null);await p.locator('#eligibilityClose').click();assert(await p.locator('#eligibilitySheet').isHidden());pass('Clear restrictions restores both activities and editor closes');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/release-086-browser.json'),JSON.stringify({checks,errors},null,2));await b.close();
})().catch(e=>{console.error(e);process.exit(1)});
