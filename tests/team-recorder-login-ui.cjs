const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),vm=require('vm');
const {JSDOM}=require(process.env.JSDOM_MODULE||'jsdom'),root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'index.html'),'utf8');
(async()=>{
 const dom=new JSDOM(html,{url:'https://wm.test/',runScripts:'outside-only'}),w=dom.window;w.TextEncoder=TextEncoder;
 for(const [i,s] of [...w.document.querySelectorAll('script:not([src])')].entries())if(!s.type||s.type==='text/javascript')new vm.Script(s.textContent,{filename:'inline-'+i});
 function source(name){const m=html.match(new RegExp('^(?:async )?function '+name+'\\([^]*?^}', 'm'));assert(m,name);return m[0];}
 w.eval(`var session={user:{id:'coach'}},activeTeam={id:'team'},activeSeason=null,managedLogin=null,isStaff=true,isTeamAdmin=true,actualIsStaff=true,actualIsTeamAdmin=true;
 var teamLoginEditingId=null,teamLoginOperationId=null,teamLoginAdminData={accounts:[],test_athletes:[]},teamLoginAdminBusy=false,teamLoginAdminVersion=1;
 var teamProfileChoice=null,teamLoginSigningOut=false,teamProfileSelecting=false,staffWeightLoadVersion=0,teamProfileReadyUserId=null;
 var organizationMemberships=[],teamMemberships=[],accountProfileData=null,writes=[],rpcCalls=[],closeCount=0;
 var $=id=>document.getElementById(id);function show(id,on){$(id).classList.toggle('hidden',!on);}function esc(v){return String(v);}function message(){}function closeSheets(){closeCount++;}
 function renderTeamLoginPhoto(){}function renderTeamLoginAccounts(){}function subscribeAccountMemberships(){}function requestSecurityStatus(){}
 function renderSetupRole(){}var WMOnboarding={restore(){}};
 var client={auth:{getSession:async()=>({data:{session}})},from(){throw Error('Recorder must not load general team tables');},rpc:async(name,args)=>{rpcCalls.push([name,args]);if(name==='get_my_team_login')return {data:managedLogin};if(name==='video_match_request'&&args.p_action==='device_context')return {data:{team:{id:'team',name:'Example Team'},seasons:[{id:'season',name:'2026–27'}],available:true,test_only:true}};if(name==='video_match_request'&&args.p_action==='assignments')return {data:{can_scorebook:true,can_record_test:true,test_only:true,bouts:[]}};throw Error('Unexpected RPC '+name);}};
 async function callTeamLogin(action,fields){writes.push({action,fields});return {accounts:[{...fields,id:'login',state:'ready'}],test_athletes:[]};}`);
 for(const name of ['resetTeamLoginEditor','updateTeamLoginKind','readTeamLoginPassword','saveTeamLogin','isTeamRecorderLogin','recordingAccountAllowed','showTeamRecorderHome','refreshAccountView'])w.eval(source(name));
 const $=id=>w.document.getElementById(id);
 w.resetTeamLoginEditor(null,'team_recorder');assert.equal($('teamLoginKind').value,'team_recorder');assert($('teamLoginAthleteRow').classList.contains('hidden'));assert($('teamLoginPermissionFields').classList.contains('hidden'));assert.match($('teamLoginEditorTitle').textContent,/Recorder/);
 $('teamLoginName').value='Mat Team Recorder';$('teamLoginUsername').value='mat-recorder';$('teamLoginPassword').value='synthetic password only';$('teamLoginPasswordConfirm').value='synthetic password only';await w.saveTeamLogin('create');
 assert.equal(w.writes.length,1);const sent=w.writes[0].fields;assert.equal(sent.kind,'team_device');assert.equal(sent.athlete_id,null);assert.equal(sent.permissions.record_matches,true);for(const k of ['weigh_in','attendance','messages'])assert.equal(sent.permissions[k],false);assert.match($('teamLoginLoadStatus').textContent,/Each device keeps its own/);assert.equal($('teamLoginPassword').value,'');
 const account=w.teamLoginAdminData.accounts[0];w.resetTeamLoginEditor(account);assert.equal($('teamLoginKind').value,'team_recorder');assert(!$('teamLoginActiveRow').classList.contains('hidden'));assert(!$('teamLoginResetBtn').classList.contains('hidden'));
 $('teamLoginActive').checked=false;await w.saveTeamLogin('update');assert.equal(w.writes.at(-1).fields.active,false);assert.equal(w.writes.at(-1).fields.permissions.record_matches,true);
 w.resetTeamLoginEditor({...account,active:true});await w.saveTeamLogin('reset_password');$('teamLoginPassword').value='synthetic replacement password';$('teamLoginPasswordConfirm').value='synthetic replacement password';await w.saveTeamLogin('reset_password');assert.equal(w.writes.at(-1).action,'reset_password');assert.equal(w.writes.at(-1).fields.id,'login');
 w.resetTeamLoginEditor();assert.equal($('teamLoginKind').value,'shared');assert(!$('teamLoginAthleteRow').classList.contains('hidden'));assert(!$('teamLoginPermissionFields').classList.contains('hidden'));
 w.eval("session={user:{id:'recorder'}};managedLogin={id:'login',kind:'team_device',team_id:'team',display_name:'Mat Team Recorder',username:'mat-recorder',permissions:{record_matches:true}};");
 await w.refreshAccountView();assert(!$('teamRecorderView').classList.contains('hidden'));assert($('appView').classList.contains('hidden'));assert($('setupView').classList.contains('hidden'));assert.equal($('teamRecorderTeamName').textContent,'Example Team');assert.equal($('teamRecorderScoreBtn').disabled,false);assert.match($('teamRecorderStatus').textContent,/Camera test mode/);assert.equal(w.actualIsTeamAdmin,false);assert.equal(w.actualIsStaff,false);assert.equal(w.rpcCalls.length,2);assert.equal(w.recordingAccountAllowed(),true);
 // The score sheet is outside the hidden main application and remains reachable.
 assert.equal($('matchScoreSheet').closest('#appView'),null);
 w.eval(fs.readFileSync(path.join(root,'src/match-video.js'),'utf8'));await w.WMMatchVideo.scorebook();assert.match(w.document.querySelector('.vp-replay').textContent,/Test scorebook/);assert(!w.document.querySelector('.vp-replay').textContent.includes('Team recording access'));
 w.managedLogin.permissions.record_matches=false;assert.equal(w.recordingAccountAllowed(),false);await assert.rejects(()=>w.WMMatchVideo.scorebook(),/Team Recorder/);w.managedLogin.permissions.record_matches=true;w.activeTeam.id='other';assert.equal(w.recordingAccountAllowed(),false);
 console.log('PASS Actual login editor, creation payload, disable/reset password payloads, normal login preservation, startup RPC isolation, dedicated screen, recording controller and all inline script syntax. JSDOM; no device/layout claim.');w.close();
})().catch(e=>{console.error(e);process.exit(1)});
