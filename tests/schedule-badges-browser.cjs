'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[],pass=s=>{passed.push(s);console.log('PASS',s);};
const html=fs.readFileSync(path.join(root,'index.html'),'utf8'),fixture=fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:1228,height:920}}),page=await context.newPage(),errors=[];
 page.on('pageerror',e=>errors.push(e.message));await context.addInitScript({content:fixture});
 await context.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 async function setup(){
  await page.goto('https://theteammanager.app/');await page.waitForFunction(()=>window.wrestlingManagerSignInReady);
  await page.evaluate(()=>{
   session=fixture.session={user:{id:'synthetic-coach'}};activeTeam={id:'synthetic-a',name:'Synthetic Girls Wrestling'};activeSeason={id:'synthetic-season',name:'2026-27'};managedLogin=null;
   isStaff=true;isManager=false;show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);show('scheduleTab',false);show('messagesTab',true);
   $('headerTeamName').textContent=activeTeam.name;$('headerSeasonName').textContent=activeSeason.name;WMScheduleBadges.reset();
   fixture.scheduleBase=Date.parse('2026-09-29T15:00:00Z');
   fixture.dates=Array.from({length:74},(_,i)=>({id:'practice-'+i,team_id:activeTeam.id,title:'Practice',event_type:'practice',starts_at:new Date(fixture.scheduleBase+(i+1)*86400000).toISOString(),ends_at:new Date(fixture.scheduleBase+(i+1)*86400000+7200000).toISOString(),updated_at:new Date(fixture.scheduleBase).toISOString(),location_name:'Synthetic Wrestling Room'}));
   const from=client.from.bind(client);
   client.from=name=>{
    if(name!=='team_events')return from(name);
    const q={select(){return this;},eq(k,v){this.team=v;return this;},order(){return this;},then(resolve){
     const result=structuredClone({data:fixture.dates,error:fixture.scheduleFail?{message:'Synthetic schedule error'}:null});
     if(fixture.holdSchedule){fixture.releaseSchedule=()=>resolve(result);}else resolve(result);
    }};return q;
   };
   WMOperations.calendar=async()=>[];
  });
 }
 const state=()=>page.locator('[data-nav-badge="schedule"]').evaluate(el=>({text:el.textContent,shown:el.classList.contains('show'),label:el.getAttribute('aria-label')}));
 await setup();await page.evaluate(()=>loadSchedule());assert.deepEqual(await state(),{text:'0',shown:false,label:'0 unseen schedule changes'});
 assert.equal(await page.evaluate(()=>scheduleRows.length),74);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 pass('Real Mac-width page keeps all 74 practices while hiding the false first-login Schedule badge');
 await page.evaluate(()=>{fixture.dates[0].updated_at=new Date(fixture.scheduleBase+1000).toISOString();fixture.dates.push({...fixture.dates[1],id:'new-dual',event_type:'dual',title:'Synthetic Dual',updated_at:new Date(fixture.scheduleBase+2000).toISOString()});return loadSchedule();});
 assert.equal((await state()).text,'2');assert.equal((await state()).shown,true);
 await page.locator('.nav-btn[data-tab="schedule"]').click();await page.waitForFunction(()=>!document.querySelector('[data-nav-badge="schedule"]').classList.contains('show'));
 assert.equal((await state()).label,'0 unseen schedule changes');
 pass('A later edit plus a new event show two changes; the actual Schedule button acknowledges them');
 await page.evaluate(()=>{show('scheduleTab',false);show('messagesTab',true);activeTeam={id:'synthetic-b',name:'Other Synthetic Team'};activeSeason={id:'other-season'};WMScheduleBadges.reset();fixture.dates=fixture.dates.slice(0,5).map(e=>({...e,team_id:activeTeam.id}));return loadSchedule();});assert.equal((await state()).shown,false);
 await page.evaluate(()=>{activeTeam={id:'synthetic-a',name:'Synthetic Girls Wrestling'};activeSeason={id:'synthetic-season'};WMScheduleBadges.reset();return loadSchedule();});assert.equal((await state()).shown,false);
 pass('Synthetic team switching does not turn existing practices back into new changes');
 await setup();await page.evaluate(()=>loadSchedule());assert.equal((await state()).shown,false);
 pass('Reload preserves the existing account/team last-viewed value without an unread season');
 await page.evaluate(()=>{fixture.holdSchedule=true;fixture.pendingSchedule=loadSchedule();});await page.waitForFunction(()=>!!fixture.releaseSchedule);
 await page.evaluate(()=>{activeTeam={id:'synthetic-new-team'};WMScheduleBadges.reset();scheduleRows=[];fixture.releaseSchedule();return fixture.pendingSchedule;});
 assert.equal(await page.evaluate(()=>scheduleRows.length),0);assert.equal(await page.evaluate(()=>localStorage.getItem('wm_nav_seen_schedule_synthetic-coach_synthetic-new-team')),null);
 pass('An old team response cannot fill the real schedule model or initialize the new team badge');
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>{fixture.holdSchedule=false;fixture.dates=[];return loadSchedule();});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.deepEqual(errors,[]);
 pass('Phone-width navigation still fits, with no page errors or live server writes');
 fs.writeFileSync(path.join(root,'validation/schedule-badges-browser.json'),JSON.stringify({passed,errors,engine:'Chromium actual bundled UI with isolated synthetic API responses',productionDataChanged:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
