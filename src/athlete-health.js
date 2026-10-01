/* Private team health records. No localStorage, offline queue or public media URLs. */
(() => {
 const $h=id=>document.getElementById(id),escape=esc;
 const labels={awaiting_trainer:'Awaiting trainer',not_cleared:'Not cleared',modified:'Modified activity',no_contact:'No contact',cleared:'Cleared'};
 const kinds={injury:'Injury',skin:'Skin concern',concussion:'Concussion concern',other:'Other health concern'};
 const sheet=document.createElement('section');sheet.id='athleteHealthSheet';sheet.className='sheet hidden';sheet.setAttribute('aria-modal','true');sheet.setAttribute('role','dialog');sheet.setAttribute('aria-labelledby','healthTitle');
 sheet.innerHTML='<div class="sheet-handle"></div><div class="sheet-head"><div><div class="eyebrow">TEAM TRAINER</div><h2 id="healthTitle">Athlete Health</h2><p id="healthSubtitle" class="muted"></p></div><button id="healthClose" class="icon-close" aria-label="Close Athlete Health">×</button></div><div id="healthStatus" class="fine" role="status"></div><div id="healthBody"></div>';
 document.body.append(sheet);
 let epoch=0,owner='',state=null,selected=null,busy=false,lastCheck=0,checking=false,urls=[];
 const actor=()=>session?.user?.id&&activeTeam?.id&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)')?session.user.id+'/'+activeTeam.id:'';
 const active=g=>g===epoch&&owner&&owner===actor()&&!sheet.classList.contains('hidden')&&navigator.onLine;
 const today=()=>{const d=new Date();return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,10)};
 const date=d=>d?new Date(d+'T12:00:00').toLocaleDateString():'—';
 const note=(s,error=false)=>{$h('healthStatus').textContent=s;$h('healthStatus').classList.toggle('error',error)};
 const release=()=>{urls.forEach(u=>URL.revokeObjectURL(u));urls=[]};
 function reset(){epoch++;owner='';state=null;selected=null;busy=false;release();$h('healthBody').replaceChildren();note('')}
 function close(){reset();show(sheet.id,false);recoverInteractionLayer()}
 $h('healthClose').onclick=()=>closeSheets();
 async function call(action,data={},g=epoch){
  if(!active(g))throw Error('Reconnect and reopen Athlete Health.');
  const team=activeTeam.id,{data:out,error}=await client.rpc('athlete_health_request',{p_action:action,p_data:{...data,team_id:team}});
  if(!active(g))throw Error('The account or team changed.');
  if(error)throw Error(error.message);return out;
 }
 async function save(button,work){
  if(busy)return;busy=true;button.disabled=true;const g=epoch;note('Saving…');
  try{await work(g);if(active(g))note('Saved.');}catch(e){if(active(g))note(e.message,true)}
  finally{if(g===epoch){busy=false;if(button.isConnected)button.disabled=false}}
 }
 const person=id=>state?.athletes.find(a=>a.id===id);
 function readiness(a){
  const pending=(a.cases||[]).filter(c=>c.status!=='cleared'||!c.return_on||c.return_on>today());
  const missing=state.baseline_required&&!a.baseline;
  return {attention:missing||!!pending.length,text:pending.length?(pending[0].return_on>today()?'Return date pending':labels[pending[0].status])+(pending[0].return_on>today()?' · return '+date(pending[0].return_on):''):missing?'Baseline required':(a.baseline?'Baseline recorded':'Baseline optional'),missing};
 }
 const back=()=>'<button type="button" id="healthBack" class="secondary">‹ All athletes</button>';
 function bindBack(){ $h('healthBack').onclick=()=>load().catch(e=>note(e.message,true)); }
 async function load(g=epoch){
  selected=null;release();note('Loading…');const data=await call('dashboard',{},g);if(!active(g))return;
  state=data;lastCheck=Date.now();render();note('');
 }
 async function open(){
  if(!actor()){message('Sign in to your personal account first.',true);return;}
  if(!navigator.onLine){message('Athlete Health needs an internet connection.',true);return;}
  reset();owner=actor();$h('healthSubtitle').textContent=activeTeam.name;openSheet(sheet.id);const g=epoch;
  try{await load(g)}catch(e){if(active(g))note(e.message,true)}
 }
 function render(){
  if(!state)return;
  const trainers=state.trainers.map(t=>escape(t.name)+(t.accepted?'':' · acceptance pending')).join(', ');
  $h('healthBody').innerHTML=`<p class="fine">${trainers?'Trainer: '+trainers:'Your team administrator can assign a Team Trainer in People & Roles.'}</p>
   ${state.assigned_trainer&&!state.trainer?'<div class="health-card"><h3>Accept trainer access</h3><p>Confirm you are an adult authorized by this school or team to handle athlete health information and record decisions within your professional role.</p><label class="toggle-row"><span>I accept this responsibility.</span><input id="healthAcceptCheck" type="checkbox"></label><button id="healthAccept" type="button" disabled>Accept Team Trainer Role</button></div>':''}
   <div class="health-year"><b>School year ${date(state.school_year_start)}–${date(nextYear(state.school_year_start))}</b><span>${state.baseline_required?'Baseline required before participation':'Baseline tracking optional for this team'}</span></div>
   <div class="health-toolbar"><input id="healthSearch" aria-label="Find an athlete" placeholder="Find an athlete"><button type="button" id="healthReload" class="secondary">Refresh</button></div><div id="healthRoster"></div>
   ${state.admin?`<details class="health-card"><summary>School-year settings</summary><label for="healthYearStart">School-year start</label><input id="healthYearStart" type="date" value="${escape(state.school_year_start)}"><label class="toggle-row"><span>Require a baseline before sports</span><input id="healthRequired" type="checkbox" ${state.baseline_required?'checked':''}></label><button type="button" id="healthSaveSettings">Save Settings</button></details>`:''}
   <details class="health-help"><summary>Testing, clearance and privacy</summary><p>Testing happens in Sway or your school’s testing provider. The trainer verifies its completion here. Baseline completion does not clear an injury. Follow the trainer’s current instructions and your school’s required release process.</p><p>Coaches see participation updates and their own submissions. Private notes and photos are available to accepted trainers and the connected family with permission. Health records are available online only.</p><p>For an urgent concern, contact your trainer or emergency services directly. This inbox is not monitored continuously.</p><a href="https://www.swaymedical.com/sports" target="_blank" rel="noopener noreferrer">About Sway testing ↗</a></details>`;
  $h('healthSearch').oninput=renderRoster;$h('healthReload').onclick=()=>load().catch(e=>note(e.message,true));renderRoster();
  if($h('healthAccept')){$h('healthAcceptCheck').onchange=()=>$h('healthAccept').disabled=!$h('healthAcceptCheck').checked;$h('healthAccept').onclick=e=>save(e.currentTarget,async g=>{await call('accept_trainer',{acknowledgement:'trainer-v1'},g);await load(g)})}
  if(state.admin)$h('healthSaveSettings').onclick=e=>save(e.currentTarget,async g=>{await call('settings',{school_year_start:$h('healthYearStart').value,baseline_required:$h('healthRequired').checked},g);await load(g)});
 }
 function nextYear(v){const d=new Date(v+'T12:00:00');d.setFullYear(d.getFullYear()+1);d.setDate(d.getDate()-1);return d.toISOString().slice(0,10)}
 function renderRoster(){
  const q=$h('healthSearch').value.trim().toLowerCase(),rows=state.athletes.filter(a=>a.name.toLowerCase().includes(q));
  $h('healthRoster').innerHTML=rows.length?rows.map(a=>{const r=readiness(a);return `<article class="health-card"><div class="health-person"><b>${escape(a.name)}</b><span class="health-badge ${r.attention?'health-attention':''}">${escape(r.text)}</span></div><p class="fine">${a.baseline?'Sway / provider: '+escape(a.baseline.provider)+' · completed '+date(a.baseline.completed_on):'No verified baseline for this school year.'}</p><div class="health-actions"><button type="button" data-health-athlete="${escape(a.id)}">Open Health Record</button>${state.trainer?`<button type="button" class="secondary" data-health-baseline="${escape(a.id)}">${a.baseline?'Review':'Verify'} Baseline</button>`:''}</div></article>`}).join(''):'<p class="empty-card">No athletes available to this account.</p>';
  sheet.querySelectorAll('[data-health-athlete]').forEach(b=>b.onclick=()=>athlete(b.dataset.healthAthlete));
  sheet.querySelectorAll('[data-health-baseline]').forEach(b=>b.onclick=()=>baseline(b.dataset.healthBaseline));
 }
 function baseline(id){
  const a=person(id);if(!a||!state.trainer)return;selected={athlete_id:id};release();
  $h('healthBody').innerHTML=back()+`<h3>${escape(a.name)} · baseline</h3><p>Verify the completed test in Sway or your school’s provider. This records completion only.</p><label for="healthProvider">Testing provider</label><input id="healthProvider" maxlength="80" value="${escape(a.baseline?.provider||'Sway')}"><label for="healthCompleted">Completed on</label><input id="healthCompleted" type="date" min="${escape(state.school_year_start)}" max="${today()}" value="${escape(a.baseline?.completed_on||today())}"><label class="toggle-row"><span>I verified this athlete’s completed baseline with the testing provider.</span><input id="healthVerified" type="checkbox"></label><button id="healthBaselineSave" type="button" class="wide" disabled>Record Verified Baseline</button>${a.baseline?'<button id="healthBaselineRevoke" type="button" class="wide secondary">Remove Incorrect Verification</button>':''}<p class="fine">Recorded with your name and date. Within this organization, the verified baseline follows the athlete for the same school year.</p>`;
  bindBack();$h('healthVerified').onchange=()=>$h('healthBaselineSave').disabled=!$h('healthVerified').checked;
  $h('healthBaselineSave').onclick=e=>save(e.currentTarget,async g=>{await call('baseline',{athlete_id:id,provider:$h('healthProvider').value,completed_on:$h('healthCompleted').value,confirmed:$h('healthVerified').checked},g);await load(g)});
  if($h('healthBaselineRevoke'))$h('healthBaselineRevoke').onclick=e=>save(e.currentTarget,async g=>{if(!confirm('Remove this baseline verification? The correction remains in the history.'))return;await call('revoke_baseline',{athlete_id:id},g);await load(g)});
 }
 function athlete(id){
  const a=person(id);if(!a)return;selected={athlete_id:id};release();
  $h('healthBody').innerHTML=back()+`<h3>${escape(a.name)}</h3><p class="fine">${a.baseline?'Baseline completed '+date(a.baseline.completed_on)+' · '+escape(a.baseline.provider):'Baseline not verified for this school year.'}</p><div class="health-actions">${a.can_submit?'<button type="button" id="healthNewCase">Report a Concern</button>':'<p>A parent or guardian can submit a concern or approve health updates for athletes age 13–17.</p>'}${state.trainer?'<button type="button" class="secondary" id="healthVerifyBaseline">Verify Baseline</button>':''}</div><div>${a.cases.length?a.cases.map(c=>`<button class="health-case-row" type="button" data-health-case="${escape(c.id)}"><span><b>${escape(kinds[c.category]||'Health record')}</b><small>${escape(c.participation_note||'Awaiting trainer instructions')}</small>${c.review_on?'<small>Review '+date(c.review_on)+'</small>':''}</span><span class="health-badge">${escape(labels[c.status])}</span></button>`).join(''):'<p class="empty-card">No injury or concern records. This is not a medical clearance.</p>'}</div>
   ${a.guardian?`<details class="health-card"><summary>Athlete health-sharing permission</summary><p>For your athlete age 13–17: allow updates to the trainer, visible to connected parents and guardians. Photo sharing is a separate choice. You can withdraw permission here.</p><label class="toggle-row"><span>Allow my athlete to send health updates</span><input type="checkbox" id="healthAllowUpdates" ${a.family_permission?.allow_updates?'checked':''}></label><label class="toggle-row"><span>Allow private health photos/documents</span><input type="checkbox" id="healthAllowPhotos" ${a.family_permission?.allow_photos?'checked':''}></label><button type="button" id="healthPermissionSave">Save Parent Permission</button></details>`:''}`;
  bindBack();if($h('healthNewCase'))$h('healthNewCase').onclick=()=>newCase(id);if($h('healthVerifyBaseline'))$h('healthVerifyBaseline').onclick=()=>baseline(id);
  sheet.querySelectorAll('[data-health-case]').forEach(b=>b.onclick=()=>caseView(b.dataset.healthCase).catch(e=>note(e.message,true)));
  if(a.guardian){$h('healthAllowUpdates').onchange=()=>{if(!$h('healthAllowUpdates').checked)$h('healthAllowPhotos').checked=false};$h('healthAllowPhotos').onchange=()=>{if($h('healthAllowPhotos').checked)$h('healthAllowUpdates').checked=true};$h('healthPermissionSave').onclick=e=>save(e.currentTarget,async g=>{await call('family_permission',{athlete_id:id,allow_updates:$h('healthAllowUpdates').checked,allow_photos:$h('healthAllowPhotos').checked},g);await load(g);athlete(id)})}
 }
 function newCase(id){
  const a=person(id);if(!a?.can_submit)return;const requestId=crypto.randomUUID();selected={athlete_id:id};
  $h('healthBody').innerHTML=back()+`<h3>Report a concern · ${escape(a.name)}</h3><label for="healthCategory">Concern</label><select id="healthCategory">${Object.entries(kinds).map(([k,v])=>`<option value="${k}">${v}</option>`).join('')}</select><label for="healthNoticed">Date noticed</label><input id="healthNoticed" type="date" max="${today()}" value="${today()}"><label for="healthConcern">What should the trainer know?</label><textarea id="healthConcern" maxlength="4000" rows="4" placeholder="Briefly describe the concern or question."></textarea><p class="fine">Private to the trainer, connected family with permission, and you. You can add a photo after saving. Contact the trainer directly for urgent concerns.</p><button type="button" id="healthCreate" class="wide">Send to Team Trainer</button>`;
  bindBack();$h('healthCreate').onclick=e=>save(e.currentTarget,async g=>{const out=await call('new_case',{athlete_id:id,category:$h('healthCategory').value,noticed_on:$h('healthNoticed').value,body:$h('healthConcern').value,request_id:requestId},g);await caseView(out.case_id,g)});
 }
 async function caseView(id,g=epoch){
  note('Loading record…');release();const out=await call('case',{case_id:id},g);if(!active(g))return;
  const c=out.case;selected={case_id:id,athlete_id:c.athlete_id};
  $h('healthBody').innerHTML=back()+`<button type="button" id="healthRecordRefresh" class="secondary">Refresh Updates</button><h3>${escape(out.athlete_name)} · ${escape(kinds[c.category])}</h3><div class="health-card"><b>${escape(labels[c.status])}</b><p>${escape(c.participation_note||'Awaiting trainer instructions.')}</p>${c.return_on?'<p>Return date: '+date(c.return_on)+'</p>':''}${c.review_on?'<p>Next review: '+date(c.review_on)+'</p>':''}</div>
   ${out.trainer?`<details class="health-card"><summary>Record participation decision</summary><label for="healthDecision">Participation</label><select id="healthDecision">${Object.entries(labels).filter(([k])=>k!=='awaiting_trainer').map(([k,v])=>`<option value="${k}" ${k===c.status?'selected':''}>${v}</option>`).join('')}</select><label for="healthRestrictions">Instructions for coaches and family</label><textarea id="healthRestrictions" rows="3" maxlength="2000" placeholder="Permitted activity and restrictions">${escape(c.participation_note)}</textarea><div class="health-grid"><div><label for="healthReviewOn">Next review</label><input type="date" id="healthReviewOn" value="${escape(c.review_on||'')}"></div><div><label for="healthReturnOn">Cleared return date</label><input type="date" id="healthReturnOn" value="${escape(c.return_on||'')}"></div></div><label for="healthClearanceProvider">Provider authorizing clearance</label><input id="healthClearanceProvider" maxlength="120" value="${escape(c.provider_name||'')}"><label for="healthClearanceFile">Written release ${c.category==='concussion'?'(required for concussion clearance)':'(when required)'}</label><select id="healthClearanceFile"><option value="">Select uploaded release</option>${out.files.filter(f=>f.kind==='provider_release').map(f=>`<option value="${f.id}" ${f.id===c.clearance_file_id?'selected':''}>Provider release · ${new Date(f.created_at).toLocaleDateString()}</option>`).join('')}</select><label class="toggle-row"><span>For clearance, I confirm the decision is authorized and the school’s required release process is complete.</span><input type="checkbox" id="healthClearanceConfirm"></label><button id="healthDecisionSave" type="button">Save Trainer Decision</button></details>`:''}
   <h3>Updates</h3><p class="fine">Participation updates are shared with coaches. Private care updates are limited to the trainer, connected family with permission, and the author.</p><div class="health-updates">${out.updates.map(n=>`<article class="health-update"><b>${escape(n.author)}</b><small>${escape(n.visibility==='participation'?'Participation update':'Private care update')} · ${new Date(n.created_at).toLocaleString()}</small><p>${escape(n.body)}</p></article>`).join('')||'<p>No updates visible to this account.</p>'}</div>
   ${out.can_submit?` ${out.trainer?'<label for="healthUpdateVisibility">Who can see this update?</label><select id="healthUpdateVisibility"><option value="care_team">Private · trainer and connected family</option><option value="participation">Shared · coaches and connected family</option></select>':''}<label for="healthUpdateBody">Send a care update</label><textarea id="healthUpdateBody" rows="3" maxlength="4000" placeholder="Question or update for the trainer and family"></textarea><button id="healthSendUpdate" type="button">Send Update</button>`:''}
   <h3>Private photos and releases</h3><div id="healthFiles">${out.files.map(f=>`<button type="button" class="secondary health-file" data-health-file="${f.id}">${f.kind==='concern_photo'?'Concern photo':'Provider release'} · ${new Date(f.created_at).toLocaleDateString()}</button>`).join('')||'<p class="fine">No files visible to this account.</p>'}</div><div id="healthFilePreview"></div>
   ${out.can_upload?'<details class="health-card"><summary>Add a private photo or release</summary><label for="healthFileKind">File purpose</label><select id="healthFileKind"><option value="concern_photo">Skin / injury concern photo</option><option value="provider_release">Written provider release</option></select><label for="healthFileInput">Photo or PDF</label><input type="file" id="healthFileInput" accept="image/jpeg,image/png,image/webp,image/heic,image/heif,application/pdf"><p class="fine">Share only the relevant area or release. Photos are resized and location metadata is removed. Maximum upload 8 MB.</p><button type="button" id="healthUpload">Upload Privately</button></details>':''}`;
  bindBack();note('');$h('healthRecordRefresh').onclick=()=>caseView(id).catch(e=>note(e.message,true));
  if(out.trainer)$h('healthDecisionSave').onclick=e=>save(e.currentTarget,async k=>{await call('participation',{case_id:id,revision:c.revision,status:$h('healthDecision').value,participation_note:$h('healthRestrictions').value,review_on:$h('healthReviewOn').value||null,return_on:$h('healthReturnOn').value||null,provider_name:$h('healthClearanceProvider').value,clearance_file_id:$h('healthClearanceFile').value||null,confirmed:$h('healthClearanceConfirm').checked},k);await caseView(id,k)});
  if(out.can_submit){let requestId=crypto.randomUUID();$h('healthSendUpdate').onclick=e=>save(e.currentTarget,async k=>{await call('update',{case_id:id,body:$h('healthUpdateBody').value,visibility:$h('healthUpdateVisibility')?.value||'care_team',request_id:requestId},k);await caseView(id,k)})}
  if(out.can_upload)$h('healthUpload').onclick=e=>save(e.currentTarget,async k=>{await upload(id,k);await caseView(id,k)});
  sheet.querySelectorAll('[data-health-file]').forEach(b=>b.onclick=()=>viewFile(id,b.dataset.healthFile).catch(e=>note(e.message,true)));
 }
 async function preparedFile(file,kind){
  if(!file)throw Error('Choose a photo or PDF.');if(file.size>30*1024*1024)throw Error('Choose a smaller file.');
  if(file.type==='application/pdf'){
   if(kind!=='provider_release')throw Error('A concern photo must be an image.');
   if(new TextDecoder().decode(await file.slice(0,5).arrayBuffer())!=='%PDF-')throw Error('Choose a valid PDF.');return file;
  }
  if(!file.type.startsWith('image/'))throw Error('Choose a photo or PDF.');
  const url=URL.createObjectURL(file);try{
   const img=new Image();img.src=url;await img.decode();
   const ratio=Math.min(1,1600/Math.max(img.naturalWidth,img.naturalHeight)),canvas=document.createElement('canvas');
   canvas.width=Math.max(1,Math.round(img.naturalWidth*ratio));canvas.height=Math.max(1,Math.round(img.naturalHeight*ratio));
   const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);
   return await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('Unable to prepare this photo. Try a JPEG.')),'image/jpeg',0.88));
  }catch{throw Error('Unable to open this image. Choose a JPEG or PNG photo.')}finally{URL.revokeObjectURL(url)}
 }
 async function upload(id,g){
  const kind=$h('healthFileKind').value,blob=await preparedFile($h('healthFileInput').files[0],kind);
  if(blob.size>8388608)throw Error('Choose a file under 8 MB.');if(!active(g))return;
  const slot=await call('reserve_file',{case_id:id,file_kind:kind,mime_type:blob.type,size_bytes:blob.size},g);
  const {error}=await client.storage.from(slot.bucket).upload(slot.path,blob,{contentType:blob.type,cacheControl:'0',upsert:false});
  if(!active(g))return;if(error)throw Error(error.message);
  await call('complete_file',{case_id:id,file_id:slot.id},g);
 }
 async function viewFile(caseId,id){
  const g=epoch,file=await call('file',{case_id:caseId,file_id:id},g),{data,error}=await client.storage.from(file.bucket).download(file.path);
  if(!active(g))return;if(error)throw Error(error.message);release();
  const url=URL.createObjectURL(data);urls.push(url);const box=$h('healthFilePreview');box.replaceChildren();
  if(file.mime==='image/jpeg'){const img=document.createElement('img');img.src=url;img.alt='Private health photo';img.className='health-preview';box.append(img)}
  const link=document.createElement('a');link.href=url;link.download=file.mime==='application/pdf'?'provider-release.pdf':'private-health-photo.jpg';link.textContent=file.mime==='application/pdf'?'Open / save private release':'Save private photo';box.append(link);
 }
 function sync(){
  const button=$h('athleteHealthBtn'),visible=!!actor()&&(!isManager||staffMembership?.permissions?.staff_role==='team_trainer'||isStaff);if(button&&button.classList.contains('hidden')===visible){show(button.id,visible);window.WMClipboard?.sync()}
  if(owner&&(owner!==actor()||!navigator.onLine||sheet.classList.contains('hidden'))){close()}
 }
 setInterval(sync,500);window.addEventListener('offline',close);document.addEventListener('visibilitychange',()=>{if(document.hidden)close()});
 setInterval(async()=>{
  if(!owner||!state||busy||checking||Date.now()-lastCheck<15000)return;checking=true;const g=epoch;
  try{const next=await call('dashboard',{},g);const capabilities=x=>JSON.stringify([x.trainer,x.coach,x.athletes.map(a=>[a.id,a.guardian,a.can_submit,a.can_upload,a.clinical])]);if(capabilities(next)!==capabilities(state)){close();message('Health access changed. Reopen Athlete Health to check current permissions.',true);}else lastCheck=Date.now();}
  catch(e){if(active(g)){close();message('Health access could not be checked. Reopen when connected.',true)}}finally{checking=false}
 },1000);
 $h('athleteHealthBtn').onclick=open;window.WMAthleteHealth={open,close,readiness};sync();
})();
