window.WMScheduleTools=(()=>{
 'use strict';const $=id=>document.getElementById(id),E=esc;let generation=0,pending=null;
 const key=()=>`${session?.user?.id}:${activeTeam?.id}:${activeSeason?.id}`;
 function reset(){generation++;pending=null;}
 async function locations(nameId,addressId){
  const name=$(nameId),address=$(addressId);if(!name||!address)return;
  const old=$('favorites_'+nameId);old?.remove();const box=document.createElement('div');box.id='favorites_'+nameId;box.className='saved-locations';address.after(box);
  const k=key(),g=generation;let rows=[],busy=false;
  const valid=()=>g===generation&&k===key()&&box.isConnected&&isStaff&&!managedLogin;
  function draw(status=''){
   if(!valid())return;
   box.innerHTML=`<label>Saved locations<select aria-label="Saved locations"><option value="">Choose a favorite…</option>${rows.map(r=>`<option value="${E(r.id)}">${E(r.name)}${r.address?' · '+E(r.address):''}</option>`).join('')}</select></label><div class="wp-actions"><button type="button" data-save-location>Save current location</button><button type="button" class="secondary" data-remove-location disabled>Remove favorite</button></div><p class="fine" role="status">${E(status)}</p>`;
   const select=box.querySelector('select'),remove=box.querySelector('[data-remove-location]');select.onchange=()=>{const row=rows.find(r=>r.id===select.value);if(row){name.value=row.name;address.value=row.address;name.dispatchEvent(new Event('change',{bubbles:true}));}remove.disabled=!row;};
   box.querySelector('[data-save-location]').onclick=()=>write('save',{name:name.value.trim(),address:address.value.trim()});
   remove.onclick=()=>{if(select.value&&confirm('Remove this saved location? Existing events keep their location.'))write('remove',{id:select.value});};
  }
  async function write(action,data){if(busy||!valid())return;busy=true;box.querySelectorAll('button,select').forEach(b=>b.disabled=true);try{const r=await client.rpc('saved_locations_request',{p_action:action,p_data:{team_id:activeTeam.id,...data}});if(!valid())return;if(r.error)throw r.error;rows=r.data||[];draw(action==='save'?'Location saved for this team.':'Favorite removed.');}catch(e){if(valid())draw(e.message);}finally{busy=false;}}
  try{const r=await client.rpc('saved_locations_request',{p_action:'list',p_data:{team_id:activeTeam.id}});if(!valid())return;if(r.error)throw r.error;rows=r.data||[];draw();}catch(e){if(valid())draw('Saved locations unavailable. You can still type a location.');}
 }
 function mountCreate(){reset();locations('eventLocation','eventAddress');}
 function mountEditor(record){
  reset();locations('ee_location_name','ee_location_address');const form=$('eventEditForm');
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
 return {mountCreate,mountEditor,handles,save,reset};
})();
