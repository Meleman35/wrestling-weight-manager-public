const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[];const pass=s=>{passed.push(s);console.log('PASS',s)};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844},hasTouch:true}),p=await ctx.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 let init=fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8');
 init=init.replace('const q={select()',`const q={update(v){F.savedProfile=v;return this;},single:async()=>{if(F.profileError)return {error:{message:'Offline'}};const row={id:F.session.user.id,...F.savedProfile};localStorage.setItem('fixture-server-'+row.id,JSON.stringify(row));return {data:row,error:null};},select()`);
 await ctx.addInitScript({content:init});await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://wm.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady);
 async function setup(role){await p.evaluate(role=>{session=fixture.session={user:{id:role+'-layout'}};managedLogin=null;activeTeam={id:'team-a',name:'Layout Team'};accountProfileData=JSON.parse(localStorage.getItem('fixture-server-'+session.user.id)||'null')||{id:session.user.id,ui_preferences:{}};isStaff=actualIsStaff=role==='coach';isTeamAdmin=actualIsTeamAdmin=false;isManager=false;viewerRole=role==='parent'?'parent_guardian':role==='coach'?'coach':'athlete';viewMode=isStaff?'staff':'member';show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);closeSheets();setTab('home');applyRoleUI();applyUiPreferences();document.querySelector('.locker-room-tabs').scrollLeft=0;},role);}
 const order=()=>p.locator('.locker-room-tabs>[data-layout-key]').evaluateAll(ns=>ns.map(n=>n.dataset.layoutKey));
 for(const role of ['coach','parent','athlete']){
  await setup(role);assert.equal((await order())[0],'board');await p.locator('#lockerArrangeTilesBtn').click();
  await p.locator('[data-layout-move="locker:1:-1"]').click();
  assert.equal(await p.evaluate(()=>document.activeElement.getAttribute('data-layout-move')),'locker:0:1');
  await p.locator('[data-layout-move="locker:3:-1"]').click();await p.locator('[data-layout-visible="locker:trophy"]').uncheck();
  assert(await p.locator('[data-layout-visible="locker:board"]').isDisabled());
  await p.locator('#saveLayoutBtn').click();assert.deepEqual((await order()).slice(0,4),['my_profile','board','find_profile','parent_controls']);assert(await p.locator('[data-layout-key="trophy"]').isHidden());
  const saved=await p.evaluate(()=>fixture.savedProfile.ui_preferences.layout);assert.deepEqual(saved.locker.slice(0,4),['my_profile','board','find_profile','parent_controls']);
 }
 pass('Coach, parent and athlete accounts can reorder every Locker Room shortcut and hide optional tiles; arrow focus follows the moved tile');
 await p.evaluate(()=>localStorage.removeItem('wm_ui_layout_athlete-layout'));await p.reload();await p.waitForFunction(()=>window.wrestlingManagerSignInReady);await setup('athlete');
 assert.deepEqual((await order()).slice(0,4),['my_profile','board','find_profile','parent_controls']);assert(await p.locator('[data-layout-key="trophy"]').isHidden());
 await p.evaluate(()=>{activeTeam={id:'team-b',name:'Other team'};applyRoleUI();applyUiPreferences();});assert.equal((await order())[0],'my_profile');
 await setup('other');assert.equal((await order())[0],'board');assert(await p.locator('[data-layout-key="trophy"]').isVisible());
 pass('Saved account preferences restore without the device layout cache, survive team changes, and stay separate between accounts');
 await setup('athlete');await p.locator('#lockerArrangeTilesBtn').click();await p.locator('[data-layout-move="locker:1:-1"]').click();await p.locator('#layoutEditorSheet > .sheet-returnbar button').click();assert.equal((await order())[0],'my_profile');
 await p.locator('#lockerArrangeTilesBtn').click();await p.locator('[data-layout-move="locker:1:-1"]').click();await p.evaluate(()=>fixture.profileError=true);await p.locator('#saveLayoutBtn').click();assert.equal((await order())[0],'board');assert.match(await p.locator('#message').innerText(),/saved on this device/);
 await p.reload();await p.waitForFunction(()=>window.wrestlingManagerSignInReady);await setup('athlete');assert.equal((await order())[0],'board');
 await p.locator('#lockerArrangeTilesBtn').click();await p.locator('#saveLayoutBtn').click();assert.equal(await p.evaluate(()=>JSON.parse(localStorage.getItem('wm_ui_layout_athlete-layout')).pendingSync),false);
 pass('Cancel preserves the prior layout; offline saves stay on-device and sync when saved online');
 // Real touch events: swipe should scroll normally, while hold + drag edits without opening a tile.
 await setup('other');await p.evaluate(()=>{document.getElementById('lockerMyProfileTab').onclick=()=>{fixture.accidentalOpen=true;};});
 const touch=await ctx.newCDPSession(p),rail=await p.locator('.locker-room-tabs').boundingBox(),y=rail.y+24;
 await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:rail.x+rail.width-20,y}]});
 await touch.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:rail.x+40,y}]});await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await p.waitForTimeout(90);
 assert.equal(await p.evaluate(()=>tileEditing),false);assert(await p.locator('.locker-room-tabs').evaluate(el=>el.scrollLeft)>0);
 await p.locator('.locker-room-tabs').evaluate(el=>{el.scrollLeft=0;});await p.waitForTimeout(80);
 let box=await p.locator('[data-layout-key="board"]').boundingBox();
 await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:box.x+20,y:box.y+22}]});await p.waitForTimeout(580);await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 assert.equal(await p.evaluate(()=>tileEditing),true);assert.match(await p.locator('#tileEditLabel').innerText(),/left or right/);
 await p.locator('.locker-room-tabs').evaluate(el=>{el.scrollLeft=0;});box=await p.locator('[data-layout-key="board"]').boundingBox();let next=await p.locator('#lockerMyProfileTab').boundingBox();
 await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:box.x+25,y:box.y+25}]});await touch.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:Math.min(next.x+40,rail.x+rail.width-30),y:box.y+25}]});await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 assert((await order()).indexOf('board')>0);assert.equal(await p.evaluate(()=>!!fixture.accidentalOpen),false);
 await p.locator('#tileEditCancel').click();assert.equal((await order())[0],'board');
 pass('Normal touch swipes scroll the row; long press and horizontal dragging reorder tiles without opening them; Cancel restores the order');
 // Mouse drag held at the right edge must expose offscreen destinations.
 box=await p.locator('[data-layout-key="board"]').boundingBox();await p.mouse.move(box.x+20,box.y+20);await p.mouse.down();await p.waitForTimeout(580);await p.mouse.up();
 box=await p.locator('[data-layout-key="board"]').boundingBox();const rb=await p.locator('.locker-room-tabs').boundingBox();await p.mouse.move(box.x+25,box.y+25);await p.mouse.down();await p.mouse.move(rb.x+rb.width-8,box.y+25,{steps:6});await p.waitForTimeout(420);await p.mouse.up();
 assert(await p.locator('.locker-room-tabs').evaluate(el=>el.scrollLeft)>30);await p.locator('#tileEditDone').click();assert.equal(await p.evaluate(()=>tileEditing),false);
 pass('Dragging toward the horizontal edge scrolls to offscreen tiles and Done saves the chosen order');
 await p.locator('#lockerArrangeTilesBtn').click();await p.screenshot({path:path.join(root,'validation/locker-layout-phone.png')});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await p.setViewportSize({width:1200,height:900});await p.screenshot({path:path.join(root,'validation/locker-layout-desktop.png')});
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/locker-layout-browser.json'),JSON.stringify({passed,errors},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
