const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),checks=[];
const pass=s=>{checks.push(s);console.log('PASS',s);};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));await ctx.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://wm.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady===true);
 await p.evaluate(()=>{
   session=fixture.session={user:{id:'owner'},access_token:'synthetic'};managedLogin=null;
   show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
   fixture.follows=[{source:'pending-source',name:'Example Athlete',status:'pending'},{source:'approved-source',name:'Example Parent',status:'approved'}];fixture.reviews=[];
   const profile={id:'own-profile',name:'Example Owner',manager:true,self:true,athlete:false,details:{},sharing:{}};
   client.rpc=async(name,args)=>{
     if(name!=='wrestling_profiles_request')return {data:{},error:null};
     if(args.p_action==='mine')return {data:[profile],error:null};
     if(args.p_action==='view')return {data:profile,error:null};
     if(args.p_action==='requests'){if(fixture.failReload)return {error:{message:'Refresh unavailable'}};return {data:JSON.parse(JSON.stringify(fixture.follows)),error:null};}
     if(args.p_action==='review'){
       fixture.reviews.push(args.p_data);if(fixture.delay)await new Promise(r=>setTimeout(r,fixture.delay));
       if(fixture.failSave)return {error:{message:'Connection interrupted. Try again.'}};
       if(!fixture.noop)fixture.follows.find(r=>r.source===args.p_data.source).status=args.p_data.status;
       return {data:{ok:true},error:null};
     }
     return {data:[],error:null};
   };window.WMOperations={open:async()=>{},close:()=>{}};
 });
 const open=async()=>{await p.evaluate(()=>WMProfiles.openProfile('own-profile'));await p.locator('[data-wp-requests]').click();await p.waitForSelector('[data-wp-request]');};
 await open();const reviewed=p.locator('[data-wp-request="approved-source"]');assert.match(await reviewed.innerText(),/✓ Follow approved/);assert.equal(await reviewed.locator('[data-wp-review="approved"]').count(),0);
 const pending=p.locator('[data-wp-request="pending-source"]');assert.match(await pending.innerText(),/Waiting for your approval/);
 await pending.locator('[data-wp-review="approved"]').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent==='Follow approved.');
 assert.match(await pending.innerText(),/✓ Follow approved/);assert.equal(await pending.locator('[data-wp-review="approved"]').count(),0);assert.equal(await p.locator('#wpBody').getByText('No requests waiting for approval.').count(),1);
 assert.deepEqual(await p.evaluate(()=>fixture.reviews),[{id:'own-profile',source:'pending-source',status:'approved'}]);
 await open();assert.match(await pending.innerText(),/✓ Follow approved/);pass('Approval reloads the saved state, shows confirmation, removes the repeated approve button, and stays approved when reopened');
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.getElementById('wrestlingProfilesSheet').scrollWidth<=document.getElementById('wrestlingProfilesSheet').clientWidth+1));}
 await p.screenshot({path:path.join(root,'validation/follow-approval-phone.png')});
 await p.evaluate(()=>fixture.failSave=true);await pending.locator('[data-wp-review="denied"]').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.includes('Connection interrupted'));
 assert.equal(await pending.locator('[data-wp-review="denied"]').isDisabled(),false);assert.match(await pending.locator('[data-follow-result]').innerText(),/Connection interrupted/);
 await p.evaluate(()=>{fixture.failSave=false;fixture.delay=150;});await pending.locator('[data-wp-review="denied"]').click();assert.equal(await pending.locator('[data-wp-review="blocked"]').isDisabled(),true);
 await p.waitForFunction(()=>document.getElementById('wpStatus').textContent==='Follow declined / removed.');assert.match(await pending.innerText(),/Follow declined/);
 pass('Failed decisions show a local error and allow retry; in-flight decisions disable competing row actions');
 await p.evaluate(()=>{fixture.noop=true;fixture.delay=0;});await pending.locator('[data-wp-review="approved"]').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.startsWith('This request changed'));
 assert.match(await pending.innerText(),/Follow declined/);pass('A successful response without a matching saved decision never displays false approval');
 await p.evaluate(()=>{fixture.noop=false;fixture.failReload=true;});await pending.locator('[data-wp-review="approved"]').click();await p.waitForFunction(()=>document.getElementById('wpStatus').textContent.includes('was saved, but the list could not refresh'));
 await p.evaluate(()=>fixture.failReload=false);await open();assert.match(await pending.innerText(),/✓ Follow approved/);pass('A saved decision followed by refresh failure is reported accurately and recovered by reopening');
 await p.evaluate(()=>fixture.delay=150);await pending.locator('[data-wp-review="blocked"]').click();await p.evaluate(()=>{session={user:{id:'other-account'}};WMProfiles.reset();});await p.waitForTimeout(250);assert.equal(await p.locator('#wpBody').innerText(),'');
 pass('Late responses do not show another account’s follower list');assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(root,'validation/follow-approval.json'),JSON.stringify({checks,engine:'Chromium; actual app with synthetic follower requests',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
