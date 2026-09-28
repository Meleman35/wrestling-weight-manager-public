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
  fixture.profile={id:'profile',name:'Published Athlete',self:true,athlete:true,manager:false,details:{bio:'Published bio'},sharing:{bio:true},discoverable:false};fixture.records=[];fixture.calls=[];fixture.uploads=[];
  const copy=x=>JSON.parse(JSON.stringify(x));
  client.rpc=async(name,a={})=>{
   fixture.calls.push({name,...copy(a)});if(name==='wrestling_profiles_request'){
    if(a.p_action==='mine')return {data:[copy(fixture.profile)]};if(a.p_action==='view')return {data:copy(fixture.profile)};
    if(a.p_action==='save'){fixture.profile={...fixture.profile,...a.p_data};return {data:copy(fixture.profile)};}return {data:[]};
   }
   if(name==='wm_profile_approval_request'){
    if(a.p_action==='settings')return {data:[]};
    const d=a.p_data,latest=fixture.records.filter(r=>['draft','pending','rejected'].includes(r.status)).at(-1);
    if(a.p_action==='context')return {data:{approval_required:!fixture.profile.manager,profile_id:'profile',draft:latest||null,expected:{v:1}}};
    if(a.p_action==='prepare'){if(fixture.profile.manager)return {data:{approval_required:false}};const id='request-'+(fixture.records.length+1),r={id,profile_id:'profile',name:fixture.profile.name,status:'uploading',proposal:d.proposal||latest?.proposal||copy(fixture.profile),path:d.new_photo?id+'.jpg':latest?.path||null};fixture.records.push(r);return {data:{...r,approval_required:true,bucket:'profile-photo-requests'}};}
    if(a.p_action==='list')return {data:copy(fixture.records.filter(r=>!['uploading','superseded'].includes(r.status)).map(r=>({...r,can_review:fixture.profile.manager})))};
    const r=fixture.records.find(r=>r.id===d.id);if(a.p_action==='save_draft'){fixture.records.forEach(x=>{if(x!==r&&['draft','pending'].includes(x.status))x.status='superseded'});r.status='draft';}
    if(a.p_action==='submit'){if(fixture.noGuardian)return {error:{message:'Ask your coach to link a parent or guardian.'}};r.status='pending';}
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
 await p.evaluate(()=>WMProfiles.openProfile('profile'));assert.equal(await p.locator('[data-wp-name]').count(),0);await p.getByRole('button',{name:'Build / edit my profile',exact:true}).click();
 await p.locator('#wpName').fill('Real First Last');await p.locator('#wp_bio').fill('My complete private profile');await p.locator('#wpDiscover').check();
 await p.locator('#wpDraftSave').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.startsWith('Private draft saved'));
 assert.equal(await p.evaluate(()=>fixture.profile.name),'Published Athlete');assert.equal(await p.evaluate(()=>fixture.records.at(-1).proposal.name),'Real First Last');
 pass('Minor can edit a complete profile and save privately without changing the published name or details');
 await p.getByRole('button',{name:'Build / edit my profile',exact:true}).click();assert.equal(await p.locator('#wpName').inputValue(),'Real First Last');assert.equal(await p.locator('#wp_bio').inputValue(),'My complete private profile');
 await p.evaluate(()=>fixture.noGuardian=true);await p.locator('#wpSave').click();await p.waitForFunction(()=>!document.getElementById('wpSave').disabled);assert.match(await p.locator('#wpEditStatus').innerText(),/private draft is saved.*link a parent/);assert.equal(await p.evaluate(()=>fixture.profile.name),'Published Athlete');
 await p.evaluate(()=>fixture.noGuardian=false);await p.locator('#wpSave').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.startsWith('Sent for parent approval'));
 assert.equal(await p.evaluate(()=>fixture.calls.filter(c=>c.name==='wrestling_profiles_request'&&c.p_action==='save').length),0);
 pass('Reopening retains the draft; missing guardian leaves it saved; sending uses approval RPC without a live save');
 // The crop entry used in the reported screenshot now uploads privately and sends approval.
 await p.evaluate(async()=>{const r=await saveUnifiedProfilePhoto(new Blob(['test'],{type:'image/jpeg'}),{kind:'account'});fixture.cropResult=r;});
 assert.equal(await p.evaluate(()=>fixture.cropResult.pending),true);assert.deepEqual(await p.evaluate(()=>fixture.uploads.map(x=>x.bucket)),['profile-photo-requests']);
 pass('Account photo crop routes a minor upload to private storage and returns an explicit pending state');
 await p.evaluate(()=>{fixture.profile.manager=true;fixture.profile.self=false;return WMProfileApprovals.open();});await p.waitForFunction(()=>!document.querySelector('[data-approve-profile]').disabled);
 await p.locator('[data-approve-profile]').click();assert.match(await p.locator('[data-approval-note]').last().innerText(),/Review the profile/);
 await p.locator('[data-review-confirm]').check();await p.locator('[data-approve-profile]').click();await p.waitForFunction(()=>document.getElementById('profileApprovalsStatus').textContent.startsWith('Profile approved'));
 assert.equal(await p.evaluate(()=>fixture.profile.name),'Real First Last');assert(await p.evaluate(()=>!!fixture.committed.approval_id));
 assert.deepEqual(await p.evaluate(()=>fixture.uploads.map(x=>x.bucket)),['profile-photo-requests','athlete-photos','wrestling-profile-photos']);
 pass('Parent sees full pending profile and photo; checked review publishes through the atomic approval commit');
 await p.evaluate(()=>{fixture.records.at(-1).status='pending';fixture.failDownload=true;return WMProfileApprovals.open();});await p.waitForFunction(()=>document.querySelector('[data-approval-note]').textContent.includes('Photo could not load'));assert(await p.locator('[data-approve-profile]').isDisabled());
 await p.locator('[data-reject-profile]').click();await p.waitForFunction(()=>document.getElementById('profileApprovalsStatus').textContent.startsWith('Changes requested'));
 pass('Unavailable photos cannot be approved; parent can request changes without altering the published profile');
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.getElementById('profileApprovalsSheet').scrollWidth<=document.getElementById('profileApprovalsSheet').clientWidth+1));}
 await p.screenshot({path:path.join(root,'validation/profile-approval-phone.png')});
 await p.evaluate(()=>{session={user:{id:'other'}};WMProfiles.reset();});assert.equal(await p.locator('#profileApprovalsBody').innerText(),'');
 pass('Approval view fits phones and resets private details when the account changes');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/profile-approval-browser.json'),JSON.stringify({passed,engine:'Chromium; actual app and synthetic API fixtures',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
