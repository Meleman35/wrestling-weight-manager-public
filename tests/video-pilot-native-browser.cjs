// Bridge contract tests only. This fixture does NOT record native media or verify iOS.
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH||'/tmp/chromium',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[],passed=[];
 p.on('pageerror',e=>errors.push(e.message));const pass=s=>{passed.push(s);console.log('PASS',s);};
 let init=fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8').replace('    F.calls.push',`    if(name==='get_operations'&&args.p_request.action==='matches')return {data:{matches:[],athletes:[],challenges:[]},error:null};
    if(name==='save_operations')return {data:{revision:1},error:null};
    F.calls.push`);
 await ctx.addInitScript({content:init});
 await ctx.addInitScript(()=>{
   const N=window.nativeVideoFixture={calls:[],takes:[],current:null,scope:'',denied:false,permissionDenied:false,failSave:false,holdAuthorization:false,held:[]};
   const emit=(event,value,scope=N.scope)=>window.wrestlingManagerVideoPilotMessage?.({event,value,scope});N.emit=emit;
   window.webkit={messageHandlers:{wmVideoPilot:{postMessage(m){
     N.calls.push(structuredClone(m));
     const reply=(value={},error)=>setTimeout(()=>window.wrestlingManagerVideoPilotMessage?.({requestId:m.requestId,ok:!error,value,error}),0);
     if(m.command==='authorize'){
       const complete=()=>{N.scope=m.userId+':'+m.teamId;reply({allowed:!N.denied,user_id:m.userId,team_id:m.teamId,lease_seconds:7200,athlete_ids:[]});};
       if(N.holdAuthorization)N.held.push(complete);else complete();return;
     }
     if(m.command==='preview'){reply({},N.permissionDenied?'Allow Camera and Microphone for Wrestling Manager in iPhone Settings, then retry.':null);return;}
     if(m.command==='start'){
       N.current={id:crypto.randomUUID(),scope:N.scope,matchId:m.state.id,label:m.state.red_name+' vs '+m.state.other_name,demo:true,createdAt:new Date().toISOString(),status:'recording',events:[],started:performance.now()};
       reply({status:'starting'});setTimeout(()=>emit('recording',{status:'recording'}),10);return;
     }
     if(m.command==='snapshot'&&N.current){N.current.events.push({atMs:performance.now()-N.current.started,state:structuredClone(m.state),label:m.label});return;}
     if(m.command==='stop'){
       if(N.current){const row=N.current;N.current=null;row.status=N.failSave?'failed':'ready';row.reason=N.failSave?'Playback could not be verified.':'';N.takes.push(row);reply({status:'stopping'});setTimeout(()=>emit('saved',{take:row},row.scope),10);}else reply({status:'idle'});return;
     }
     if(m.command==='reset'){N.current=null;return;}
     if(m.command==='list'){reply({takes:N.takes.filter(r=>r.scope===N.scope)});return;}
     if(m.command==='delete'){N.takes=N.takes.filter(r=>r.id!==m.id);reply();return;}
     if(m.command==='recover'){const row=N.takes.find(r=>r.id===m.id);row.status='partial';row.reason='Recovered after an interruption. The ending may be missing.';reply({take:row});return;}
     if(m.command==='play'){reply();return;}
     if(m.requestId)reply();
   }}}};
 });
 await p.route('**/*',r=>r.request().url()==='https://wm.test/'?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 async function setup(){await p.evaluate(()=>{session=fixture.session={access_token:'synthetic-token',user:{id:'11111111-1111-4111-8111-111111111111'}};activeTeam={id:'22222222-2222-4222-8222-222222222222',name:'Synthetic Team'};activeSeason={id:'SEASON-A'};accountProfileData={id:session.user.id,ui_preferences:{}};isStaff=actualIsStaff=isTeamAdmin=actualIsTeamAdmin=true;isManager=false;viewMode='staff';show('authView',false);show('appView',true);show('appLockOverlay',false);applyRoleUI();});}
 await p.goto('https://wm.test/');await setup();
 await p.evaluate(()=>{navigator.mediaDevices.getUserMedia=()=>{throw Error('Native adapter must not use browser camera');};WMVideoCore.DeviceStore.prototype.init=()=>{throw Error('Native adapter must not use browser storage');};});
 await p.evaluate(()=>WMMatch.open());await p.locator('#matchNew').click();await p.locator('#matchBookType').selectOption('test');await p.locator('#matchSetupForm').evaluate(f=>f.requestSubmit());
 await p.waitForFunction(()=>!document.getElementById('vpPanel').hidden);
 assert.equal(await p.locator('#vpPanel').count(),1);assert.match(await p.locator('#vpPanel').innerText(),/iPhone or iPad/);
 await p.locator('#vpPreview').click();assert.match(await p.locator('#vpStatus').innerText(),/Confirm recording permission/);
 assert.equal(await p.evaluate(()=>nativeVideoFixture.calls.filter(m=>m.command==='preview').length),0);
 pass('Native handler selects one adapter; event permission is required before camera access');
 await p.locator('#vpPermission').check();await p.evaluate(()=>nativeVideoFixture.permissionDenied=true);await p.locator('#vpPreview').click();await p.waitForFunction(()=>document.getElementById('vpStatus').textContent.includes('iPhone Settings'));assert(await p.locator('#vpStart').isDisabled());
 await p.evaluate(()=>nativeVideoFixture.permissionDenied=false);pass('Native permission errors are actionable and cannot mark a recording saved');
 await p.locator('#vpPreview').click();await p.waitForFunction(()=>!document.getElementById('vpStart').disabled);await p.locator('#vpStart').click();await p.waitForFunction(()=>document.getElementById('vpStatus').textContent.includes('Recording privately'));
 await p.locator('#matchToggle').click();await p.locator('#matchCorners [data-corner="red"][data-award="td"]').click();await p.locator('#matchToggle').click();await p.locator('#matchUndo').click();
 await p.waitForTimeout(300);
 const snapshots=await p.evaluate(()=>nativeVideoFixture.current.events);
 assert(snapshots.some(e=>e.state.running));assert(snapshots.some(e=>e.state.ledger.some(a=>a.undo_of)));assert(snapshots.some(e=>e.state.ledger.some(a=>a.scoring&&a.points===3)));
 assert(await p.evaluate(()=>nativeVideoFixture.calls.some(m=>m.command==='layout'&&m.visible&&m.width>0&&m.text.includes('Period'))));
 pass('Existing scorer supplies clock, award and correction history; native preview receives bounded geometry and score display');
 await ctx.setOffline(true);await p.locator('#vpStop').click();await p.waitForFunction(()=>document.getElementById('vpStatus').textContent.includes('Saved on this device'));assert(!(await p.evaluate(()=>WMVideoPilot.active())));await ctx.setOffline(false);
 await p.locator('#vpTakes').locator('..').evaluate(d=>d.open=true);await p.locator('#vpTakes [data-action="play"]').click();
 assert(await p.evaluate(()=>nativeVideoFixture.calls.some(m=>m.command==='play')));pass('Existing lease permits an offline stop; replay routes to native without transferring movie bytes to JavaScript');
 await p.locator('#vpPreview').click();await p.waitForFunction(()=>!document.getElementById('vpStart').disabled);await p.locator('#vpStart').click();await p.waitForFunction(()=>document.getElementById('vpStatus').textContent.includes('Recording privately'));await p.evaluate(()=>nativeVideoFixture.failSave=true);await p.locator('#vpStop').click();await p.waitForFunction(()=>document.getElementById('vpStatus').textContent.includes('Playback was not verified'));
 assert.equal(await p.locator('#vpTakes [data-action="recover"]').count(),1);await p.locator('#vpTakes [data-action="recover"]').click();await p.waitForFunction(()=>document.getElementById('vpTakes').textContent.includes('Partial recording'));pass('Unverified save requires recovery; recovered footage is labeled partial');
 await p.evaluate(()=>{activeTeam={id:'33333333-3333-4333-8333-333333333333'};WMVideoPilot.reset();});await p.evaluate(()=>WMMatch.open());await p.waitForTimeout(100);assert.equal(await p.locator('#vpAllTakes [data-action="play"]').count(),0);pass('Team change resets native access and excludes prior-team rows');
 await p.evaluate(()=>{nativeVideoFixture.denied=true;WMVideoPilot.reset();});await p.evaluate(()=>WMMatch.open());await p.waitForTimeout(100);assert(await p.locator('#vpLibrary').isHidden());pass('Server denial keeps native pilot controls closed');
 await p.evaluate(()=>{nativeVideoFixture.denied=false;nativeVideoFixture.holdAuthorization=true;WMVideoPilot.reset();WMMatch.open();});await p.waitForFunction(()=>nativeVideoFixture.held.length>0);
 await p.evaluate(()=>{WMVideoPilot.reset();nativeVideoFixture.held.splice(0).forEach(fn=>fn());});await p.waitForTimeout(100);assert(await p.locator('#vpLibrary').isHidden());pass('An authorization response arriving after reset cannot reopen the pilot');
 assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(root,'validation/video-pilot-native-browser.json'),JSON.stringify({passed,engine:'Chromium full app with a synthetic native-message fixture. No AVFoundation, Xcode compilation, device storage, native replay or iOS permission behavior verified.'},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
