// DOM interaction checks with isolated records; no hosted writes or email sends.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'..'),checks=[];
const dom=new JSDOM('<main id="opsContent"></main>',{url:'https://wm.example.test/',runScripts:'outside-only'});
const w=dom.window,d=w.document;
const positions=[
 {id:'secretary',title:'Secretary',division_name:'Girls program',revision:3,active:true,assignment_enabled:true,assigned_user_id:null,voting_member:true},
 {id:'filled',title:'Treasurer',active:true,assignment_enabled:true,assigned_user_id:'adult-2'},
 {id:'archived',title:'Past position',active:false,assignment_enabled:true},
 {id:'athlete',title:'Female Athlete Rep',active:true,assignment_enabled:false}
];
let admin=true,available=true,writes=[],emailCalls=0,pause=null,failContext=false;
w.session={user:{id:'admin-1'}};w.activeTeam=null;w.managedLogin=false;w.confirm=()=>true;
w.esc=value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
w.EMAIL_CONFIRM_REDIRECT_URL='https://wm.example.test/auth-confirm.html';
w.client={rpc:async(name,{p_request:q})=>{
 if(name==='organization_governance')return {data:{can_manage_structure:admin,positions,directory:[],affiliates:[],linkable_teams:[],linkable_organizations:[]}};
 assert.equal(name,'organization_leadership_invites');
 if(q.action==='context'){
  if(pause)await pause;
  if(failContext)return {error:{message:'Simulated context failure'}};
  if(!admin)return {error:{message:'Organization administrator access required.'}};
  return {data:{positions:available?[positions[0]]:[],members:[],administrators:[],invitations:[]}};
 }
 assert.equal(q.action,'create');writes.push(q);
 return {data:{id:q.id,expires_at:'2026-10-10T12:00:00Z',access:{...positions[0],scope:'Girls program',access_role:q.access_role}}};
},functions:{invoke:async()=>{emailCalls++;throw Error('Email not authorized in test');}}};
for(const file of ['organization-structure.js','organization-invitations.js'])w.eval(fs.readFileSync(path.join(root,'src',file),'utf8'));
const hub=()=>({admin,divisions:[],organizations:[]});
const flush=async()=>{await new Promise(setImmediate);await new Promise(setImmediate);};
const openPositions=()=>w.WMOrgStructure.open({org:'test-org',hub:hub(),kind:'positions'});
const pass=text=>{checks.push(text);console.log('PASS',text);};
(async()=>{
 await openPositions();assert.equal(d.querySelectorAll('[data-gs-invite]').length,1);
 assert.equal(d.querySelector('[data-gs-invite]').dataset.gsInvite,'secretary');
 d.getElementById('gsFilter').value='all';d.getElementById('gsFilter').onchange();assert.equal(d.querySelectorAll('[data-gs-invite]').length,1);
 pass('Only active vacant adult positions offer invitations');
 d.querySelector('[data-gs-invite="secretary"]').click();await flush();
 assert.equal(d.getElementById('oiPosition').value,'secretary');assert.equal(d.getElementById('oiKind').value,'position');
 assert.equal(d.getElementById('oiAccess').value,'');assert.equal(d.getElementById('oiPermissions').checked,false);
 assert.match(d.getElementById('oiAccessSummary').textContent,/Secretary.*Girls program/s);assert.equal(writes.length,0);
 pass('Position entry preselects the saved position and scope without granting access');
 d.getElementById('oiEmail').value='tester@example.test';d.getElementById('oiAdult').checked=true;
 d.getElementById('oiPermissions').checked=true;d.getElementById('oiAccess').value='board';d.getElementById('oiAccess').onchange();
 assert.equal(d.getElementById('oiPermissions').checked,false);d.getElementById('oiPermissions').checked=true;
 await d.getElementById('oiForm').onsubmit({preventDefault(){}});
 assert.equal(writes.length,1);assert.equal(writes[0].position_id,'secretary');assert.equal(writes[0].revision,3);
 assert.equal(writes[0].kind,'position');assert.equal(writes[0].access_role,'board');assert.equal(writes[0].organization_id,'test-org');
 assert.ok(d.getElementById('oiLink'));assert.equal(emailCalls,0);
 pass('Creation uses the selected position revision and explicitly reviewed permissions');
 d.getElementById('oiBackPositions').click();await flush();assert.ok(d.getElementById('gsRows'));
 d.querySelector('[data-gs-invite]').click();await flush();d.getElementById('oiCancel').click();await flush();
 assert.ok(d.getElementById('gsRows'));assert.equal(writes.length,1);
 pass('Back and Cancel return to positions without creating another invitation');
 d.querySelector('[data-gs-edit="secretary"]').click();assert.ok(d.getElementById('gsInvitePosition'));
 d.getElementById('gsTitle').value='Unsaved title';d.getElementById('gsForm').oninput();w.confirm=()=>false;
 d.getElementById('gsInvitePosition').click();assert.ok(d.getElementById('gsForm'));
 w.confirm=()=>true;d.getElementById('gsInvitePosition').click();await flush();
 assert.match(d.getElementById('oiAccessSummary').textContent,/Secretary/);assert.doesNotMatch(d.getElementById('oiAccessSummary').textContent,/Unsaved title/);
 pass('Edit screen protects unsaved edits and invites only to the saved position');
 d.getElementById('oiCancel').click();await flush();available=false;
 d.querySelector('[data-gs-invite]').click();await flush();assert.equal(d.getElementById('oiForm'),null);
 assert.match(d.getElementById('oiStatus').textContent,/no longer available/);assert.equal(writes.length,1);
 pass('A position filled or removed before opening is rejected without a fallback role');
 d.getElementById('oiBackPositions').click();await flush();available=true;failContext=true;
 d.querySelector('[data-gs-invite]').click();await flush();assert.ok(d.getElementById('oiRetry'));
 failContext=false;d.getElementById('oiRetry').click();await flush();assert.equal(d.getElementById('oiPosition').value,'secretary');
 pass('Retry after a loading failure retains the intended position');
 d.getElementById('oiCancel').click();await flush();let resolve;pause=new Promise(r=>resolve=r);
 d.querySelector('[data-gs-invite]').click();w.WMOrgInvites.close();d.getElementById('opsContent').textContent='Different tab';
 resolve();await flush();pause=null;assert.equal(d.getElementById('opsContent').textContent,'Different tab');
 pass('Late invitation responses cannot overwrite a different tab');
 admin=false;await openPositions();assert.equal(d.querySelectorAll('[data-gs-invite]').length,0);
 pass('Read-only members have no position invitation action');
 admin=true;await w.WMOrgInvites.open({org:'test-org',mode:'members',positionId:'secretary'});
 assert.equal(d.getElementById('oiForm'),null);d.getElementById('oiNew').click();assert.equal(d.getElementById('oiKind').value,'member');
 assert.equal(d.getElementById('oiPosition').required,false);assert.match(d.getElementById('oiAccessSummary').textContent,/No board position/);
 assert.equal(emailCalls,0);assert.equal(writes.length,1);
 pass('Ordinary membership remains separate and all transport stays synthetic');
 fs.writeFileSync(path.join(root,'validation/organization-position-invitations.json'),JSON.stringify({engine:'JSDOM; real UI modules; synthetic RPC and email transport',passed:checks.length,tests:checks},null,2)+'\n');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>w.close());
