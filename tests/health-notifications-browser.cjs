const fs=require('fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']}),ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[],checks=[];
p.on('pageerror',e=>errors.push(e.message));const pass=s=>{checks.push(s);console.log('PASS',s)};
await ctx.addInitScript({content:fs.readFileSync('tests/browser-fixture.js','utf8')});const html=fs.readFileSync('index.html','utf8');
await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
await p.goto('https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
await p.evaluate(()=>{
 session={user:{id:'trainer',email:'trainer@example.test'}};fixture.session=session;activeTeam={id:'team-a',name:'Sample Wrestling'};viewMode='coach';isTeamAdmin=false;actualIsStaff=false;isStaff=false;isManager=true;staffMembership={permissions:{staff_role:'team_trainer'}};
 show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
 window.healthTest={trainer:false,parent:false,coach:false,baseline:null,cases:[],updates:[],files:[],calls:[],uploads:[],delay:0,allow:false};
 const old=client.rpc;client.rpc=async(name,args)=>{
  if(name!=='athlete_health_request')return old(name,args);
  healthTest.calls.push(structuredClone(args));if(healthTest.delay)await new Promise(r=>setTimeout(r,healthTest.delay));
  const h=healthTest,d=args.p_data,action=args.p_action,now=new Date().toISOString();
  if(action==='dashboard')return {data:{assigned_trainer:!h.parent&&!h.coach,trainer:h.trainer,coach:h.coach,admin:h.coach,school_year_start:'2026-07-01',baseline_required:true,trainers:[{name:'Sample Trainer',accepted:h.trainer}],athletes:h.trainer||h.parent||h.coach?[{id:'athlete',name:'Sample Athlete',baseline:h.baseline,cases:h.cases,guardian:h.parent,can_submit:true,can_upload:true,clinical:!h.coach,family_permission:{allow_updates:h.allow,allow_photos:h.allow}}]:[]}};
  if(action==='accept_trainer'){h.trainer=true;return {data:{accepted:true}}}
  if(action==='baseline'){h.baseline={provider:d.provider,completed_on:d.completed_on};return {data:{saved:true}}}
  if(action==='family_permission'){h.allow=d.allow_updates;return {data:{saved:true}}}
  if(action==='new_case'){h.cases=[{id:'case',athlete_id:'athlete',category:d.category,status:'awaiting_trainer',participation_note:'',revision:1}];h.updates=[{id:'update',body:d.body,visibility:'care_team',author:'Sample Trainer',created_at:now}];return {data:{case_id:'case'}}}
  if(action==='case')return {data:{case:h.cases[0],athlete_name:'Sample Athlete',trainer:h.trainer,guardian:h.parent,can_submit:true,can_upload:true,updates:h.coach?h.updates.filter(n=>n.visibility==='participation'):h.updates,files:h.coach?[]:h.files}};
  if(action==='participation'){Object.assign(h.cases[0],d,{revision:h.cases[0].revision+1});h.updates.push({author:'Sample Trainer',visibility:'participation',body:d.participation_note,created_at:now});return {data:{saved:true}}}
  if(action==='update'){h.updates.push({author:'Sample Trainer',visibility:d.visibility,body:d.body,created_at:now});return {data:{saved:true}}}
  if(action==='reserve_file'){h.files=[{id:'file',kind:d.file_kind,mime:d.mime_type,created_at:now}];return {data:{id:'file',bucket:'athlete-health',path:'team/athlete/case/file.jpg'}}}
  if(action==='complete_file')return {data:{saved:true}};
  if(action==='file')return {data:{bucket:'athlete-health',path:'team/athlete/case/file.jpg',mime:'image/jpeg'}};
 };
 client.storage={from:bucket=>({upload:async(path,blob,options)=>{healthTest.uploads.push({bucket,path,size:blob.size,type:blob.type,options});return {error:null}},download:async()=>({data:new Blob([Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAIAAAAC64paAAAAHUlEQVR4nGMsnr6KgVzARLbOUc2jmkc1j2qmimYAfr0B3FielmoAAAAASUVORK5CYII='),c=>c.charCodeAt(0))],{type:'image/jpeg'})})})};
});
// Appended to the existing synthetic browser fixture by the preparation script.
await p.evaluate(()=>{
 const originalRpc=client.rpc,originalFrom=client.from;
 healthTest.trainer=true;healthTest.notices=[];healthTest.marked=[];healthTest.noticeError=false;healthTest.noticeDelay=0;
 client.rpc=async(name,args)=>{
  const h=healthTest;
  if(name==='health_notification_open'){
   const allowed=session.user.id==='parent',error=h.noticeError,wait=h.noticeDelay;
   if(wait)await new Promise(r=>setTimeout(r,wait));
   return error||!allowed?{error:{message:'This care update is no longer available to this account'}}:{data:{team_id:'team-a',case_id:'case',update_id:'update'}};
  }
  if(name==='get_notification_badge_count')return {data:h.notices.filter(n=>n.user_id===session.user.id&&!n.read_at).length};
  if(name==='mark_communication_notifications_read'){
   for(const id of args.p_notification_ids){const n=h.notices.find(n=>n.id===id&&n.user_id===session.user.id);if(n){n.read_at=new Date().toISOString();h.marked.push(id)}}
   return {data:h.marked.length};
  }
  const result=await originalRpc(name,args);
  if(name==='athlete_health_request'&&result?.data){
   if(args.p_action==='dashboard')result.data.care_notifications='in_app_v1';
   if(args.p_action==='new_case'){h.updates[0].visibility=args.p_data.visibility;result.data.notifications_created=1;}
   if(args.p_action==='update')result.data.notifications_created=1;
  }
  return result;
 };
 client.from=table=>{
  if(table!=='communication_notifications')return originalFrom(table);
  let user='',cursor='',unread=false;
  const q={select(){return q},eq(k,v){if(k==='user_id')user=v;return q},is(k,v){if(k==='read_at')unread=true;return q},order(){return q},limit(){return q},gt(k,v){cursor=v;return q},then(resolve){return Promise.resolve({data:healthTest.notices.filter(n=>n.user_id===user&&(!unread||!n.read_at)&&(!cursor||n.id>cursor)),error:null}).then(resolve)}};return q;
 };
 client.functions={invoke:async()=>({data:{ok:true,count:hCount()},error:null})};
 function hCount(){return healthTest.notices.filter(n=>n.user_id===session.user.id&&!n.read_at).length}
 availableTeams=[activeTeam];
});
await p.evaluate(()=>WMAthleteHealth.open());await p.waitForSelector('[data-health-athlete]');await p.locator('[data-health-athlete]').click();
assert.equal(await p.locator('#healthNewCase').innerText(),'New Care Update');await p.locator('#healthNewCase').click();
assert.equal(await p.locator('#healthCreate').innerText(),'Send to Parents / Guardians');
assert.equal(await p.locator('#healthNewVisibility').inputValue(),'care_team');
await p.locator('#healthNewVisibility').selectOption('participation');assert.equal(await p.locator('#healthCreate').innerText(),'Send to Parents & Coaches');
await p.locator('#healthConcern').fill('SYNTHETIC SHARED UPDATE');await p.locator('#healthCreate').click();await p.waitForSelector('#healthRecordRefresh');
assert.equal(await p.evaluate(()=>healthTest.calls.find(c=>c.p_action==='new_case').p_data.visibility),'participation');
await p.waitForFunction(()=>document.getElementById('healthStatus').textContent.includes('In-app notifications created'));
assert.equal(await p.locator('#healthUpdateVisibility').inputValue(),'care_team');
assert.equal(await p.locator('#healthSendUpdate').innerText(),'Send to Parents / Guardians');
await p.locator('#healthUpdateVisibility').selectOption('participation');assert.equal(await p.locator('#healthSendUpdate').innerText(),'Send to Parents & Coaches');
pass('Trainer creates a care update with explicit private/shared recipients; existing private updates are not silently shared');
for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1))}
await p.setViewportSize({width:390,height:844});await p.screenshot({path:'validation/health-notification-trainer-phone.png'});
await p.evaluate(()=>{
 WMAthleteHealth.close();session=fixture.session={user:{id:'parent',email:'parent@example.test'}};
 healthTest.trainer=false;healthTest.parent=true;currentTeamMemberships=[{role:'parent_guardian',active:true}];
 healthTest.notices=[{id:'notice-1',user_id:'parent',team_id:'team-a',health_update_id:'update',category:'system',title:'New participation update',body:'Open this update securely.',created_at:new Date().toISOString(),read_at:null}];
 return WMNotificationSync.refresh();
});
await p.locator('#roleNotificationsBtn').click();await p.waitForSelector('[data-notification-id="notice-1"]');
assert.match(await p.locator('[data-notification-id="notice-1"] b').innerText(),/Unread/);
assert.equal(await p.locator('[data-notification-id="notice-1"] b').evaluate(e=>getComputedStyle(e).color),'rgb(180, 35, 24)');
await p.locator('[data-notification-id="notice-1"]').click();await p.waitForSelector('#healthRecordRefresh');
await p.waitForFunction(()=>healthTest.marked.includes('notice-1'));
assert.equal(await p.locator('.health-update-current').count(),1);assert.match(await p.locator('.health-update-current').innerText(),/SYNTHETIC SHARED UPDATE/);
assert.equal(await p.locator('#communicationNotificationsSheet').isVisible(),false);
assert.equal(await p.locator('#teamSwitcherSheet').isVisible(),false);
assert.equal(await p.locator('#healthSendUpdate').innerText(),'Send to Team Trainer');
await p.screenshot({path:'validation/health-notification-parent-destination-phone.png'});
pass('Parent bell opens inbox directly; a red unread care notice opens and highlights the exact concern update before being marked read');
await p.locator('#healthNotificationsBtn').click();assert(await p.locator('#communicationNotificationsSheet').isVisible());
await p.evaluate(()=>{closeSheets();healthTest.notices[0].read_at=null;healthTest.marked=[];healthTest.noticeError=true;return WMNotificationSync.refresh()});
await p.locator('#teamUnreadBadge').click();await p.waitForSelector('[data-notification-id="notice-1"]');assert.equal(await p.locator('#teamSwitcherSheet').isVisible(),false);
await p.locator('[data-notification-id="notice-1"]').click();await p.waitForFunction(()=>document.getElementById('healthStatus').textContent.includes('no longer available'));
assert.equal(await p.locator('#healthBody').innerText(),'');assert.equal(await p.evaluate(()=>healthTest.marked.length),0);
pass('Access-denied notification clears the concern view and stays unread; clicking the team badge does not open another generic menu');
await p.evaluate(()=>{closeSheets();healthTest.noticeError=false;healthTest.noticeDelay=600;return WMNotificationSync.open()});
await p.locator('[data-notification-id="notice-1"]').click();
await p.evaluate(()=>{session=fixture.session={user:{id:'unrelated'}}});await p.waitForTimeout(850);
assert.equal(await p.locator('#healthBody').innerText(),'');assert.equal(await p.evaluate(()=>healthTest.marked.length),0);
pass('Late notification resolution cannot reveal a prior account\'s concern or mark its update read');
await p.evaluate(()=>{session=fixture.session={user:{id:'parent'}};healthTest.noticeDelay=0;return WMAthleteHealth.open({notificationId:'notice-1'})});
await p.waitForSelector('#healthRecordRefresh');await ctx.setOffline(true);await p.waitForSelector('#athleteHealthSheet.hidden',{state:'attached'});
assert.equal(await p.locator('#healthBody').innerText(),'');pass('Going offline clears the opened private care record');
assert.deepEqual(errors,[]);
fs.writeFileSync('validation/health-notifications-browser.json',JSON.stringify({checks,syntheticOnly:true,physicalDeviceTested:false,externalDelivery:false},null,2));
await browser.close();

})().catch(e=>{console.error(e);process.exit(1)});
