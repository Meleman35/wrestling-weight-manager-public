const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[];
const pass=s=>{passed.push(s);console.log('PASS',s);};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));
 await ctx.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://wm.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady===true);
 await p.evaluate(()=>{
   session=fixture.session={user:{id:'name-owner'},access_token:'synthetic'};managedLogin=null;activeTeam=null;
   show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
   fixture.profile={id:'profile-own',name:'Original Name',manager:true,self:true,athlete:false,details:{},sharing:{},discoverable:false};
   fixture.account={id:'name-owner',display_name:'Original Name',phone:null,photo_path:null,ui_preferences:{}};
   fixture.nameWrites=[];fixture.accountWrites=[];fixture.familyRefreshes=0;
   client.from=table=>{let patch,owner;return {select(){return this;},update(data){patch=data;return this;},eq(k,v){if(k==='id')owner=v;return this;},async maybeSingle(){return {data:{...fixture.account},error:null};},async single(){
     fixture.accountWrites.push({owner,patch});if(fixture.throwSave)throw Error('Connection interrupted');
     if(fixture.failSave)return {error:{message:'Save failed. Try again.'}};
     fixture.account={...fixture.account,...patch};fixture.profile.name=patch.display_name;return {data:{...fixture.account},error:null};
   }};};
   client.rpc=async(name,args)=>{
     if(name==='update_profile_name'){
       fixture.nameWrites.push(args);if(fixture.delaySave)await new Promise(r=>setTimeout(r,fixture.delaySave));
       if(fixture.failSave)return {error:{message:'Save failed. Try again.'}};
       fixture.profile.name=args.p_name;if(fixture.profile.self)fixture.account.display_name=args.p_name;
       return {data:{id:args.p_profile_id,name:args.p_name},error:null};
     }
     if(name==='wrestling_profiles_request')return {data:args.p_action==='mine'?[{...fixture.profile}]:args.p_action==='view'?{...fixture.profile}:[],error:null};
     return {data:{},error:null};
   };
   window.WMFamily={home:async()=>{fixture.familyRefreshes++;}};window.WMOperations={open:async()=>{},close:()=>{}};
 });
 await p.evaluate(()=>WMProfiles.openProfile('profile-own'));
 await p.locator('[data-wp-name]').click();await p.locator('#wpNameOnly').fill('  Zoë O’Neill-Smith  ');await p.locator('#wpNameSave').click();
 await p.waitForFunction(()=>document.getElementById('wpStatus').textContent==='Name saved.');
 assert.equal(await p.locator('.wp-hero h2').innerText(),'Zoë O’Neill-Smith');
 assert.deepEqual(await p.evaluate(()=>fixture.nameWrites.at(-1)),{p_profile_id:'profile-own',p_name:'Zoë O’Neill-Smith'});
 await p.evaluate(()=>openAccountSheet());assert.equal(await p.locator('#accountDisplayName').inputValue(),'Zoë O’Neill-Smith');
 await p.locator('#accountDisplayName').fill('Changed After Signup');await p.locator('#saveAccountProfileBtn').click();
 await p.waitForFunction(()=>document.getElementById('accountProfileStatus').textContent.startsWith('Saved.'));
 await p.evaluate(()=>WMProfiles.openProfile('profile-own'));assert.equal(await p.locator('.wp-hero h2').innerText(),'Changed After Signup');
 pass('Adults edit from the profile or account settings, and reopening either screen shows the saved name');
 // Minor profile drafting and parent review are covered by profile-approval-browser.cjs.
 await p.evaluate(()=>{fixture.profile.manager=false;fixture.profile.athlete=true;return WMProfiles.openProfile('profile-own');});
 assert.equal(await p.locator('[data-wp-name]').count(),0);assert.equal(await p.getByRole('button',{name:'Build / edit my profile',exact:true}).count(),1);
 pass('Minor name editing routes through the full parent-reviewed profile draft');
 await p.evaluate(()=>{fixture.profile.manager=true;fixture.profile.athlete=false;return WMProfiles.openProfile('profile-own');});
 await p.locator('[data-wp-name]').click();await p.locator('#wpNameOnly').fill('Retry Name');await p.evaluate(()=>fixture.failSave=true);
 await p.locator('#wpNameSave').click();await p.waitForFunction(()=>!document.getElementById('wpNameSave').disabled);
 assert.match(await p.locator('#wpNameStatus').innerText(),/Save failed/);assert.equal(await p.locator('#wpNameOnly').inputValue(),'Retry Name');
 await p.evaluate(()=>fixture.failSave=false);await p.locator('#wpNameSave').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent==='Name saved.');
 pass('Failed name saves retain the draft and let the user retry');
 // Parent management does not rename the parent's own account.
 await p.evaluate(()=>{fixture.profile.manager=true;fixture.profile.self=false;fixture.profile.name='Child Name';return WMProfiles.openProfile('profile-own');});
 await p.locator('[data-wp-name]').click();await p.locator('#wpNameOnly').fill('Child Corrected');await p.locator('#wpNameSave').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent==='Name saved.');
 assert.equal(await p.evaluate(()=>fixture.account.display_name),'Retry Name');
 pass('Linked-parent name editing keeps the parent identity separate');
 await p.locator('[data-wp-name]').click();
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.getElementById('wrestlingProfilesSheet').scrollWidth<=document.getElementById('wrestlingProfilesSheet').clientWidth+1));}
 await p.screenshot({path:path.join(root,'validation/profile-name-phone.png')});
 await p.locator('#wpNameOnly').fill('Unsaved Draft');await p.getByRole('button',{name:'Cancel',exact:true}).click();assert.equal(await p.locator('.wp-hero h2').innerText(),'Child Corrected');
 await p.evaluate(()=>{fixture.profile.manager=false;fixture.profile.self=false;return WMProfiles.openProfile('profile-own');});assert.equal(await p.locator('[data-wp-name]').count(),0);
 pass('Phone editor fits at 320 and 390 pixels, cancel discards changes, and unrelated viewers have no edit-name button');
 await p.evaluate(()=>openAccountSheet());await p.locator('#accountDisplayName').fill('Draft Account Name');await p.evaluate(()=>fixture.throwSave=true);
 await p.locator('#saveAccountProfileBtn').click();await p.waitForFunction(()=>!document.getElementById('saveAccountProfileBtn').disabled);assert.match(await p.locator('#accountProfileStatus').innerText(),/Connection interrupted/);
 await p.evaluate(()=>{fixture.throwSave=false;managedLogin={id:'managed'};});const before=await p.evaluate(()=>fixture.accountWrites.length);await p.evaluate(()=>saveAccountProfile());assert.equal(await p.evaluate(()=>fixture.accountWrites.length),before);
 pass('Account save recovers from thrown network errors and managed team logins cannot use personal name saving');
 await p.evaluate(()=>{managedLogin=null;fixture.profile.manager=true;fixture.profile.self=true;fixture.delaySave=150;return WMProfiles.openProfile('profile-own');});
 await p.locator('[data-wp-name]').click();await p.locator('#wpNameOnly').fill('Delayed');await p.locator('#wpNameSave').click();
 await p.evaluate(()=>{session={user:{id:'different-account'}};WMProfiles.reset();});await p.waitForTimeout(250);assert.equal(await p.locator('#wpBody').innerText(),'');
 pass('A delayed response cannot reopen or populate a different account’s profile');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/profile-name.json'),JSON.stringify({passed,engine:'Chromium; actual app with synthetic API fixtures',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
