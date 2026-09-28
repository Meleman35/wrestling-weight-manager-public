const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[];const pass=s=>{passed.push(s);console.log('PASS',s)};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await ctx.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://theteammanager.app/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady);
 await p.evaluate(()=>{
  session=fixture.session={user:{id:'parent',email:'parent@example.invalid'},access_token:'synthetic'};managedLogin=null;activeTeam={id:'team-a',name:'Team Alpha'};show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
  fixture.calls=[];fixture.saved=[];fixture.data={};const clone=x=>JSON.parse(JSON.stringify(x));
  fixture.context=(team='team-a',athlete='child-a')=>{
   const key=team+':'+athlete;if(fixture.data[key])return clone(fixture.data[key]);
   return fixture.data[key]={teams:[{id:'team-a',name:'Team Alpha'},{id:'team-b',name:'Team Beta'}],children:[{id:'child-a',name:'Alex Athlete',profile_id:'profile-a'},{id:'child-b',name:'Blair Athlete',profile_id:'profile-b'}],team_id:team,athlete_id:athlete,profile_id:athlete==='child-a'?'profile-a':'profile-b',is_minor:true,pending_reviews:2,
    profile:{auto_approve:false,review_photos:true,discoverable:false,sharing:{bio:true}},privacy:{share_email_with_coaches:false,share_phone_with_coaches:false,share_birth_date_with_coaches:false,disclose_medical_to_coaches:false,sms_opt_in:false},
    chat:{team_chat:false,group_chat:false,peer_to_peer:false,coach_to_athlete:false,media_view:true,media_send_group:false,media_send_direct:false},
    notifications:{push_messages:true,sms_message_fallback:true,email_messages:false,push_announcements:true,sms_announcements:true,email_announcements:true,push_weigh_ins:true,guardian_alerts_only:false,quiet_start:'20:00:00',quiet_end:'08:00:00',time_zone:'America/Denver'},
    tournament:{level:'upcoming',revision:0},goals:{enabled:false,revision:0,team_enabled:false},video:{available:false,allowed:false,live_available:false}};
  };
  client.rpc=async(name,args={})=>{fixture.calls.push({name,...clone(args)});if(name!=='parent_controls_request')return {data:[]};
   if(fixture.delay)await new Promise(r=>setTimeout(r,fixture.delay));if(fixture.fail)return {error:{message:'Simulated connection failure'}};
   const q=args.p_data,r=fixture.context(q.team_id||'team-a',q.athlete_id||'child-a');
   if(args.p_action!=='context'){const k=args.p_action.replace('save_','');fixture.saved.push(clone(args));r[k]={...r[k],...clone(q.values)};fixture.data[r.team_id+':'+r.athlete_id]=r;}
   return {data:clone(r)};
  };
  window.WMProfileApprovals.open=async f=>{fixture.review=f;document.getElementById('profileApprovalsBody').textContent='Review details';openSheet('profileApprovalsSheet');};
 });
 await p.locator('#lockerParentControlsTab').click();await p.locator('[data-parent-form="profile"]').waitFor();
 assert.equal(await p.locator('#parentControlsAthlete').inputValue(),'child-a');assert(await p.locator('[data-parent-field="review_photos"]').isDisabled());
 assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
 assert.equal(await p.locator('[data-parent-field="allowed"]').count(),0);
 await p.screenshot({path:path.join(root,'validation/parent-controls-phone.png')});
 pass('One phone-friendly hub exposes real controls, conservative defaults and video availability');
 await p.locator('[data-parent-field="auto_approve"]').check();await p.locator('[data-parent-field="review_photos"]').uncheck();
 await p.locator('#parentControlsAthlete').selectOption('child-b');assert.equal(await p.locator('#parentControlsAthlete').inputValue(),'child-a');
 assert.match(await p.locator('#parentControlsStatus').innerText(),/Save your changes/);
 await p.locator('[data-parent-form="profile"] button[type=submit]').click();await p.waitForFunction(()=>document.querySelector('[data-parent-form="profile"] [data-parent-note]').textContent.startsWith('Saved.'));
 assert.deepEqual(await p.evaluate(()=>({team:fixture.saved[0].p_data.team_id,athlete:fixture.saved[0].p_data.athlete_id,auto:fixture.saved[0].p_data.values.auto_approve,photos:fixture.saved[0].p_data.values.review_photos})),{team:'team-a',athlete:'child-a',auto:true,photos:false});
 await p.locator('#parentControlsAthlete').selectOption('child-b');await p.waitForFunction(()=>document.querySelector('.pc-intro h3').textContent==='Blair Athlete');
 assert.equal(await p.locator('[data-parent-field="auto_approve"]').isChecked(),false);
 await p.locator('#parentControlsAthlete').selectOption('child-a');await p.waitForFunction(()=>document.querySelector('.pc-intro h3').textContent==='Alex Athlete');assert(await p.locator('[data-parent-field="auto_approve"]').isChecked());
 pass('Unsaved changes block accidental child switches; saved policies remain scoped to the selected athlete');
 await p.locator('[data-parent-section="notifications"]>summary').click();
 await p.locator('[data-parent-field="guardian_alerts_only"]').check();await p.locator('[data-parent-field="quiet_start"]').fill('21:30');
 await p.evaluate(()=>fixture.fail=true);await p.locator('[data-parent-form="notifications"] button[type=submit]').click();
 await p.waitForFunction(()=>document.querySelector('[data-parent-form="notifications"] [data-parent-note]').textContent.includes('Simulated connection failure'));
 assert(await p.locator('[data-parent-field="guardian_alerts_only"]').isChecked());assert.equal(await p.locator('[data-parent-field="quiet_start"]').inputValue(),'21:30');
 await p.evaluate(()=>fixture.fail=false);await p.locator('[data-parent-form="notifications"] button[type=submit]').click();await p.waitForFunction(()=>document.querySelector('[data-parent-form="notifications"] [data-parent-note]').textContent.startsWith('Saved.'));
 assert.equal(await p.evaluate(()=>fixture.saved.at(-1).p_data.values.time_zone),'America/Denver');
 await p.locator('#parentControlsTeam').selectOption('team-b');await p.waitForFunction(()=>document.querySelector('#parentControlsTeam').value==='team-b'&&!document.querySelector('#parentControlsTeam').disabled);
 assert.equal(await p.evaluate(()=>activeTeam.id),'team-a');await p.locator('[data-parent-section="notifications"]>summary').click();assert.equal(await p.locator('[data-parent-field="guardian_alerts_only"]').isChecked(),false);
 pass('Failed saves retain edits; notification timezone and team scope are preserved without changing the active team');
 await p.locator('#parentControlsTeam').selectOption('team-a');await p.waitForFunction(()=>document.querySelector('#parentControlsTeam').value==='team-a'&&!document.querySelector('#parentControlsTeam').disabled);
 await p.locator('[data-parent-field="discoverable"]').check();await p.locator('#parentControlsReview').click();assert(await p.locator('#profileApprovalsSheet').isVisible());
 await p.locator('#profileApprovalsSheet > .sheet-returnbar button').click();assert(await p.locator('#parentControlsSheet').isVisible());assert(await p.locator('[data-parent-field="discoverable"]').isChecked());
 assert.deepEqual(await p.evaluate(()=>fixture.review),{profile_id:'profile-a'});
 await p.locator('[data-parent-reload="profile"]').click();await p.waitForFunction(()=>document.querySelector('[data-parent-form="profile"] [data-parent-note]').textContent==='Latest saved settings loaded.');assert.equal(await p.locator('[data-parent-field="discoverable"]').isChecked(),false);
 pass('Back from approval review restores the hub and unsaved form; explicit section reload discards only that section');
 await p.locator('[data-parent-section="chat"]>summary').click();assert(await p.locator('[data-parent-field="media_view"]').isChecked());assert.equal(await p.locator('[data-parent-field="media_send_group"]').isChecked(),false);
 await p.locator('[data-parent-field="team_chat"]').check();await p.locator('[data-parent-form="chat"] button[type=submit]').click();await p.waitForFunction(()=>document.querySelector('[data-parent-form="chat"] [data-parent-note]').textContent.startsWith('Saved.'));
 await p.locator('#parentControlsClose').click();assert(await p.locator('#sheetBackdrop').isHidden());
 await p.evaluate(()=>openAthleteChatPermissions());await p.locator('#parentControlsSheet').waitFor();assert(await p.locator('#athleteChatPermissionsSheet').isHidden());
 pass('View-media remains independent of send-media; existing parent chat entry opens the same hub');
 await p.evaluate(()=>{fixture.delay=180;WMParentControls.reset();WMParentControls.open();session={user:{id:'different-account'}};WMParentControls.reset();});
 await p.waitForTimeout(220);assert.equal(await p.locator('#parentControlsBody').innerText(),'');assert(await p.locator('#parentControlsSheet').isHidden());
 pass('Delayed responses cannot repopulate controls after an account change');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/parent-controls-browser.json'),JSON.stringify({passed,errors},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
