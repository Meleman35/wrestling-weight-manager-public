const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JSDOM_MODULE||'jsdom'),root=path.resolve(__dirname,'..');
(async()=>{
 const dom=new JSDOM(fs.readFileSync(path.join(root,'index.html'),'utf8'),{url:'https://wm.test/',runScripts:'outside-only'}),w=dom.window;
 w.eval(`var session={user:{id:'coach-test'}},activeTeam={id:'TEAM-A'},activeSeason={id:'SEASON-A'},isStaff=true,managedLogin=null;document.getElementById('appLockOverlay').classList.add('hidden');
 var writes=[],notice='',teamRecording=false,policyRevision=0;
 function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
 function recordingAccountAllowed(){return !managedLogin;}function message(s){notice=s;}function closeSheets(){}var WMVideoPilot={openLibrary(){}};
 var client={rpc:async function(name,args){const action=args.p_action;
 if(action==='assignments')return {data:{can_scorebook:true,can_record_test:true,can_manage_recorders:session.user.id==='coach-test',team_recorder:teamRecording,test_only:true,bouts:[]}};
 if(action==='recorder_settings')return {data:{test_only:true,seasons:[{id:'SEASON-A',name:'2026–27',enabled:teamRecording,revision:policyRevision}]}};
 if(action==='recorder_settings_save'){writes.push(args);teamRecording=args.p_data.enabled;policyRevision++;return {data:{saved:true}};}
 throw Error('Unexpected RPC '+action);}};
 var WMOperations={dialog:function(config){window.dialogConfig=config;const form=document.getElementById('opsDialogForm'),box=document.getElementById('opsDialogFields');box.innerHTML=config.fields.map(f=>'<select id="od_'+f.id+'">'+f.options.map(o=>'<option value="'+o[0]+'">'+o[1]+'</option>').join('')+'</select>').join('');for(const f of config.fields)document.getElementById('od_'+f.id).value=f.value;return new Promise(resolve=>{form.onsubmit=e=>{e.preventDefault();resolve(Object.fromEntries(config.fields.map(f=>[f.id,document.getElementById('od_'+f.id).value])));};});}};`);
 w.eval(fs.readFileSync(path.join(root,'src/match-video.js'),'utf8'));
 await w.WMMatchVideo.sync();const button=w.document.getElementById('teamRecorderAccessBtn');assert(button);let task=button.onclick();await new Promise(r=>setImmediate(r));assert.match(w.dialogConfig.description,/camera tests only/);assert.equal(w.document.getElementById('od_season').value,'SEASON-A');w.document.getElementById('od_access').value='team';w.document.getElementById('opsDialogForm').dispatchEvent(new w.Event('submit',{cancelable:true}));await task;
 assert.deepEqual(JSON.parse(JSON.stringify(w.writes[0].p_data)),{season_id:'SEASON-A',revision:0,enabled:true,team_id:'TEAM-A'});
 await w.WMMatchVideo.scorebook();let overlay=w.document.querySelector('.vp-replay');assert(overlay);task=[...overlay.querySelectorAll('button')].find(b=>b.textContent==='Team recording access').onclick();await new Promise(r=>setImmediate(r));assert.equal(w.document.querySelector('.vp-replay'),null);assert.equal(w.document.getElementById('od_access').value,'team');w.document.getElementById('od_access').value='assigned';w.document.getElementById('opsDialogForm').dispatchEvent(new w.Event('submit',{cancelable:true}));await task;assert.equal(w.policyRevision,2);
 w.WMMatchVideo.reset();w.eval("session={user:{id:'athlete-test'}};isStaff=false");await w.WMMatchVideo.sync();assert.equal(w.document.getElementById('teamRecorderAccessBtn'),null);await w.WMMatchVideo.scorebook();overlay=w.document.querySelector('.vp-replay');assert(overlay.textContent.includes('Test scorebook'));assert(!overlay.textContent.includes('Team recording access'));
 console.log('PASS Actual recorder controller: coach-only season toggle, scoped save, overlay dismissal, persisted selection and athlete camera entry. JSDOM; no device/layout claim.');w.close();
})().catch(e=>{console.error(e);process.exit(1)});
