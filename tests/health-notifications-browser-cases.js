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
