const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');const init=fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8');
const gov=`
window.gsFixture={delay:0,fail:null,readonly:false,writes:[],seen:{},data:{organization_id:'org-a',can_manage_structure:true,directory:[{id:'adult-a',name:'Example Adult'}],linkable_teams:[{id:'team-a',name:'Example School Girls'}],linkable_organizations:[],positions:[{id:'p1',title:'Chairman',assigned_user_id:null,assigned_name:null,access_role:null,active:true,assignment_enabled:true,revision:1},{id:'p2',title:'Female Athlete Rep',active:true,assignment_enabled:false,revision:1}],affiliates:[{id:'a1',name:'Historical Example Club',affiliate_type:'club',status:'active',membership_review:'unreviewed',voting_review:'unreviewed',voting_eligible:false,revision:2,contact:{}}]}};
window.governanceRpc=async q=>{
 const f=gsFixture;if(f.delay)await new Promise(r=>setTimeout(r,f.delay));
 if(q.action==='context')return {data:JSON.parse(JSON.stringify({...f.data,can_manage_structure:!f.readonly})),error:null};
 if(q.action==='history')return {data:[{revision:1,snapshot:{name:'Historical Example Club',status:'active'},reason:'Pre-0.20.36 baseline',recorded_at:'2026-09-24T18:00:00Z'}],error:null};
 f.writes.push(JSON.parse(JSON.stringify(q)));
 if(f.fail)return {data:null,error:{message:f.fail}};
 if(f.seen[q.request_id])return {data:f.seen[q.request_id],error:null};
 const pos=q.action.includes('position'),rows=pos?f.data.positions:f.data.affiliates;
 let r=rows.find(r=>r.id===q.id);
 if(q.action.startsWith('save_')){if(!r){r={id:'new-'+f.writes.length,active:true,assignment_enabled:true,revision:0};rows.push(r)}Object.assign(r,q,{revision:r.revision+1,assigned_user_id:q.user_id||null,assigned_name:q.user_id?'Example Adult':null,name:q.title});}
 if(q.action.startsWith('archive_')){r.active=false;r.status='archived';r.revision++;}
 if(q.action.startsWith('restore_')){r.active=true;r.status='active';r.revision++;r.membership_review='unreviewed';r.voting_review='unreviewed';}
 const result={saved:true,id:r?.id,revision:r?.revision};f.seen[q.request_id]=result;return {data:result,error:null};
};`;
const coach=`() => {
 fixture.session={user:{id:'coach',email:'coach@example.test'}};session=fixture.session;
 availableTeams=[{id:'team-a',name:'Example School Girls',organization_id:'org-a'},{id:'team-b',name:'Example State Girls',organization_id:'org-b'}];activeTeam=availableTeams[0];activeSeason={id:'season-a'};managedLogin=null;
 organizationMemberships=[{organization_id:'org-a',role:'organization_admin'}];teamMemberships=availableTeams.map(t=>({team_id:t.id,user_id:'coach',role:'head_coach',active:true}));
 organizationHeadingRows=[{id:'org-a',name:'Example School District'},{id:'org-b',name:'Example State Association'}];homeOrganizationId='org-a';homeOrganizationUser='coach';
 isStaff=actualIsStaff=isTeamAdmin=actualIsTeamAdmin=true;isManager=false;canAttendance=true;canWeighIn=true;viewMode='staff';show('authView',false);show('appView',true);applyRoleUI();setTab('more');
}`;
async function main(){
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});let results=[];
 const pass=n=>{results.push(n);console.log('PASS',n)};
 async function page(width){const p=await browser.newPage({viewport:{width,height:1000}});const errors=[];p.on('pageerror',e=>errors.push(e.message));p.on('dialog',d=>d.accept());
  await p.route('**/*',r=>r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:'/* fixture */'}):r.abort());
  await p.evaluate(()=>{for(const kind of ['localStorage','sessionStorage']){const data=new Map();Object.defineProperty(window,kind,{value:{getItem:k=>data.get(String(k))??null,setItem:(k,v)=>data.set(String(k),String(v)),removeItem:k=>data.delete(String(k)),clear:()=>data.clear(),key:i=>[...data.keys()][i]??null,get length(){return data.size}}})}Object.defineProperty(crypto,'randomUUID',{value:()=>Array.from({length:32},()=>Math.floor(Math.random()*16).toString(16)).join('')});});
  await p.evaluate(init);await p.evaluate(gov);await p.setContent(html,{waitUntil:'domcontentloaded'});await p.waitForFunction(()=>typeof WMClipboard!=='undefined');await p.waitForTimeout(150);await p.evaluate('('+coach+')()');await p.waitForSelector('[data-clipboard-category="organization"]',{timeout:5000});return {p,errors};}
 try{
 const {p,errors}=await page(1024);
 assert.equal(await p.locator('[data-clipboard-category="organization"]').count(),1);assert.equal(await p.locator('#organizationHeading').isVisible(),false);
 await p.locator('[data-clipboard-category="settings"]').click();assert.equal(await p.locator('[data-clipboard-tool="organizationHubBtn"]').count(),0);await p.locator('#clipboardCategoryBack').click();pass('Clipboard organization remains separate from Settings');
 await p.locator('[data-clipboard-category="organization"]').click();await p.waitForSelector('[data-ops-home="positions"]');await p.locator('[data-ops-home="positions"]').click();await p.waitForSelector('#gsAdd');
 assert.match(await p.locator('#gsRows').innerText(),/Vacant/);await p.screenshot({path:path.join(root,'validation','positions-tablet.png')});pass('Existing hub opens Positions with vacant posts');
 await p.locator('[data-gs-edit="p2"]').click();assert.equal(await p.locator('#gsPerson').isDisabled(),true);await p.locator('#gsCancel').click();pass('Athlete representative assignment disabled in UI');
 await p.locator('#gsAdd').click();await p.locator('#gsTitle').fill('Secretary');await p.locator('#gsPerson').selectOption('adult-a');await p.locator('#gsAdult').check();await p.evaluate(()=>gsFixture.fail='Simulated offline save');await p.locator('#gsSave').click();await p.waitForFunction(()=>document.getElementById('gsStatus').textContent.includes('Not saved'));
 assert.equal(await p.locator('#gsTitle').inputValue(),'Secretary');assert.equal(await p.locator('#gsSave').isDisabled(),false);pass('Failed save retains form and visibly reports unsaved state');
 await p.evaluate(()=>gsFixture.fail=null);await p.locator('#gsSave').click();await p.waitForSelector('#gsRows');let writes=await p.evaluate(()=>gsFixture.writes);assert.equal(writes[0].request_id,writes[1].request_id);assert.match(await p.locator('#gsRows').innerText(),/Example Adult/);pass('Retry reuses request identifier and reloads server state');
 await p.locator('[data-gs-edit="p1"]').click();await p.locator('#gsTitle').fill('Updated chairman');await p.evaluate(()=>gsFixture.fail='This position changed. Reload before saving.');await p.locator('#gsSave').click();await p.waitForSelector('#gsReloadRecord:not(.hidden)');assert.equal(await p.locator('#gsTitle').inputValue(),'Updated chairman');await p.evaluate(()=>gsFixture.fail=null);await p.locator('#gsReloadRecord').click();await p.waitForSelector('#gsRows');pass('Revision conflict preserves edit and offers explicit reload');
 await p.locator('#gsPresets').click();await p.locator('#gsPreset').selectOption('wawa');assert.equal(await p.locator('#gsPresetList li').count(),19);await p.locator('#gsCancel').click();pass('WAWA template previews 19 titles without applying automatically');
 await p.locator('[data-ops-tab="affiliates"]').click();await p.waitForSelector('#gsRows');assert.match(await p.locator('#gsRows').innerText(),/Membership needs review/);assert.match(await p.locator('#gsRows').innerText(),/Voting: not reviewed/);pass('Historical affiliates show separate membership and eligibility review');
 await p.locator('[data-gs-history="a1"]').click();await p.waitForFunction(()=>document.getElementById('gsHistory').textContent.includes('Revision 1'));await p.locator('#gsBack').click();await p.locator('[data-gs-archive="a1"]').click();await p.locator('#gsSave').click();await p.waitForSelector('#gsFilter');await p.locator('#gsFilter').selectOption('all');assert.match(await p.locator('#gsRows').innerText(),/archived/);await p.locator('[data-gs-archive="a1"]').click();await p.locator('#gsSave').click();await p.waitForSelector('#gsRows');assert.match(await p.locator('#gsRows').innerText(),/Membership needs review/);pass('History, archive and reactivation preserve the affiliate record');
 await p.locator('[data-gs-edit="a1"]').click();assert.equal(await p.locator('#gsTeam option').count(),2);await p.screenshot({path:path.join(root,'validation','affiliate-editor-tablet.png')});await p.locator('#gsCancel').click();
 await p.evaluate(()=>gsFixture.delay=300);await p.locator('[data-ops-tab="positions"]').click();await p.locator('[data-ops-tab="home"]').click();await p.waitForTimeout(400);assert.equal(await p.locator('#gsRows').count(),0);assert.equal(await p.locator('#opsSwitchTeams').isVisible(),true);pass('Late server responses cannot replace another organization tab');
 await p.evaluate(()=>gsFixture.delay=0);await p.locator('#opsSwitchTeams').click();assert.equal(await p.locator('[data-switch-team]').count(),2);await p.locator('[data-switch-team="team-b"]').click();await p.waitForFunction(()=>activeTeam.id==='team-b'&&homeOrganizationId==='org-b');pass('Cross-organization team navigation preserved');
 assert.deepEqual(errors,[]);await p.close();
 const phone=await page(390);const p2=phone.p;await p2.locator('[data-clipboard-category="organization"]').click();await p2.waitForSelector('[data-ops-home="affiliates"]');await p2.locator('[data-ops-home="affiliates"]').click();await p2.waitForSelector('#gsRows');
 assert.equal(await p2.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);await p2.screenshot({path:path.join(root,'validation','affiliates-phone.png')});await p2.locator('#gsAdd').click();assert.equal(await p2.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);await p2.screenshot({path:path.join(root,'validation','affiliate-editor-phone.png')});pass('390px directory and editor have no horizontal overflow');
 await p2.locator('#gsCancel').click();await p2.evaluate(()=>gsFixture.readonly=true);await p2.locator('#gsRefresh').click();await p2.waitForFunction(()=>!document.getElementById('gsAdd'));assert.equal(await p2.locator('[data-gs-edit]').count(),0);pass('Read-only view hides all structure mutations');
 await p2.evaluate(()=>{gsFixture.data.affiliates[0].name='<img src=x onerror=alert(1)>';});await p2.locator('#gsRefresh').click();await p2.waitForFunction(()=>document.getElementById('gsRows').textContent.includes('<img'));assert.equal(await p2.locator('#gsRows img').count(),0);pass('Stored titles and names are escaped');assert.deepEqual(phone.errors,[]);await p2.close();
 fs.writeFileSync(path.join(root,'validation','structure-browser.json'),JSON.stringify({engine:'Isolated Chromium; mocked backend; complete HTML',passed:results.length,tests:results},null,2));
 }finally{await browser.close()}
}
main().catch(e=>{console.error(e);process.exit(1)});
