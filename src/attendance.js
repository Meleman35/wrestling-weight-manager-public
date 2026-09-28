/* Season attendance reads Schedule records and keeps unknown marks out of percentages. */
window.WMAttendance=(()=>{
 'use strict';const $=id=>document.getElementById(id),E=esc;
 const types={practice:'Practice',dual:'Duals',tournament:'Tournaments',open_mat:'Open Mats',camp:'Camps',travel:'Travel',meeting:'Meetings',weigh_in:'Weigh-ins',wrestle_off:'Wrestle-offs',other:'Other'};
 let generation=0,ctx=null,athlete=null,scope='',busy=false;
 const key=()=>`${session?.user?.id}:${activeTeam?.id}:${activeSeason?.id}:${viewMode}`;
 const sheet=document.createElement('section');sheet.id='attendanceStatsSheet';sheet.className='sheet hidden';sheet.setAttribute('role','dialog');sheet.setAttribute('aria-label','Attendance');sheet.innerHTML='<div class="sheet-head"><h2>Attendance</h2><button type="button" class="icon-close" id="attendanceStatsClose" aria-label="Close attendance">×</button></div><p id="attendanceStatsStatus" role="status"></p><div id="attendanceStatsBody"></div>';document.body.append(sheet);$('attendanceStatsClose').onclick=()=>closeSheets();
 function reset(){generation++;ctx=null;athlete=null;scope='';busy=false;$('attendanceStatsBody').replaceChildren();sheet.classList.add('hidden');}
 const valid=g=>g===generation&&scope===key()&&!managedLogin&&!sheet.classList.contains('hidden');
 function totals(events,settings){
  let attended=0,counted=0,unmarked=0,excused=0,modified=0;
  for(const e of events){
   if(e.status==='present'||e.status==='late'){attended++;counted++;continue;}
   if(e.status==='modified'){modified++;if(settings.modified_counts){attended++;counted++;}continue;}
   if(e.excused){excused++;if(settings.excused_counts)counted++;continue;}
   if(e.status==='absent'){counted++;continue;}
   unmarked++;
  }
  return {attended,counted,unmarked,excused,modified,percent:counted?Math.round(100*attended/counted):null};
 }
 function card(label,events){const t=totals(events,ctx.settings);return `<div class="attendance-stat"><b>${E(label)}</b><strong>${t.percent==null?'—':t.percent+'%'}</strong><small>${t.attended} / ${t.counted} counted · ${t.unmarked} unmarked</small></div>`;}
 function render(){
  const own=ctx.athletes.find(a=>a.athlete_id===athlete),s=ctx.settings;
  $('attendanceStatsBody').innerHTML=`<p class="fine">${E(activeTeam.name)} · ${E(activeSeason.name||'Current season')}</p>${ctx.can_manage?`<label>Athlete<select id="attendanceStatsAthlete"><option value="">Choose an athlete</option>${ctx.athletes.map(a=>`<option value="${E(a.athlete_id)}" ${a.athlete_id===athlete?'selected':''}>${E(a.name)}${a.active?'':' · Standby / Removed'}</option>`).join('')}</select></label><button type="button" class="wide secondary" id="attendanceStatsSchedule">Manage attendance in Schedule</button>`:`<h3>${E(own?.name||'My attendance')}</h3>`}
${athlete?`<div class="attendance-stat-grid">${s.event_types.map(t=>card(types[t]||t,ctx.events.filter(e=>e.event_type===t))).join('')}${card('Overall events',ctx.events)}</div><p class="fine">Completed events marked to count toward season attendance. Present and Late count as attended. Modified ${s.modified_counts?'counts as attended':'is excluded'}. Excused absences ${s.excused_counts?'count as missed':'are excluded'}. Unmarked events are excluded. Group events count only when attendance is recorded.</p><details><summary>Event attendance (${ctx.events.length})</summary>${ctx.events.map(e=>`<div class="attendance-event-row"><b>${E(e.title)}</b><small>${E(fmtDate(e.starts_at))} · ${E(types[e.event_type])}</small><span>${E(e.excused&&!['present','late','modified'].includes(e.status)?'Excused':e.status==='expected'?'Unmarked':e.status[0].toUpperCase()+e.status.slice(1))}</span>${ctx.can_manage?`<button type="button" class="secondary" data-attendance-event="${E(e.id)}">Open event</button>`:''}</div>`).join('')||'<p>No completed events to show yet.</p>'}</details>`:'<p>Select an athlete to see percentages and individual events.</p>'}
${ctx.can_manage?`<details><summary>Team attendance settings</summary><form id="attendanceSettingsForm"><p class="fine">Choose the event types that count for this team.</p>${Object.entries(types).map(([t,label])=>`<label class="toggle-row"><span>${E(label)}</span><input type="checkbox" name="event_type" value="${t}" ${s.event_types.includes(t)?'checked':''}></label>`).join('')}<label class="toggle-row"><span>Count excused absences as missed</span><input id="attendanceExcusedCounts" type="checkbox" ${s.excused_counts?'checked':''}></label><label class="toggle-row"><span>Count Modified as attended</span><input id="attendanceModifiedCounts" type="checkbox" ${s.modified_counts?'checked':''}></label><button type="submit">Save attendance settings</button></form></details>`:''}`.replace(/^\+/gm,'');
  $('attendanceStatsAthlete')?.addEventListener('change',e=>open(e.target.value||null));
  $('attendanceStatsSchedule')?.addEventListener('click',()=>{closeSheets();setTab('schedule');});
  $('attendanceStatsBody').querySelectorAll('[data-attendance-event]').forEach(b=>b.onclick=async()=>{const g=generation;await loadSchedule();if(valid(g))await openEventDetail(b.dataset.attendanceEvent);});
  $('attendanceSettingsForm')?.addEventListener('submit',save);
 }
 async function open(id=null){
  reset();if(!activeSeason||managedLogin)return;athlete=id;scope=key();const g=generation;openSheet(sheet.id);$('attendanceStatsStatus').textContent='Loading attendance…';
  try{const r=await client.rpc('attendance_summary_request',{p_action:'read',p_data:{season_id:activeSeason.id,athlete_id:id,view_as_parent:viewMode==='parent'}});if(!valid(g))return;if(r.error)throw r.error;ctx=r.data;render();$('attendanceStatsStatus').textContent='';}
  catch(e){if(valid(g))$('attendanceStatsStatus').textContent=e.message;}
 }
 async function save(ev){ev.preventDefault();if(busy||!ctx?.can_manage)return;const g=generation;if(!valid(g))return;busy=true;const b=ev.submitter;b.disabled=true;
  try{const types=[...$('attendanceSettingsForm').querySelectorAll('[name=event_type]:checked')].map(x=>x.value);if(!types.length)throw Error('Choose at least one event type.');const r=await client.rpc('attendance_summary_request',{p_action:'settings',p_data:{season_id:activeSeason.id,athlete_id:athlete,view_as_parent:viewMode==='parent',revision:ctx.settings.revision,event_types:types,excused_counts:$('attendanceExcusedCounts').checked,modified_counts:$('attendanceModifiedCounts').checked}});if(!valid(g))return;if(r.error)throw r.error;ctx=r.data;render();$('attendanceStatsStatus').textContent='Team attendance settings saved.';}catch(e){if(valid(g))$('attendanceStatsStatus').textContent=e.message;}finally{if(valid(g)){busy=false;b.disabled=false;}}
 }
 function openHome(){
  if(isStaff&&viewMode!=='parent')return open();
  const athletes=[...new Map([...memberAthletes.map(a=>({id:a.id,name:`${a.first_name} ${a.last_name}`})),...familyAthletes.map(a=>({id:a.athlete_id,name:`${a.first_name} ${a.last_name}`}))].filter(a=>a.id).map(a=>[a.id,a])).values()];
  if(athletes.length===1)return open(athletes[0].id);
  reset();scope=key();openSheet(sheet.id);$('attendanceStatsStatus').textContent=athletes.length?'Choose an athlete.':'No athlete profile is connected to this team yet.';
  $('attendanceStatsBody').innerHTML=athletes.map(a=>`<button type="button" class="wide secondary" data-attendance-child="${E(a.id)}">${E(a.name)}</button>`).join('');
  $('attendanceStatsBody').querySelectorAll('[data-attendance-child]').forEach(b=>b.onclick=()=>open(b.dataset.attendanceChild));
 }
 $('lockerAttendanceTab').onclick=openHome;
 $('teamAttendanceStatsBtn').onclick=()=>open();$('viewAthleteAttendanceBtn').onclick=()=>open(viewAthleteId);$('profileAttendanceBtn').onclick=()=>open(profileAthleteId);
 return {open,reset,totals};
})();
