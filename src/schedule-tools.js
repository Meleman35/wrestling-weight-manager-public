window.WMScheduleTools=(()=>{
 'use strict';const $=id=>document.getElementById(id),E=esc;let generation=0,pending=null;const durationModes=new Map();let durationListeners=new AbortController();
 const key=()=>`${session?.user?.id}:${activeTeam?.id}:${activeSeason?.id}`;
 function reset(){generation++;pending=null;durationListeners.abort();durationListeners=new AbortController();durationModes.clear();}
 async function locations(nameId,addressId){
  const name=$(nameId),address=$(addressId);if(!name||!address)return;
  const old=$('favorites_'+nameId);old?.remove();const box=document.createElement('div');box.id='favorites_'+nameId;box.className='saved-locations';(address.closest('label')||address).after(box);
  const k=key(),g=generation;let rows=[],busy=false;
  const recent=[...new Map((scheduleRows||[]).filter(e=>e.team_id===activeTeam.id&&e.location_name).slice().sort((a,b)=>String(b.starts_at).localeCompare(String(a.starts_at))).map(e=>({name:e.location_name,address:e.location_address||''})).map(e=>[e.name+'|'+e.address,e])).values()].slice(0,20);
  const valid=()=>g===generation&&k===key()&&box.isConnected&&isStaff&&!managedLogin;
  function draw(status=''){
   if(!valid())return;
   box.innerHTML=`<label>Saved locations<select aria-label="Saved locations"><option value="">Choose a favorite…</option>${rows.map(r=>`<option value="${E(r.id)}">${E(r.name)}${r.address?' · '+E(r.address):''}</option>`).join('')}</select></label><div class="wp-actions"><button type="button" data-save-location>Save current location</button><button type="button" class="secondary" data-remove-location disabled>Remove favorite</button></div><p class="fine" role="status">${E(status)}</p>`;
   const finder=document.createElement('details');finder.className='location-finder';finder.innerHTML='<summary>Find a saved or recent venue</summary><label>Search venues<input type="search" placeholder="School, wrestling room or city" autocomplete="off"></label><div class="location-results"></div><p class="fine">Searches your team’s saved locations and loaded schedule. You can also type a new location above.</p>';box.prepend(finder);
   const choices=[...new Map([...rows.map(r=>({...r,kind:'Saved'})),...recent.map(r=>({...r,kind:'Recent'}))].map(r=>[r.name+'|'+r.address,r])).values()];
   const search=finder.querySelector('input'),results=finder.querySelector('.location-results');
   function searchVenues(){const query=search.value.trim().toLocaleLowerCase(),matches=choices.filter(r=>(r.name+' '+r.address).toLocaleLowerCase().includes(query)).slice(0,8);results.innerHTML=matches.map((r,i)=>`<button type="button" class="secondary location-result" data-location-result="${i}"><b>${E(r.name)}</b><small>${E(r.address||r.kind)}${r.address?' · '+E(r.kind):''}</small></button>`).join('')||'<p class="fine">No matching saved or recent venues. Enter the venue and address above.</p>';results.querySelectorAll('[data-location-result]').forEach(b=>b.onclick=()=>{const r=matches[Number(b.dataset.locationResult)];name.value=r.name;address.value=r.address;name.dispatchEvent(new Event('change',{bubbles:true}));finder.open=false;});}
   search.oninput=searchVenues;searchVenues();
   const select=box.querySelector('select'),remove=box.querySelector('[data-remove-location]');select.onchange=()=>{const row=rows.find(r=>r.id===select.value);if(row){name.value=row.name;address.value=row.address;name.dispatchEvent(new Event('change',{bubbles:true}));}remove.disabled=!row;};
   box.querySelector('[data-save-location]').onclick=()=>write('save',{name:name.value.trim(),address:address.value.trim()});
   remove.onclick=()=>{if(select.value&&confirm('Remove this saved location? Existing events keep their location.'))write('remove',{id:select.value});};
  }
  async function write(action,data){if(busy||!valid())return;busy=true;box.querySelectorAll('button,select').forEach(b=>b.disabled=true);try{const r=await client.rpc('saved_locations_request',{p_action:action,p_data:{team_id:activeTeam.id,...data}});if(!valid())return;if(r.error)throw r.error;rows=r.data||[];draw(action==='save'?'Location saved for this team.':'Favorite removed.');}catch(e){if(valid())draw(e.message);}finally{busy=false;}}
  try{const r=await client.rpc('saved_locations_request',{p_action:'list',p_data:{team_id:activeTeam.id}});if(!valid())return;if(r.error)throw r.error;rows=r.data||[];draw();}catch(e){if(valid())draw('Saved locations unavailable. You can still type a location.');}
 }
 function duration(startId,endId){
  const start=$(startId),end=$(endId);if(!start||!end)return;
  $('duration_'+startId)?.remove();const box=document.createElement('div');box.id='duration_'+startId;box.className='event-duration';
  box.innerHTML='<label>Duration</label><div class="duration-choices" role="group" aria-label="Event duration">'+[[60,'1 hour'],[90,'1½ hours'],[120,'2 hours'],['custom','Custom']].map(([v,label])=>`<button type="button" class="secondary" data-duration="${v}">${label}</button>`).join('')+'</div><p class="fine">Choose a duration or set a custom end time above.</p>';
  (end.closest('.two-col')||end.parentElement).after(box);
  const minutes=()=>Math.round((new Date(end.value)-new Date(start.value))/60000);
  let mode=[60,90,120].includes(minutes())?String(minutes()):'custom';
  function draw(){durationModes.set(startId,mode);box.querySelectorAll('[data-duration]').forEach(b=>{const active=b.dataset.duration===mode;b.setAttribute('aria-pressed',String(active));b.classList.toggle('selected',active);});}
  function apply(){if(mode==='custom'||!start.value)return;const d=new Date(start.value);if(!Number.isFinite(d.getTime()))return;end.min=start.value;end.value=localDateTimeValue(new Date(d.getTime()+Number(mode)*60000));end.dispatchEvent(new Event('change',{bubbles:true}));}
  box.querySelectorAll('[data-duration]').forEach(b=>b.onclick=()=>{mode=b.dataset.duration;draw();if(mode==='custom'){end.focus();return;}apply();});
  start.addEventListener('change',()=>{end.min=start.value;apply();},{signal:durationListeners.signal});
  end.addEventListener('change',()=>{if(Number(mode)!==minutes())mode=[60,90,120].includes(minutes())?String(minutes()):'custom';draw();},{signal:durationListeners.signal});draw();
 }
 function usesDuration(id){return durationModes.has(id)&&durationModes.get(id)!=='custom';}
 function mountCreate(){reset();locations('eventLocation','eventAddress');duration('eventStart','eventEnd');}
 function mountEditor(record){
  reset();locations('ee_location_name','ee_location_address');duration('ee_starts_at','ee_ends_at');const form=$('eventEditForm');
  const box=document.createElement('section');box.className='practice-repeat-box';box.innerHTML=`<label>Apply changes<select id="ee_scope"><option value="one">This occurrence only</option><option value="following">${record.practice_series_id||record.repeat_batch_id?'This and future events':'Make this event repeat'}</option></select></label><div id="ee_repeatOptions" hidden><label>Repeat<select id="ee_frequency"><option value="weekly">Weekly · selected days</option><option value="daily">Daily</option><option value="monthly">Monthly · same date</option><option value="none">Stop after this occurrence</option></select></label><div id="ee_weekdays" class="wp-actions">${['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map((d,i)=>`<label><input type="checkbox" value="${i+1}"> ${d}</label>`).join('')}</div><label>Repeat through<input id="ee_until" type="date"></label><p class="fine" id="ee_repeatSummary" aria-live="polite"></p><p class="fine">Past events and individually edited occurrences stay intact. Changing repeat rules creates a fixed set of dates; review competition-day conflicts before saving. Future occurrences with saved attendance, RSVPs, videos or other records cannot be replaced in bulk.</p></div>`;form.querySelector('[type=submit]').before(box);
  const local=$('ee_starts_at').value,date=new Date(local),day=date.getDay()||7;box.querySelector(`#ee_weekdays input[value="${day}"]`).checked=true;
  const until=new Date(date);until.setDate(until.getDate()+28);$('ee_until').value=dateKeyLocal(until);
  function refresh(){const on=$('ee_scope').value==='following',mode=$('ee_frequency').value;$('ee_repeatOptions').hidden=!on;$('ee_weekdays').hidden=mode!=='weekly';$('ee_until').parentElement.hidden=mode==='none';$('ee_until').min=$('ee_starts_at').value.slice(0,10);const dates=WMEventRepeat.dates($('ee_starts_at').value.slice(0,10),$('ee_until').value,mode,[...box.querySelectorAll('#ee_weekdays input:checked')].map(x=>Number(x.value)));$('ee_repeatSummary').textContent=mode==='none'?'Keep this occurrence and stop untouched future repeats.':`${dates.length} occurrence${dates.length===1?'':'s'} in this schedule. Times stay in ${Intl.DateTimeFormat().resolvedOptions().timeZone}.`;}
  box.addEventListener('change',refresh);$('ee_starts_at').addEventListener('change',refresh);refresh();
 }
 function handles(){return pending||$('ee_scope')?.value==='following';}
 async function save(record,values){
  const g=generation,k=key();const valid=()=>g===generation&&key()===k&&isStaff&&!managedLogin;
  const form=$('eventEditForm');
  if(!pending){
   const frequency=$('ee_frequency').value,start=$('ee_starts_at').value;
   const shift=original=>{if(!original)return null;const offset=new Date(original)-new Date(record.starts_at);return localDateTimeValue(new Date(new Date(start).getTime()+offset));};
   const repeat={frequency,timezone:Intl.DateTimeFormat().resolvedOptions().timeZone,start_local:start,end_local:$('ee_ends_at').value||null,arrival_local:$('ee_arrival_at').value||null,weigh_in_local:$('ee_weigh_in_at').value||null,pre_local:shift(record.pre_weigh_cutoff_at),post_local:shift(record.post_weigh_start_at),until:$('ee_until').value,weekdays:[...form.querySelectorAll('#ee_weekdays input:checked')].map(x=>Number(x.value))};
   const dates=frequency==='none'?[]:WMEventRepeat.dates(start.slice(0,10),repeat.until,frequency,repeat.weekdays);
   if(frequency!=='none'&&(!dates.length||dates[0]!==start.slice(0,10)))throw Error('Choose valid repeat dates within one year, including the start day.');
   const q={client_id:crypto.randomUUID(),event_id:record.id,expected:record.updated_at,values,repeat};
   const preview=await client.rpc('edit_event_recurrence',{p_action:'preview',p_data:q});if(!valid())return null;if(preview.error)throw preview.error;
   if(preview.data.blocked_count)throw Error('Future occurrences already have saved records. Use “This occurrence only”; no events were changed.');
   if(!confirm(`Keep this event and its records, replace ${preview.data.replace_count} untouched future occurrence(s), and ${frequency==='none'?'stop repeating':'save '+dates.length+' occurrences'}?`))return null;
   pending={...q,fingerprint:preview.data.fingerprint};
  }
  form.querySelectorAll('input,select,textarea,button').forEach(b=>b.disabled=true);
  const r=await client.rpc('edit_event_recurrence',{p_action:'save',p_data:pending});if(!valid())return null;
  if(r.error){
   if(r.error.code==='P0001'||r.error.code?.startsWith('22')){pending=null;form.querySelectorAll('input,select,textarea,button').forEach(b=>b.disabled=false);}
   else form.querySelector('[type=submit]').textContent='Retry same repeat change';
   throw Error(r.error.message+(pending?' Retry to finish the same change without duplicates.':''));
  }
  pending=null;return r.data;
 }
 return {mountCreate,mountEditor,handles,save,reset,usesDuration};
})();
