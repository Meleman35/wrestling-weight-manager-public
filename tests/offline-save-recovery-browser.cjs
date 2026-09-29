const fs=require('fs'),path=require('path'),http=require('http'),os=require('os'),assert=require('node:assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),checks=[],pass=s=>{checks.push(s);console.log('PASS',s)},fixture=fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8');
(async()=>{
 const server=http.createServer((req,res)=>{const f=req.url.split('?')[0];res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.webmanifest')?'application/manifest+json':f.endsWith('.png')?'image/png':'text/html');if(f==='/vendor/supabase.js')return res.end('/* test adapter */');const file=path.join(root,f==='/'?'index.html':f);try{res.end(fs.readFileSync(file));}catch{res.statusCode=404;res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='http://127.0.0.1:'+server.address().port;
 const profile=fs.mkdtempSync(path.join(os.tmpdir(),'wm-save-recovery-')),launch={executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage'],viewport:{width:390,height:844},hasTouch:true},c=await chromium.launchPersistentContext(profile,launch),errors=[];
 await c.addInitScript({content:fixture});const p=await c.newPage();p.on('pageerror',e=>errors.push(e.message));const wait=async fn=>{const end=Date.now()+15000;while(Date.now()<end){if(await p.evaluate(fn))return;await new Promise(r=>setTimeout(r,75));}throw Error('Async browser condition timed out');};await p.goto(url);await p.waitForFunction(()=>window.wrestlingManagerSignInReady);
 const setup=()=>{
  session=fixture.session={user:{id:'coach'}};managedLogin=null;activeTeam={id:'team',name:'Test Wrestling'};activeSeason={id:'season',name:'2026–27'};show('authView',false);show('appView',true);show('appLockOverlay',false);isStaff=actualIsStaff=isTeamAdmin=true;viewMode='staff';
  const manifest={user_id:'coach',team:activeTeam,season:activeSeason,verified_at:new Date().toISOString(),expires_at:new Date(Date.now()+7*864e5).toISOString()};
  const e={id:'event',team_id:'team',season_id:'season',title:'Practice',starts_at:'2026-10-02T20:00:00Z',ends_at:'2026-10-02T21:30:00Z',updated_at:'2026-09-01T00:00:00Z',attendance_required:true};
  window.ofCalls=[];window.ofReplies={};window.ofSent=[];window.ofLost=false;window.ofConflict=false;
  const original=client.rpc;client.rpc=async(name,args)=>{if(name!=='offline_coach_request')return original(name,args);const a=args.p_action,d=args.p_data;ofCalls.push({a,d});if(a==='manifest')return {data:manifest};if(a==='roster')return {data:[{athlete_id:'active',first_name:'Zoe',last_name:'Able',latest_weight:130,roster_status:'active'},{athlete_id:'inactive',first_name:'Sam',last_name:'Baker',roster_status:'standby'},{athlete_id:'lighter',first_name:'Alex',last_name:'Zed',latest_weight:100,roster_status:'active'}]};if(a==='events')return {data:[e]};if(a==='attendance')return {data:[]};if(a==='threads')return {data:[{thread_id:'thread',title:'Coaches',can_post:true,guardian_mirrored:false}]};if(a==='messages')return {data:[{message_id:'past',sender_name:'Coach',body:'Bring wrestling shoes.',created_at:'2026-09-01T00:00:00Z'}]};if(a==='apply'){
   if(!ofReplies[d.operation_id]){ofSent.push(d);ofReplies[d.operation_id]=ofConflict&&d.kind==='attendance'?{status:'conflict',message:'Changed by another coach',value:{id:'att',event_id:d.event_id,athlete_id:d.athlete_id,status:'absent',updated_at:'2026-09-02T00:00:00Z'}}:{status:'applied',value:d.kind==='message'?'msg-'+d.operation_id:d.kind==='event'?{...e,...d.values,updated_at:'2026-09-02T00:00:00Z'}:{id:'att-'+d.athlete_id,event_id:d.event_id,athlete_id:d.athlete_id,status:d.status,updated_at:'2026-09-02T00:00:00Z'}};}
   if(ofLost){ofLost=false;throw Error('Simulated lost response');}return {data:ofReplies[d.operation_id]};}throw Error('Unknown action');};
 };
 await p.evaluate(setup);await p.evaluate(()=>WMProfilePIN.set('1234'));await p.evaluate(()=>WMOffline.open());await p.locator('#ofPIN').fill('1234');await p.locator('#ofUnlockForm button').click();await p.locator('#ofDownload').click();await wait(async()=>Object.keys((await WMOfflineStore.get('coach')).packs).length===1);await p.waitForFunction(()=>document.querySelector('[data-pack]'));

 await c.setOffline(true);
 await p.locator('[data-pack]').click();
 await p.locator('[data-view="schedule"]').click();
 await p.locator('[data-edit]').click();
 const title=p.locator('#ofEventForm [name="title"]');
 const notes=p.locator('#ofEventForm [name="description"]');
 await title.fill('Keep my revised practice');
 await notes.fill('Bus leaves at 4:15. Bring both uniforms.');
 await p.evaluate(()=>{
  window.originalRecordPut=IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put=function(...args){
   if(this.name==='records')throw new DOMException('Storage full','QuotaExceededError');
   return originalRecordPut.apply(this,args);
  };
 });
 await p.locator('#ofEventForm button').click();
 await p.waitForFunction(()=>document.querySelector('#ofStatus').classList.contains('of-error'));
 assert.equal(await p.evaluate(async()=>(await WMOfflineStore.get('coach')).queue.length),0);
 assert.equal(await title.inputValue(),'Keep my revised practice');
 assert.equal(await notes.inputValue(),'Bus leaves at 4:15. Bring both uniforms.');
 assert.equal(await p.locator('#ofEventForm button').isEnabled(),true);
 pass('Failed IndexedDB commit keeps the unsaved event fields and allows retry without claiming a save');
 await p.evaluate(()=>{IDBObjectStore.prototype.put=originalRecordPut;});
 await p.locator('#ofEventForm button').click();
 await wait(async()=>(await WMOfflineStore.get('coach')).queue.length===1);
 const saved=await p.evaluate(async()=>(await WMOfflineStore.get('coach')).queue[0]);
 assert.equal(saved.request.values.title,'Keep my revised practice');
 assert.equal(saved.request.values.description,'Bus leaves at 4:15. Bring both uniforms.');
 assert.equal(saved.request.expected,'2026-09-01T00:00:00Z');
 assert.equal(await p.evaluate(()=>ofSent.length),0);
 pass('Retry durably queues the original edited values once while offline');
 // A second edit cannot replace the existing queued revision and must retain the new typing.
 await title.fill('Second edit awaiting review');
 await notes.fill('Keep this second attempt visible.');
 await p.locator('#ofEventForm button').click();
 await p.waitForFunction(()=>document.querySelector('#ofStatus').textContent.includes('already has a saved change'));
 assert.equal(await title.inputValue(),'Second edit awaiting review');
 assert.equal(await notes.inputValue(),'Keep this second attempt visible.');
 assert.equal(await p.locator('#ofEventForm button').isEnabled(),true);
 assert.equal(await p.evaluate(async()=>(await WMOfflineStore.get('coach')).queue.length),1);
 assert.equal(await p.evaluate(async()=>(await WMOfflineStore.get('coach')).queue[0].id),saved.id);
 pass('An existing queued edit is preserved while rejected new input stays available for review');
 await p.locator('#ofLock').click();
 assert(await p.locator('#offlineWorkspace').isHidden());
 assert.equal(await p.locator('#ofEventForm').count(),0);
 pass('Lock still clears unsaved event fields from the screen');
 assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(root,'validation/offline-save-recovery-browser.json'),JSON.stringify({checks,errors},null,2));
 await c.close();fs.rmSync(profile,{recursive:true,force:true});await new Promise(r=>server.close(r));
})().catch(e=>{console.error(e);process.exit(1)});
