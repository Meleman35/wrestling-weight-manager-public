/* Team coaching workspace; all reads and saves are authorized by the server. */
(() => {
 const $p=id=>document.getElementById(id),categories={warmup:'Warm-up',technique:'Technique',drills:'Drills',live:'Live wrestling',conditioning:'Conditioning',cooldown:'Cool-down',break:'Break',other:'Other'};
 const sheet=document.createElement('section');sheet.id='practicePlansSheet';sheet.className='sheet hidden';sheet.setAttribute('role','dialog');sheet.setAttribute('aria-modal','true');sheet.setAttribute('aria-labelledby','practicePlansTitle');
 sheet.innerHTML='<div class="sheet-handle"></div><div class="sheet-head"><div><div class="eyebrow">COACH WORKSPACE</div><h2 id="practicePlansTitle">Practice Plans</h2></div><button type="button" class="icon-close" id="ppClose" aria-label="Close practice plans">×</button></div><p id="ppTeam" class="pp-fine"></p><p id="ppStatus" role="status" aria-live="polite"></p><div id="ppBody"></div>';
 document.body.append(sheet);
 let owner='',generation=0,busy=false,draft=null,dirty=false,pending=null,month='',zone='UTC',teamName='',eventInfo=null;
 const actor=()=>session?.user?.id&&activeTeam?.id&&isStaff&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)')?session.user.id+':'+activeTeam.id:'';
 const valid=g=>g===generation&&owner&&actor()===owner&&!sheet.classList.contains('hidden');
 const today=()=>{try{const p=new Intl.DateTimeFormat('en-US',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());return ['year','month','day'].map(k=>p.find(x=>x.type===k).value).join('-')}catch{return new Date().toISOString().slice(0,10)}};
 const status=(s,error=false)=>{$p('ppStatus').textContent=s;$p('ppStatus').classList.toggle('error',error)};
 const total=()=>draft.blocks.reduce((s,b)=>s+(Number(b.minutes)||0),0);
 const clock=m=>{const day=Math.floor(m/1440),hour=Math.floor(m/60)%24;return `${hour%12||12}:${String(m%60).padStart(2,'0')} ${hour<12?'AM':'PM'}${day?' (+1 day)':''}`};
 const dateLabel=d=>new Date(d+'T12:00:00').toLocaleDateString(undefined,{weekday:'short',month:'short',day:'numeric',year:'numeric'});
 function close(clear=false){generation++;busy=false;if(clear){owner='';draft=null;dirty=false;pending=null;eventInfo=null;month=''}$p('ppBody').replaceChildren();$p('ppTeam').textContent='';status('');show(sheet.id,false);recoverInteractionLayer()}
 function sync(){const a=actor();show('practicePlansBtn',!!a);show('eventPracticePlanBtn',!!a&&activeEvent?.event_type==='practice');if(owner&&owner!==a)close(true)}
 async function call(action,data={},g=generation){
  if(!valid(g))throw Error('Reopen practice plans for the current team.');
  if(!navigator.onLine)throw Error('Reconnect to save or load. Your unsaved draft stays here until you close the app or switch accounts or teams.');
  const team=activeTeam.id;let result;
  try{result=await client.rpc('practice_plans_request',{p_action:action,p_data:{team_id:team,...data}})}catch{throw Error('Connection interrupted. Completion is not confirmed; reconnect and try the same save again.')}
  if(!valid(g))throw Error('The account or team changed.');
  if(result.error){if(result.error.code==='42501')close(true);if(result.error.code==='PT402'){draft=null;dirty=false;pending=null;paidGate()}throw Error(result.error.message||'Unable to load practice plans.')}
  if(result.data?.timezone)zone=result.data.timezone;if(result.data?.team_name)teamName=result.data.team_name;
  $p('ppTeam').textContent=`${teamName} · Coaches only · ${zone.replaceAll('_',' ')}`;return result.data;
 }
 async function run(operation){if(busy)return;const g=generation;busy=true;sheet.querySelectorAll('fieldset').forEach(x=>x.disabled=true);status('Working…');
  try{await operation(g)}catch(e){if(valid(g))status(e.message,true)}finally{if(valid(g)){busy=false;sheet.querySelectorAll('fieldset').forEach(x=>x.disabled=false)}}
 }
 async function open(eventId){
  sync();if(!actor()){message('Sign in with a personal coaching account and choose your team.',true);return}
  if(owner&&owner!==actor())close(true);owner=actor();zone=activeTeam.timezone||'UTC';teamName=activeTeam.name||'Team';
  ++generation;busy=false;openSheet(sheet.id);$p('ppBody').replaceChildren();$p('ppTeam').textContent=`${teamName} · Coaches only`;
  if(!month)month=today().slice(0,7);
  await run(async g=>{
   const access=await call('context',{},g);if(!access.covered){draft=null;dirty=false;pending=null;paidGate();status('');return}
   if(eventId){
    if(dirty&&!confirm('Replace your unsaved draft with this practice?')){await list(g);return}
    const out=await call('event',{event_id:eventId},g);eventInfo=out.event;
    if(out.plan){draft=out.plan;draft.start_time=draft.start_time?.slice(0,5)||null;dirty=false;pending=null}
    else makeDraft(out.event);
    editor();status(out.plan?'':'New plan — save when ready.');
   }else await list(g);
  });
 }
 function paidGate(){
  $p('ppBody').innerHTML='<div class="pp-card"><div class="eyebrow">TEAM PRO</div><h3>Daily plans for better practices</h3><p>Build timed blocks, add coaching notes, and reuse a practice with your coaching staff.</p><p class="pp-fine">Practice Plans is a paid team feature. Paid access and the 7-day full-feature trial are awaiting billing setup.</p><button id="ppSample" type="button" class="secondary">Preview a Sample Plan</button></div>';
  $p('ppSample').onclick=()=>{$p('ppBody').innerHTML='<p class="pp-link"><b>Sample preview</b><br>Fictional practice. No team data is loaded or saved.</p><h3>Single-leg attacks &amp; finishes</h3><p class="pp-fine">90 minutes · Technique and live application</p>'+[['0–10 min','Warm-up','Movement, stance and motion'],['10–30 min','Technique','Single-leg entries and two finishes'],['30–50 min','Drills','Partner reps with progressive resistance'],['50–75 min','Live wrestling','Situational goes from a single-leg position'],['75–85 min','Conditioning','Short effort intervals'],['85–90 min','Cool-down','Mobility and recap']].map(([time,title,note])=>`<article class="pp-card"><span class="pp-fine">${time}</span><h3>${title}</h3><p>${note}</p></article>`).join('')+'<button id="ppSampleBack" type="button" class="secondary">‹ Back</button>';$p('ppSampleBack').onclick=paidGate};
 }
 function makeDraft(event){
  eventInfo=event||null;draft={id:crypto.randomUUID(),revision:0,event_id:event?.id||null,plan_date:event?.plan_date||today(),start_time:event?.start_time||null,target_minutes:event?.target_minutes||null,title:event?.title||'Daily practice',focus:'',notes:'',blocks:[]};dirty=true;pending=null;
 }
 function discardOK(){return !dirty||confirm('Discard the unsaved changes to this plan?')}
 async function list(g=generation){
  const out=await call('list',{month},g);
  $p('ppBody').innerHTML=`<fieldset><div class="pp-actions"><button id="ppNew" type="button">New Plan</button>${draft&&dirty?'<button id="ppResume" type="button" class="secondary">Resume Unsaved Draft</button>':''}</div><label for="ppMonth">Practice month</label><input id="ppMonth" type="month" value="${esc(month)}" required><div class="pp-list">${out.plans.length?out.plans.map(p=>`<article class="pp-card"><span class="pp-fine">${esc(dateLabel(p.plan_date))}</span><h3>${esc(p.title)}</h3><p class="pp-fine">${Number(p.total_minutes)} min · ${Number(p.block_count)} blocks${p.event_id?' · Scheduled practice':''}</p><button type="button" class="secondary" data-pp-open="${esc(p.id)}">Open Plan</button></article>`).join(''):'<p class="pp-empty">No plans this month. Start a plan or choose another month to reuse an earlier practice.</p>'}</div></fieldset>`;
  $p('ppNew').onclick=()=>{if(busy||!discardOK())return;makeDraft();editor();status('New plan — save when ready.')};
  if($p('ppResume'))$p('ppResume').onclick=()=>{editor();status('Unsaved draft — reconnect and save to share with coaches.')};
  $p('ppMonth').onchange=e=>{if(!e.target.value)return;month=e.target.value;run(list)};
  sheet.querySelectorAll('[data-pp-open]').forEach(b=>b.onclick=()=>{if(!discardOK())return;run(async g=>{const out=await call('read',{id:b.dataset.ppOpen},g);draft=out.plan;draft.start_time=draft.start_time?.slice(0,5)||null;eventInfo=out.event;dirty=false;pending=null;editor();status('')})});status('');
 }
 function summary(){
  if(!draft||!$p('ppSummary'))return;const minutes=total(),target=Number(draft.target_minutes)||0,diff=minutes-target;
  $p('ppSummary').textContent=`${minutes} min planned${target?` · ${diff===0?'On target':Math.abs(diff)+' min '+(diff>0?'over':'under')+' target'}`:''}`;
  let elapsed=0,start=draft.start_time?draft.start_time.split(':').reduce((h,m)=>Number(h)*60+Number(m)):null;
  draft.blocks.forEach(b=>{const n=Number(b.minutes)||0,el=sheet.querySelector(`[data-pp-time="${b.id}"]`);if(el)el.textContent=start===null?`${elapsed}–${elapsed+n} min`:`${clock(start+elapsed)} – ${clock(start+elapsed+n)}`;elapsed+=n});
  if($p('ppUnsaved'))$p('ppUnsaved').textContent=dirty?'Unsaved changes':'Saved with your team';
 }
 function editor(){
  const d=draft;
  $p('ppBody').innerHTML=`<button id="ppBack" type="button" class="secondary">‹ Plans</button><form id="ppForm"><fieldset><div class="pp-editor-head"><span id="ppUnsaved" class="pp-fine"></span><span id="ppRevision" class="pp-fine">${d.revision?'Revision '+d.revision:'New plan'}</span></div>
   ${d.event_id?`<div class="pp-link"><b>Linked to scheduled practice</b><p class="pp-fine">${esc(eventInfo?.title||d.title)}${eventInfo?.plan_date?' · '+esc(dateLabel(eventInfo.plan_date)):''}. Plan edits do not change the schedule or attendance.</p><button id="ppUnlink" type="button" class="secondary">Unlink</button></div>`:''}
   <label for="ppTitle">Practice title</label><input id="ppTitle" maxlength="160" value="${esc(d.title)}" required>
   <div class="pp-fields"><div><label for="ppDate">Date</label><input id="ppDate" type="date" min="2000-01-01" max="2100-12-31" value="${esc(d.plan_date)}" required></div><div><label for="ppStart">Start time (optional)</label><input id="ppStart" type="time" value="${esc(d.start_time||'')}"></div></div>
   <label for="ppTarget">Target length in minutes (optional)</label><input id="ppTarget" type="number" min="1" max="720" step="1" value="${d.target_minutes||''}" placeholder="e.g. 90">
   <label for="ppFocus">Practice focus</label><textarea id="ppFocus" maxlength="2000" rows="2" placeholder="What should athletes improve today?">${esc(d.focus)}</textarea>
   <div class="pp-section-head"><h3>Practice breakdown</h3><p id="ppSummary" role="status"></p></div><div id="ppBlocks"></div>
   <button id="ppAdd" type="button" class="secondary wide">+ Add Block</button>
   <label for="ppNotes">Coach notes</label><textarea id="ppNotes" maxlength="4000" rows="3" placeholder="Equipment, groups, reminders, or changes for next time">${esc(d.notes)}</textarea>
   <p class="pp-fine">Shared with this team’s coaches and administrators. Save to keep your changes.</p><button id="ppSave" type="submit" class="wide">Save Practice Plan</button>
   <details class="pp-card"><summary>Reuse this practice</summary><label for="ppCopyDate">New practice date</label><input id="ppCopyDate" type="date" min="2000-01-01" max="2100-12-31" value="${today()}"><p class="pp-fine">Copy the blocks and notes into a new plan. The original stays saved.</p><button id="ppCopy" type="button" class="secondary">Copy to New Date</button></details>
   ${d.revision?'<button id="ppDelete" type="button" class="pp-delete secondary">Delete Plan</button>':'<button id="ppDiscard" type="button" class="secondary">Discard Draft</button>'}</fieldset></form>`;
  const keys={ppTitle:'title',ppDate:'plan_date',ppStart:'start_time',ppTarget:'target_minutes',ppFocus:'focus',ppNotes:'notes'};
  Object.entries(keys).forEach(([id,key])=>$p(id).oninput=e=>{d[key]=key==='target_minutes'?(e.target.value===''?null:Number(e.target.value)):key==='start_time'?(e.target.value||null):e.target.value;dirty=true;summary()});
  $p('ppBack').onclick=()=>run(list);
  if($p('ppUnlink'))$p('ppUnlink').onclick=()=>{d.event_id=null;eventInfo=null;dirty=true;editor()};
  $p('ppAdd').onclick=()=>{if(d.blocks.length>=40){status('Use up to 40 blocks in one plan.',true);return}d.blocks.push({id:crypto.randomUUID(),category:'drills',label:'',minutes:10,notes:''});dirty=true;blocks();$p('ppBlocks').lastElementChild.querySelector('[data-key="label"]').focus()};
  $p('ppForm').onsubmit=e=>{e.preventDefault();run(async g=>{
   if(total()>720)throw Error('A plan can include up to 12 hours of blocks.');
   const payload={id:d.id,event_id:d.event_id,revision:d.revision,plan_date:d.plan_date,start_time:d.start_time,target_minutes:d.target_minutes,title:d.title,focus:d.focus,notes:d.notes,blocks:structuredClone(d.blocks)};
   const fingerprint=JSON.stringify(payload);if(!pending||pending.fingerprint!==fingerprint)pending={fingerprint,payload:{...payload,request_id:crypto.randomUUID()}};
   const out=await call('save',pending.payload,g);draft=out.plan;draft.start_time=draft.start_time?.slice(0,5)||null;dirty=false;pending=null;month=draft.plan_date.slice(0,7);editor();status('Practice plan saved with your team.');
  })};
  $p('ppCopy').onclick=()=>{const date=$p('ppCopyDate');if(!date.value||!date.reportValidity())return;
   draft={...structuredClone(d),id:crypto.randomUUID(),revision:0,event_id:null,plan_date:date.value,blocks:d.blocks.map(b=>({...b,id:crypto.randomUUID()}))};eventInfo=null;dirty=true;pending=null;editor();status('New copy — review it and save.');sheet.scrollTop=0;
  };
  if($p('ppDelete'))$p('ppDelete').onclick=()=>{if(!confirm('Delete this practice plan? The scheduled practice and attendance will stay.'))return;run(async g=>{await call('delete',{id:d.id,revision:d.revision},g);draft=null;dirty=false;pending=null;await list(g);status('Practice plan deleted.')})};
  if($p('ppDiscard'))$p('ppDiscard').onclick=()=>{if(!discardOK())return;draft=null;dirty=false;pending=null;run(list)};
  blocks();
 }
 function blocks(){
  $p('ppBlocks').innerHTML=draft.blocks.map((b,i)=>`<section class="pp-block" data-block-id="${b.id}"><div class="pp-section-head"><b>Block ${i+1}</b><span class="pp-fine" data-pp-time="${b.id}"></span></div>
   <label for="ppLabel-${b.id}">Activity</label><input id="ppLabel-${b.id}" data-key="label" maxlength="120" value="${esc(b.label)}" required placeholder="e.g. Single-leg finishes">
   <div class="pp-fields"><div><label for="ppCategory-${b.id}">Type</label><select id="ppCategory-${b.id}" data-key="category">${Object.entries(categories).map(([k,v])=>`<option value="${k}" ${b.category===k?'selected':''}>${v}</option>`).join('')}</select></div><div><label for="ppMinutes-${b.id}">Minutes</label><input id="ppMinutes-${b.id}" data-key="minutes" type="number" min="1" max="240" step="1" value="${b.minutes||''}" required></div></div>
   <label for="ppBlockNotes-${b.id}">Instructions</label><textarea id="ppBlockNotes-${b.id}" data-key="notes" rows="2" maxlength="1500" placeholder="Reps, partners, coaching points">${esc(b.notes)}</textarea>
   <div class="pp-block-actions"><button type="button" class="secondary" data-move="-1" ${i===0?'disabled':''} aria-label="Move block ${i+1} up">↑ Up</button><button type="button" class="secondary" data-move="1" ${i===draft.blocks.length-1?'disabled':''} aria-label="Move block ${i+1} down">↓ Down</button><button type="button" class="secondary" data-remove aria-label="Remove block ${i+1}">Remove</button></div></section>`).join('')||'<p class="pp-empty">Build the day with warm-up, technique, drills, live wrestling, and cool-down blocks.</p>';
  $p('ppBlocks').querySelectorAll('[data-block-id]').forEach(el=>{const id=el.dataset.blockId,b=draft.blocks.find(x=>x.id===id);
   el.querySelectorAll('[data-key]').forEach(input=>input.oninput=()=>{b[input.dataset.key]=input.dataset.key==='minutes'?Number(input.value):input.value;dirty=true;summary()});
   el.querySelectorAll('[data-move]').forEach(button=>button.onclick=()=>{const i=draft.blocks.indexOf(b),j=i+Number(button.dataset.move);[draft.blocks[i],draft.blocks[j]]=[draft.blocks[j],draft.blocks[i]];dirty=true;blocks()});
   el.querySelector('[data-remove]').onclick=()=>{if((b.label||b.notes)&&!confirm('Remove this block from the draft?'))return;draft.blocks=draft.blocks.filter(x=>x!==b);dirty=true;blocks()};
  });$p('ppAdd').disabled=draft.blocks.length>=40;summary();
 }
 $p('practicePlansBtn').onclick=()=>open();$p('eventPracticePlanBtn').onclick=()=>open(activeEvent?.id);$p('ppClose').onclick=()=>closeSheets();
 window.addEventListener('offline',()=>{if(owner&&!sheet.classList.contains('hidden'))status('Offline. Changes are not saved; keep this screen open and reconnect to save.',true)});
 window.WMPracticePlans={open,close,sync};setInterval(sync,250);sync();
})();
