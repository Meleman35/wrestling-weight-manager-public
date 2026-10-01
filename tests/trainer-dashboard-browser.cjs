const fs=require('fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage'],...(process.env.WM_BROWSER_PATH?{executablePath:process.env.WM_BROWSER_PATH}:{})});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[],checks=[];
 const pass=s=>{checks.push(s);console.log('PASS',s)};p.on('pageerror',e=>errors.push(e.message));
 fs.mkdirSync('validation',{recursive:true});
 await ctx.addInitScript({content:fs.readFileSync('tests/browser-fixture.js','utf8')});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync('index.html','utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto(process.env.WM_TEST_ORIGIN||'https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
 await p.evaluate(()=>{
  session=fixture.session={user:{id:'trainer',email:'trainer@example.test'}};managedLogin=null;
  availableTeams=[{id:'team-a',name:'Sample Wrestling'},{id:'team-b',name:'Second Assigned Team'},{id:'unassigned',name:'Other Team'}];activeTeam=availableTeams[0];
  teamMemberships=['team-a','team-b'].map(team_id=>({team_id,user_id:'trainer',role:'manager',active:true,permissions:{staff_role:'team_trainer'}}));currentTeamMemberships=[teamMemberships[0]];
  staffMembership=currentTeamMemberships[0];actualIsStaff=isStaff=actualIsTeamAdmin=isTeamAdmin=false;actualIsManager=isManager=true;familyAthletes=[];canWeighIn=actualCanWeighIn=false;
  show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);setTab('home');
  const today=new Date().toLocaleDateString('en-CA');
  window.trainerTest={accepted:true,assigned:true,deny:false,delay:0,calls:[],readCalls:[],athletes:[
   {id:'a',name:'Review Athlete',baseline:null,cases:[{id:'case-a',status:'awaiting_trainer',review_on:today}],can_submit:true},
   {id:'b',name:'Restricted Athlete',baseline:{provider:'Sway',completed_on:today},cases:[{id:'case-b',status:'no_contact'},{id:'case-c',status:'modified'}],can_submit:true},
   {id:'c',name:'Followup Athlete',baseline:{provider:'Sway',completed_on:today},cases:[{id:'case-d',status:'cleared',review_on:today,return_on:today}],can_submit:true}
  ]};
  const old=client.rpc;client.rpc=async(name,args)=>{
   if(name!=='athlete_health_request')return old(name,args);
   const snapshot=structuredClone(trainerTest);trainerTest.calls.push(structuredClone(args));
   if(snapshot.delay)await new Promise(r=>setTimeout(r,snapshot.delay));
   if(snapshot.deny)return {error:{code:'42501',message:'Access denied'}};
   if(args.p_action==='dashboard')return {data:{assigned_trainer:snapshot.assigned,trainer:snapshot.accepted,coach:false,admin:false,school_year_start:'2026-07-01',baseline_required:true,trainers:[],athletes:snapshot.athletes}};
   throw Error('Unexpected test action '+args.p_action);
  };
  const originalFrom=client.from;client.from=name=>{
   if(name!=='team_events')return originalFrom(name);
   const query={};const q={select:v=>(query.select=v,q),eq:(k,v)=>(query[k]=v,q),gte:(k,v)=>(query[k]=v,q),order:()=>q,limit:()=>{trainerTest.readCalls.push(query);return Promise.resolve({data:[{id:'event-a',title:'Practice',starts_at:'2026-12-01T17:00:00Z',location:'Wrestling room'}],error:null})}};return q;
  };
  WMTrainerDashboard.prepared();
 });
 await p.waitForSelector('[data-trainer-filter="awaiting"]');
 assert.equal(await p.locator('[data-trainer-filter="awaiting"] strong').innerText(),'1');
 assert.equal(await p.locator('[data-trainer-filter="restricted"] strong').innerText(),'1');
 assert.equal(await p.locator('[data-trainer-filter="due"] strong').innerText(),'2');
 assert.equal(await p.locator('[data-trainer-filter="baseline"] strong').innerText(),'1');
 assert.match(await p.locator('#trainerDashboardBody').innerText(),/does not establish medical clearance/);
 assert.equal(await p.locator('#trainerAssignedTeams option').count(),2);assert(!((await p.locator('#trainerAssignedTeams').innerText()).includes('Other Team')));
 assert.equal(await p.evaluate(()=>session.user.id),'trainer');assert.equal(await p.evaluate(()=>actualIsStaff||canWeighIn),false);
 pass('Trainer-only home uses existing accepted access, athlete counts and assigned teams without granting coach or scale permissions');
 for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1))}
 await p.setViewportSize({width:390,height:844});await p.screenshot({path:'validation/trainer-dashboard-phone.png'});
 await p.locator('[data-trainer-filter="restricted"]').click();await p.waitForSelector('#healthFilter');assert.equal(await p.locator('#healthFilter').inputValue(),'restricted');
 assert.match(await p.locator('#healthRoster').innerText(),/Restricted Athlete/);assert(!((await p.locator('#healthRoster').innerText()).includes('Review Athlete')));
 await p.locator('#healthClose').click();await p.waitForSelector('#trainerSchedule');await p.locator('#trainerSchedule').click();await p.waitForSelector('#trainerScheduleBody article');
 assert.equal(await p.locator('#trainerScheduleBody button').count(),0);assert.equal(await p.evaluate(()=>trainerTest.readCalls[0].team_id),'team-a');
 assert.match(await p.evaluate(()=>trainerTest.readCalls[0].select),/^id,title,event_type,starts_at,ends_at,location$/);
 pass('Dashboard cards open filtered existing health records; the schedule is a current-team read-only query');
 await p.locator('#trainerReturnHome').click();assert.equal(await p.locator('#trainerDashboardPanel').isVisible(),false);await p.locator('#trainerHomeEntry').click();await p.waitForSelector('#trainerAthletes');
 await p.evaluate(()=>{WMTrainerDashboard.reset();familyAthletes=[{athlete_id:'child'}];WMTrainerDashboard.prepared()});await p.waitForSelector('#trainerHomeEntry');assert.equal(await p.locator('#trainerDashboardPanel').isVisible(),false);
 await p.locator('#trainerHomeEntry').click();await p.waitForSelector('#trainerAthletes');assert.equal(await p.evaluate(()=>familyAthletes[0].athlete_id),'child');
 pass('Multi-role trainers retain their team/family home and can switch workspaces without another login');
 await p.evaluate(()=>{trainerTest.accepted=false;WMTrainerDashboard.open()});await p.waitForSelector('#trainerAcceptRole');assert.equal(await p.locator('[data-trainer-filter]').count(),0);assert(!((await p.locator('#trainerDashboardBody').innerText()).includes('Review Athlete')));
 await p.evaluate(()=>{trainerTest.assigned=false;WMTrainerDashboard.open()});await p.waitForFunction(()=>document.querySelector('#trainerDashboardBody').textContent.includes('not available'));assert.equal(await p.locator('#trainerAcceptRole').count(),0);
 pass('Unaccepted or revoked trainer access never displays health counts, even when an unrelated role returns family data');
 await p.evaluate(()=>{trainerTest.accepted=true;trainerTest.assigned=true;trainerTest.delay=800;WMTrainerDashboard.open()});
 await p.evaluate(()=>{session=fixture.session={user:{id:'other-account'}};currentTeamMemberships=[]});await p.waitForTimeout(1100);assert.equal(await p.locator('#trainerDashboardPanel').innerText(),'');assert.equal(await p.locator('#trainerDashboardMoreBtn').isVisible(),false);
 pass('A delayed authorized response cannot render after switching accounts');
 await p.evaluate(()=>{session=fixture.session={user:{id:'trainer'}};currentTeamMemberships=[teamMemberships[0]];familyAthletes=[];trainerTest.delay=0;WMTrainerDashboard.prepared()});await p.waitForSelector('#trainerAthletes');
 await p.evaluate(()=>show('appLockOverlay',true));await p.waitForTimeout(600);assert.equal(await p.locator('#trainerDashboardPanel').innerText(),'');
 await p.evaluate(()=>show('appLockOverlay',false));await p.waitForSelector('#trainerAthletes');await ctx.setOffline(true);await p.waitForTimeout(650);assert.equal(await p.locator('[data-trainer-filter]').count(),0);assert.match(await p.locator('#trainerDashboardBody').innerText(),/Reconnect/);
 await ctx.setOffline(false);await p.waitForSelector('#trainerAthletes');await p.evaluate(()=>{currentTeamMemberships=[];WMTrainerDashboard.sync()});assert.equal(await p.locator('#trainerDashboardPanel').innerText(),'');
 assert.equal(await p.evaluate(()=>fixture.writes.length),0);assert.deepEqual(errors,[]);
 pass('Lock, disconnect and assignment changes clear health content; no account, team, billing or clinical mutations occur');
 fs.writeFileSync('validation/trainer-dashboard-browser.json',JSON.stringify({checks,syntheticOnly:true,nativeCodeChanged:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
