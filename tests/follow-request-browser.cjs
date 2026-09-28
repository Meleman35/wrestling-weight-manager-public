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
   fixture.followStates={};fixture.sends=[];
   client.rpc=async(name,args)=>{
     if(name!=='wrestling_profiles_request')return {data:{},error:null};
     if(args.p_action==='mine')return {data:[{id:'parent',name:'Example Parent',self:true,manager:true},{id:'child',name:'Example Child',manager:true,athlete:true}],error:null};
     if(args.p_action==='view')return {data:{id:args.p_data.id,name:'Example Coach',manager:false,self:false,details:{},sharing:{},discoverable:true},error:null};
     if(args.p_action==='links'){
       const state=fixture.followStates[args.p_data.id],delay=fixture.linkDelay||0;await new Promise(r=>setTimeout(r,delay));
       if(fixture.failLinks)return {error:{message:'Status unavailable'}};
       return {data:state?[{id:'target',status:state}]:[],error:null};
     }
     if(args.p_action==='follow'){
       fixture.sends.push(args.p_data);if(fixture.sendDelay)await new Promise(r=>setTimeout(r,fixture.sendDelay));
       if(fixture.failSend)return {error:{message:'Parent approval is required to follow or manage My Corner'}};
       fixture.followStates[args.p_data.id]='pending';return {data:{ok:true},error:null};
     }
     return {data:[],error:null};
   };window.WMOperations={open:async()=>{},close:()=>{}};
 });
 const ready=()=>p.waitForFunction(()=>document.getElementById('wpFollowBtn')?.textContent!=='Checking follow status…');
 const open=async()=>{await p.evaluate(()=>WMProfiles.openProfile('target'));await ready();};
 await open();assert.equal(await p.locator('#wpFollowBtn').innerText(),'Request to follow');
 await p.evaluate(()=>fixture.sendDelay=150);await p.locator('#wpFollowBtn').click();assert.equal(await p.locator('#wpFollowBtn').innerText(),'Sending request…');assert(await p.locator('#wpActor').isDisabled());
 await p.waitForFunction(()=>document.getElementById('wpFollowStatus').textContent.includes('waiting for approval'));
 assert.equal(await p.locator('#wpFollowBtn').innerText(),'✓ Request sent');assert(await p.locator('#wpFollowBtn').isDisabled());assert.match(await p.locator('#wpFollowStatus').innerText(),/Example Coach as Example Parent/);
 assert.deepEqual(await p.evaluate(()=>fixture.sends),[{id:'parent',target:'target'}]);
 await p.locator('#wpFollowBox').scrollIntoViewIfNeeded();await p.screenshot({path:path.join(root,'validation/follow-request-phone.png')});
 pass('Sending gives immediate feedback and then an inline confirmation beside a disabled Request sent button');
 await open();assert.equal(await p.locator('#wpFollowBtn').innerText(),'✓ Request sent');
 await p.evaluate(()=>fixture.followStates.parent='approved');await open();assert.equal(await p.locator('#wpFollowBtn').innerText(),'✓ Following');assert(await p.locator('#wpFollowBtn').isHidden());assert(await p.locator('#wpFollowStatus').isHidden());assert(await p.locator('#wpFollowingBadge').isVisible());
 pass('Reopening reads the saved request and changes Pending to Following after approval');
 await p.locator('#wpActor').selectOption('child');await ready();assert.equal(await p.locator('#wpFollowBtn').innerText(),'Request to follow');
 await p.evaluate(()=>fixture.failSend=true);await p.locator('#wpFollowBtn').click();await p.waitForFunction(()=>!document.getElementById('wpFollowBtn').disabled);assert.match(await p.locator('#wpFollowStatus').innerText(),/Parent approval is required/);assert.equal(await p.locator('#wpActor').isDisabled(),false);
 await p.evaluate(()=>{fixture.failSend=false;fixture.failLinks=true;});await p.locator('#wpFollowBtn').click();await p.waitForFunction(()=>document.getElementById('wpFollowStatus').textContent.includes('current status could not refresh'));
 assert.equal(await p.locator('#wpFollowBtn').innerText(),'✓ Request sent');assert(await p.locator('#wpFollowBtn').isDisabled());
 pass('Switching profiles has separate follow state; failures stay next to the button, and a saved request survives a status-refresh error');
 await p.evaluate(()=>{fixture.failLinks=false;fixture.linkDelay=150;fixture.followStates.child='denied';});
 await p.locator('#wpActor').selectOption('parent');await p.locator('#wpActor').selectOption('child');await ready();assert.equal(await p.locator('#wpFollowBtn').innerText(),'Follow unavailable');
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.getElementById('wrestlingProfilesSheet').scrollWidth<=document.getElementById('wrestlingProfilesSheet').clientWidth+1));}
 pass('Rapid actor changes ignore old responses, denied connections remain unavailable, and phone layout fits');
 await p.locator('#wpActor').selectOption('parent');await p.evaluate(()=>{session={user:{id:'different-account'}};WMProfiles.reset();});await p.waitForTimeout(250);assert.equal(await p.locator('#wpBody').innerText(),'');
 pass('Late status reads cannot populate another signed-in account');assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(root,'validation/follow-request.json'),JSON.stringify({checks,engine:'Chromium; actual app with synthetic follow responses',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
