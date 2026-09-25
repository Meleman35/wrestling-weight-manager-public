const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright'),{PGlite}=require('@electric-sql/pglite'),{fixture,root}=require('./team-plan-fixture.cjs');
(async()=>{
 const db=new PGlite(),f=await fixture(db),{ids}=f,tests=[],errors=[];
 await db.exec('reset role');await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[ids.other,ids.coach]);
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu']}),ctx=await browser.newContext({viewport:{width:390,height:844},hasTouch:true}),p=await ctx.newPage();
 p.on('pageerror',e=>errors.push(e.message));const pass=s=>{tests.push(s);console.log('PASS',s);};let serial=Promise.resolve(),delay=0,fail=false;
 await p.exposeFunction('planBackend',(name,q,uid)=>{
  const ms=delay,bad=fail,work=serial.then(async()=>{await f.as(uid);try{if(bad)throw Error('Simulated unavailable service');const data=name==='team_plan_request'?await f.plan(q.p_team_id):await f.resource(q.p_action,q.p_data);return {data,error:null};}catch(e){return {data:null,error:{message:e.message}}}});
  serial=work.catch(()=>{});return work.then(async result=>{if(ms)await new Promise(r=>setTimeout(r,ms));return result;});
 });
 const init=fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8').replace('    F.calls.push',"    if(['team_plan_request','wm_resources_request'].includes(name))return window.planBackend(name,args,F.session.user.id);\n    F.calls.push");
 await ctx.addInitScript({content:init});await p.route('**/*',r=>r.request().url()==='https://wm.test/'?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());await p.goto('https://wm.test/');
 async function as(uid,team=ids.team){await p.evaluate(({uid,team,ids})=>{
  closeSheets();session=fixture.session={user:{id:uid}};activeTeam={id:team,name:'Synthetic team'};activeSeason={id:ids.season};managedLogin=null;
  isStaff=actualIsStaff=isTeamAdmin=actualIsTeamAdmin=uid===ids.coach;isManager=false;viewMode=uid===ids.coach?'staff':'parent';accountProfileData={id:uid,ui_preferences:{}};
  show('authView',false);show('appView',true);applyRoleUI();
 },{uid,team,ids});}
 const loaded=()=>p.waitForFunction(()=>!!document.querySelector('#teamPlanBody h3'));
 async function open(){await p.evaluate(()=>WMTeamPlan.open());await loaded();}
 await as(ids.coach);await p.evaluate(()=>setTab('more'));await p.locator('[data-clipboard-category="settings"]').click();await p.locator('[data-clipboard-tool="teamPlanBtn"]').click();await loaded();
 assert.match(await p.locator('#teamPlanBody').innerText(),/TestFlight pilot/);assert.equal(await p.locator('#teamPlanBody button').count(),0);assert.match(await p.locator('#teamPlanBody').innerText(),/Purchases are not open/);
 assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await p.screenshot({path:path.join(root,'validation/team-plan-phone.png')});pass('Team Plan opens through Clipboard Settings with free pilot status and no purchase action at phone width');
 await f.pilot(false);await f.apply();await open();assert.match(await p.locator('#teamPlanBody').innerText(),/Current access runs through/);
 await as(ids.coach,ids.other);await open();assert.equal(await p.locator('#teamPlanBody h3').first().innerText(),'Free');pass('The same coach sees Full Year for the paid team and Free for another team');
 await as(ids.parent);await open();assert.match(await p.locator('#teamPlanBody').innerText(),/coach or team administrator/);assert.doesNotMatch(await p.locator('#teamPlanBody').innerText(),/Current access runs through/);pass('Parents see shared coverage without administrator billing dates');
 await as(ids.coach);fail=true;await p.evaluate(()=>WMTeamPlan.open());await p.waitForFunction(()=>document.querySelector('#teamPlanStatus').textContent.includes('unavailable'));assert.equal(await p.locator('#teamPlanBody h3').count(),0);
 fail=false;await p.locator('#teamPlanRefresh').click();await loaded();pass('A failed plan request clears old status and supports retry without granting local access');
 delay=500;await p.evaluate(()=>WMTeamPlan.open());await as(ids.coach,ids.other);await p.evaluate(()=>WMTeamPlan.open());await loaded();await new Promise(r=>setTimeout(r,600));
 assert.equal(await p.locator('#teamPlanBody h3').first().innerText(),'Free');assert.doesNotMatch(await p.locator('#teamPlanBody').innerText(),/Current access runs through/);delay=0;pass('Late paid-team responses cannot overwrite another team’s plan');
 await p.evaluate(()=>{managedLogin={shared_login_id:'test'};WMTeamPlan.sync();});assert(await p.locator('#teamPlanSheet').evaluate(n=>n.classList.contains('hidden')));assert.equal(await p.locator('#teamPlanBody').innerText(),'');pass('Managed account changes close the plan screen and clear its data');
 await as(ids.coach);await p.evaluate(()=>{setTab('more');WMClipboard.reset();});await p.locator('[data-clipboard-category="gear"]').click();await p.locator('[data-clipboard-tool="clipboardEquipmentBtn"]').click();await p.locator('#wmEquipmentTitle').waitFor();
 await p.locator('#wmEquipmentTitle').fill('=Synthetic spreadsheet formula');await p.locator('#wmEquipmentQty').fill('2');await p.locator('#wmEquipmentNotes').fill('Quotes " and commas, stay intact');await p.locator('#wmEquipmentForm button').click();await p.locator('[data-equip="equipment_out"]').waitFor();
 await p.locator('[data-equip="equipment_out"]').click();await p.waitForFunction(()=>document.querySelector('#wmExtraBody').textContent.includes('1 available · 1 issued'));pass('Clipboard Equipment reaches the actual SQL-backed inventory and saves issue counts');
 await f.apply({event:'expired',revision:1,status:'expired'});await p.evaluate(()=>WMExtras.equipment());await p.locator('#wmEquipmentExport').waitFor();assert.equal(await p.locator('#wmEquipmentForm').count(),0);assert.equal(await p.locator('[data-equip]').count(),0);
 const [download]=await Promise.all([p.waitForEvent('download'),p.locator('#wmEquipmentExport').click()]);const csv=fs.readFileSync(await download.path(),'utf8');assert(csv.includes("\"'=Synthetic spreadsheet formula\""));assert(csv.includes('Quotes "" and commas, stay intact'));assert.match(csv,/"2","1","1"/);pass('Expired subscriptions keep a usable inventory CSV export with spreadsheet formula escaping');
 await p.screenshot({path:path.join(root,'validation/inventory-expired-phone.png')});
 await p.evaluate(()=>closeSheets());await p.locator('[data-clipboard-tool="clipboardFilesBtn"]').click();await p.waitForFunction(()=>document.querySelector('#wmExtraTitle').textContent==='Files & Photos'&&document.querySelector('#wmExtraStatus').textContent==='');assert.equal(await p.locator('#wmMediaForm').count(),1);pass('Clipboard Files opens the existing file module without a placeholder');
 await as(ids.coach);await open();await p.evaluate(()=>document.body.classList.add('kiosk-locked'));await p.waitForFunction(()=>document.querySelector('#teamPlanSheet').classList.contains('hidden'));assert.equal(await p.locator('#teamPlanBody').innerText(),'');pass('Kiosk lock hides and clears the plan projection');
 assert.deepEqual(errors,[]);pass('Whole-page app runs without uncaught JavaScript errors');
 fs.writeFileSync(path.join(root,'validation/team-plan-browser.json'),JSON.stringify({passed:tests.length,tests,viewport:'390 × 844',engine:'Chromium + isolated PGlite; synthetic accounts; no network or production writes'},null,2));await browser.close();await db.close();
})().catch(e=>{console.error(e);process.exit(1)});
