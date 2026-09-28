const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[];const pass=x=>{passed.push(x);console.log('PASS',x)};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await ctx.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://theteammanager.app/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady);
 await p.evaluate(()=>{
  session=fixture.session={user:{id:'athlete',email:'real.athlete@example.invalid'},access_token:'synthetic'};managedLogin=null;activeTeam=null;show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
  fixture.profile={id:'profile',name:'Published Athlete',self:true,athlete:true,manager:false,details:{bio:'Published bio'},sharing:{bio:true},discoverable:false};fixture.records=[];fixture.calls=[];fixture.uploads=[];fixture.policy={auto_approve:false,review_photos:true};fixture.contact={email:'',phone:'',share_email_with_coaches:false,share_phone_with_coaches:false};
  const copy=x=>JSON.parse(JSON.stringify(x));
  client.rpc=async(name,a={})=>{
   fixture.calls.push({name,...copy(a)});if(name==='wrestling_profiles_request'){
    if(a.p_action==='search')return {data:[{id:'result',name:'Search Athlete',details:{bio:'Found profile'},sharing:{},discoverable:true}]};if(a.p_action==='mine')return {data:[copy(fixture.profile)]};if(a.p_action==='view')return {data:a.p_data.id==='result'?{id:'result',name:'Search Athlete',details:{bio:'Found profile'},sharing:{},discoverable:true}:copy(fixture.profile)};
    if(a.p_action==='save'){fixture.profile={...fixture.profile,...a.p_data};return {data:copy(fixture.profile)};}return {data:[]};
   }
   if(name==='wm_profile_approval_request'){
    if(a.p_action==='settings'||a.p_action==='set_settings'){if(a.p_action==='set_settings')fixture.policy={auto_approve:a.p_data.auto_approve,review_photos:a.p_data.review_photos};return {data:[{profile_id:'profile',name:'Published Athlete',can_manage:fixture.profile.manager,policy:copy(fixture.policy)}]};}
    const d=a.p_data,latest=fixture.records.filter(r=>['draft','pending','rejected'].includes(r.status)).at(-1);
    if(a.p_action==='context')return {data:{approval_required:!fixture.profile.manager,profile_id:'profile',draft:latest||null,expected:{v:1},policy:copy(fixture.policy),contact:copy(fixture.contact)}};
    if(a.p_action==='prepare'){if(fixture.profile.manager)return {data:{approval_required:false}};const id='request-'+(fixture.records.length+1),r={id,profile_id:'profile',name:fixture.profile.name,status:'uploading',proposal:d.proposal||latest?.proposal||copy(fixture.profile),path:d.new_photo?id+'.jpg':latest?.path||null};fixture.records.push(r);return {data:{...r,approval_required:true,bucket:'profile-photo-requests'}};}
    if(a.p_action==='list')return {data:copy(fixture.records.filter(r=>!['uploading','superseded'].includes(r.status)).map(r=>({...r,can_review:fixture.profile.manager})))};
    const r=fixture.records.find(r=>r.id===d.id);if(a.p_action==='save_draft'){fixture.records.forEach(x=>{if(x!==r&&['draft','pending'].includes(x.status))x.status='superseded'});r.status='draft';}
    if(a.p_action==='submit'){if(fixture.noGuardian)return {error:{message:'Ask your coach to link a parent or guardian.'}};r.status='pending';if(fixture.policy.auto_approve&&r.proposal.name===fixture.profile.name&&JSON.stringify(r.proposal.contact||fixture.contact)===JSON.stringify(fixture.contact)){if(r.path&&!fixture.policy.review_photos)return {data:{status:'pending',pending:true,auto_photo:true}};if(!r.path){r.status='approved';fixture.profile={...fixture.profile,...r.proposal};}}}
    if(a.p_action==='approve'){r.status='approved';fixture.profile={...fixture.profile,...r.proposal};}
    if(a.p_action==='reject')r.status='rejected';return {data:{status:r.status,pending:r.status==='pending'}};
   }
   if(name==='wm_profile_photo_request'){
    if(a.p_action==='prepare')return {data:{id:'profile',bucket:'athlete-photos',prefix:'athlete',expected:{social:'old'}}};
    if(a.p_action==='commit'){const r=fixture.records.find(r=>r.id===a.p_data.approval_id);if(r){r.status='approved';fixture.profile={...fixture.profile,...r.proposal};}fixture.committed=a.p_data;return {data:{saved:true}};}
   }
   return {data:[]};
  };
  client.storage.from=bucket=>({upload:async(path,blob)=>{fixture.uploads.push({bucket,path,type:blob.type});return {error:fixture.failUpload?{message:'Upload failed'}:null}},download:async()=>{if(fixture.failDownload)return {error:{message:'Offline'}};const c=document.createElement('canvas');c.width=40;c.height=40;c.getContext('2d').fillRect(0,0,40,40);return {data:await new Promise(r=>c.toBlob(r,'image/jpeg'))};},createSignedUrl:async()=>({data:null}),remove:async()=>({})});
  window.WMOperations={open:async()=>{},close:()=>{}};window.WMFamily={home:async()=>{}};window.WMNotificationSync={readChanged:()=>{}};
 });
 // Same horizontal Locker Room rail; no document overflow on narrow phones.
 await p.locator('#lockerMyProfileTab').click();await p.waitForSelector('.wp-hero');
 assert.equal(await p.locator('.wp-hero h2').innerText(),'Published Athlete');
 await p.locator('#wrestlingProfilesSheet > .sheet-returnbar button').click();
 assert(await p.locator('#wrestlingProfilesSheet').isHidden());
 await p.locator('#lockerFindProfileTab').click();await p.locator('#wpQuery').fill('Search');
 await p.locator('#wpSearchForm button').click();await p.locator('#wpSearchResults [data-wp-open]').waitFor();
 const y=await p.locator('#wrestlingProfilesSheet').evaluate(el=>{el.scrollTop=130;return el.scrollTop;});
 await p.locator('#wpSearchResults [data-wp-open]').click();await p.waitForSelector('.wp-hero');
 await p.locator('#wrestlingProfilesSheet > .sheet-returnbar button').click();
 assert.equal(await p.locator('#wpQuery').inputValue(),'Search');assert.equal(await p.locator('#wpSearchResults b').innerText(),'Search Athlete');
 assert(Math.abs(await p.locator('#wrestlingProfilesSheet').evaluate(el=>el.scrollTop)-y)<2);
 pass('My Profile opens the athlete directly; Back from Find Profile restores the query, results and scroll');
 await p.evaluate(()=>{closeSheets();document.getElementById('accountDisplayName').value='Unsaved account text';openSheet('accountSheet');});
 await p.evaluate(()=>WMProfiles.myProfile());
 await p.getByRole('button',{name:'Build / edit my profile',exact:true}).click();
 await p.locator('#wp_bio').fill('Unsaved edit');
 await p.locator('#wrestlingProfilesSheet > .sheet-returnbar button').click();await p.waitForSelector('.wp-hero');
 await p.locator('#wrestlingProfilesSheet > .sheet-returnbar button').click();
 assert(await p.locator('#accountSheet').isVisible());assert.equal(await p.locator('#accountDisplayName').inputValue(),'Unsaved account text');
 pass('Back moves from editing to the profile and then restores the account screen without losing its form');
 await p.evaluate(()=>{fixture.profile.manager=true;fixture.profile.self=false;return WMProfileApprovals.open();});
 assert(await p.locator('[data-review-photos]').isDisabled());
 await p.locator('[data-auto-profile]').check();await p.locator('[data-review-photos]').uncheck();await p.locator('[data-save-profile-policy]').click();
 await p.waitForFunction(()=>document.querySelector('.profile-policy-note').textContent.startsWith('Parent settings saved'));
 assert.deepEqual(await p.evaluate(()=>fixture.policy),{auto_approve:true,review_photos:false});
 await p.screenshot({path:path.join(root,'validation/profile-parent-controls-phone.png')});
 pass('Linked parent can save both simple controls; review photos is disabled when every change needs review');
 await p.evaluate(()=>{fixture.profile.manager=false;fixture.profile.self=true;return WMProfiles.myProfile();});
 await p.locator('[data-wp-edit]').last().click();await p.locator('#wp_bio').fill('Live automatic bio');await p.locator('#wpSave').click();
 await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.startsWith('Profile saved. Your parent'));
 assert.equal(await p.evaluate(()=>fixture.profile.details.bio),'Live automatic bio');
 await p.locator('[data-wp-edit]').last().click();await p.locator('#wpName').fill('Waiting name');await p.locator('#wpSave').click();
 await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.startsWith('Sent for parent approval'));
 assert.equal(await p.evaluate(()=>fixture.profile.name),'Published Athlete');
 pass('Automatic edit success is distinguished from protected edits waiting for approval');
 // A fresh approved-name draft carries an automatically allowed photo through commit.
 await p.evaluate(async()=>{fixture.records=[];const result=await saveUnifiedProfilePhoto(new Blob(['photo'],{type:'image/jpeg'}),{kind:'account'});fixture.autoResult=result;});
 assert.equal(await p.evaluate(()=>fixture.autoResult.pending),false);
 assert.deepEqual(await p.evaluate(()=>fixture.uploads.slice(-3).map(x=>x.bucket)),['profile-photo-requests','athlete-photos','wrestling-profile-photos']);
 pass('Automatic photo flow uploads a private candidate then completes the authorized atomic photo commit');
 await p.evaluate(()=>WMProfileApprovals.open());await p.locator('#profileApprovalsClose').click();
 assert(await p.locator('#profileApprovalsSheet').isHidden());assert(await p.locator('#sheetBackdrop').isHidden());
 await p.evaluate(()=>{closeSheets();openSheet('accountSheet');});await p.evaluate(()=>WMProfiles.myProfile());
 await p.evaluate(()=>{session={user:{id:'changed-account'}};});await p.locator('#wrestlingProfilesSheet > .sheet-returnbar button').click();
 assert(await p.locator('#accountSheet').isHidden());assert(await p.locator('#wrestlingProfilesSheet').isHidden());
 pass('Close removes the approval backdrop; Back cannot restore private screens after an account switch');
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));assert(await p.locator('.locker-room-tabs').evaluate(el=>el.scrollWidth>el.clientWidth));}
 await p.screenshot({path:path.join(root,'validation/profile-shortcuts-phone.png')});
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/profile-controls-browser.json'),JSON.stringify({passed,engine:'Chromium; actual app with synthetic API fixtures',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
