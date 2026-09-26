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
 // Athlete-profile shortcut uses server bout identity and works for an assigned teammate.
 await p.evaluate(async()=>{
  nativeVideoFixture.denied=false;nativeVideoFixture.holdAuthorization=false;nativeVideoFixture.failSave=false;
  WMVideoPilot.reset();WMMatchVideo.reset();localStorage.clear();actualIsStaff=isStaff=false;viewMode='athlete';
  const original=client.rpc.bind(client),athlete='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',bout='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  fixture.videoActions=[];
  client.rpc=async(name,args)=>{if(name!=='video_match_request')return original(name,args);fixture.videoActions.push(args);const action=args.p_action;
   if(action==='athlete')return{data:{bouts:[{id:bout,athlete_id:athlete,athlete_name:'Assigned Athlete',opponent:'Imported Opponent',event_name:'Sample Invitational',bout_number:'101',mat:'3',updated_at:new Date().toISOString()}],recordings:[],can_set_permission:false},error:null};
   if(action==='begin')return{data:{id,team_id:activeTeam.id,season_id:activeSeason.id,revision:1,data:{id,bout_id:bout,athlete_id:athlete,event_id:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',bout_number:'101',red_id:athlete,other_id:null,red_name:'Assigned Athlete',other_name:'Imported Opponent',label:'Sample Invitational',style:'folkstyle',book_type:'competition',flowVersion:1,nfhs:false,periods:[120,120,120],breakSeconds:0,takedown:3,period:0,phase:'period',remainingMs:120000,deadline:null,ledger:[],status:'live'}},error:null};
   return{data:{revision:2,bouts:[]},error:null};};
  closeSheets();openSheet('athleteViewSheet');await WMMatchVideo.profile(athlete);
 });
 await p.getByRole('button',{name:'Score & record match',exact:true}).click();
 await p.waitForFunction(()=>document.getElementById('vpStatus').textContent.includes('Recording privately'));
 const imported=await p.evaluate(()=>nativeVideoFixture.calls.filter(m=>m.command==='start').at(-1).state);
 assert.equal(imported.red_name,'Assigned Athlete');assert.equal(imported.other_name,'Imported Opponent');assert.equal(imported.bout_number,'101');assert.equal(imported.bout_id,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
 assert(await p.locator('#vpGoLive').isDisabled());assert.match(await p.locator('#vpLiveState').innerText(),/not live/);assert(await p.locator('.mv-record-dot').isVisible());
 assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await p.screenshot({path:path.join(root,'validation/athlete-match-recording-phone.png')});
 await p.locator('#vpStop').click();await p.waitForFunction(()=>!WMVideoPilot.active());
 pass('One athlete-profile action starts assigned teammate recording with imported bout/opponent; device recording dot never falsely indicates live');
 // Both everyday recorder roles can reach Match Book and test without coach operations.
 for(const role of ['athlete','manager']){
  await p.evaluate(async role=>{
   closeSheets();WMMatch.close();WMVideoPilot.reset();WMMatchVideo.reset();localStorage.clear();
   actualIsStaff=isStaff=isTeamAdmin=actualIsTeamAdmin=false;actualIsManager=isManager=role==='manager';viewMode=role==='manager'?'staff':'athlete';
   fixture.coachBookCalls=0;const original=client.rpc.bind(client);
   client.rpc=async(name,args)=>{
    if(name==='get_operations'&&args.p_request?.action==='matches'||name==='save_operations'){fixture.coachBookCalls++;return{data:null,error:{message:'Coach operations denied'}};}
    if(name==='video_match_request'&&args.p_action==='assignments')return{data:{bouts:[],test_only:role==='athlete',can_scorebook:true,can_record_test:true,can_manage:false},error:null};
    if(name==='video_match_request'&&args.p_action==='recorder_test'){const id=crypto.randomUUID();return{data:{id,team_id:activeTeam.id,data:{id,video_test:true,book_type:'test',flowVersion:1,nfhs:false,style:'folkstyle',periods:[120,120,120],breakSeconds:0,takedown:3,red_id:null,other_id:null,red_name:'Test Athlete Red',other_name:'Test Athlete Green',label:'Recorder test',period:0,phase:'period',remainingMs:120000,deadline:null,ledger:[],status:'live'}},error:null};}
    return original(name,args);
   };
   applyRoleUI();await WMMatchVideo.sync();
  },role);
  await p.waitForFunction(()=>document.getElementById('lockerMatchBookBtn')&&!document.getElementById('matchBookBtn').classList.contains('hidden-role'));
  if(role==='manager'){
   await p.locator('.nav-btn[data-tab="more"]').click();await p.locator('[data-clipboard-category="practice"]').click();await p.locator('[data-clipboard-tool="matchBookBtn"]').click();
  }else {await p.locator('.nav-btn[data-tab="home"]').click();await p.locator('#lockerMatchBookBtn').click();}
  await p.getByRole('button',{name:'Test scorebook',exact:true}).click();await p.waitForFunction(()=>!document.getElementById('vpPanel').hidden);
  assert(await p.locator('#vpPermission').isVisible());assert.equal(await p.locator('#vpPermission').isChecked(),false);
  await p.locator('#vpPermission').check();await p.locator('#vpPreview').click();await p.waitForFunction(()=>!document.getElementById('vpStart').disabled);await p.locator('#vpStart').click();await p.waitForFunction(()=>WMVideoPilot.active());
  await p.locator('#matchCorners [data-corner="red"][data-award="td"]').click();await p.locator('#vpStop').click();await p.waitForFunction(()=>!WMVideoPilot.active());await p.locator('#matchSave').click();
  assert.match(await p.locator('#matchStatus').innerText(),/Test score saved on this device/);assert.equal(await p.evaluate(()=>fixture.coachBookCalls),0);
  pass(role+' can open Match Book, confirm permission, record and save a test without coach operations');
 }
 await p.evaluate(()=>{WMMatch.close();WMMatchVideo.reset();});assert.equal(await p.locator('#lockerMatchBookBtn').count(),0);assert(await p.locator('#matchBookBtn').evaluate(b=>b.classList.contains('hidden-role')));
 assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(root,'validation/video-pilot-native-browser.json'),JSON.stringify({passed,engine:'Chromium full app with a synthetic native-message fixture. No AVFoundation, Xcode compilation, device storage, native replay or iOS permission behavior verified.'},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
