const SUPABASE_URL = 'https://vfocpoyexnjsjpxhhyqr.supabase.co';
const SUPABASE_KEY = 'sb_publishable_aX7mx8Myn8sok3bhPPmphQ_fWN8o38P';
const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let session = null;
let activeTeam = null;
let activeSeason = null;
let activeEvent = null;
let rosterRows = [];
let scheduleRows = [];
let scheduleFilter = 'all';
let selectedEventType = 'practice';

const $ = id => document.getElementById(id);
const show = (id, visible=true) => $(id)?.classList.toggle('hidden', !visible);
const esc = value => String(value ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));

function message(text, bad=false){
  $('message').innerHTML = text ? `<div class="${bad?'error':'notice'}">${esc(text)}</div>` : '';
  if (text) setTimeout(() => { if ($('message').textContent === text) $('message').innerHTML=''; }, 5000);
}

function localDateTimeValue(date){
  const pad=n=>String(n).padStart(2,'0');
  return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
function toIsoOrNull(value){ return value ? new Date(value).toISOString() : null; }
function fmtDate(iso){
  if (!iso) return '—';
  return new Intl.DateTimeFormat(undefined,{weekday:'short',month:'short',day:'numeric'}).format(new Date(iso));
}
function fmtTime(iso){
  if (!iso) return '—';
  return new Intl.DateTimeFormat(undefined,{hour:'numeric',minute:'2-digit'}).format(new Date(iso));
}
function fmtDateTime(iso){ return iso ? `${fmtDate(iso)} · ${fmtTime(iso)}` : '—'; }
function eventLabel(type){
  return ({practice:'Practice',open_mat:'Open Mat',dual:'Dual',tournament:'Tournament',camp:'Camp',travel:'Travel',meeting:'Meeting',weigh_in:'Weigh-In',wrestle_off:'Wrestle-Off',other:'Other'})[type] || type;
}

function setTab(name){
  ['home','schedule','messages','weight','more'].forEach(tab => show(tab+'Tab', tab===name));
  document.querySelectorAll('.nav-btn').forEach(btn => btn.classList.toggle('active', btn.dataset.tab===name));
  if (name==='schedule') loadSchedule();
}

function openSheet(id){
  show('sheetBackdrop', true); show(id, true); document.body.style.overflow='hidden';
}
function closeSheets(){
  ['eventSheet','eventDetailSheet','attendanceSheet','rosterSheet','addAthleteSheet','joinSheet','accountSheet'].forEach(id=>show(id,false));
  show('sheetBackdrop', false); document.body.style.overflow='';
}

async function refresh(){
  const res = await client.auth.getSession();
  session = res.data.session;
  show('authView', !session);
  if (!session){ show('setupView', false); show('appView', false); return; }

  $('accountEmail').textContent = session.user.email || session.user.id;

  const { data: memberships, error: memErr } = await client.from('organization_memberships').select('organization_id,role').limit(20);
  if (memErr){ message(memErr.message,true); return; }
  if (!memberships?.length){ show('setupView', true); show('appView', false); return; }

  show('setupView', false); show('appView', true);
  const orgIds = memberships.map(x=>x.organization_id);
  const { data: teams, error: teamErr } = await client.from('teams').select('*').in('organization_id',orgIds).order('created_at');
  if (teamErr || !teams?.length){ message(teamErr?.message || 'No team found.',true); return; }

  activeTeam = teams[0];
  $('headerTeamName').textContent = activeTeam.name;
  $('homeTeamName').textContent = activeTeam.name;

  const { data: seasons, error: seasonErr } = await client.from('seasons').select('*').eq('team_id',activeTeam.id).eq('active',true).order('created_at',{ascending:false}).limit(1);
  if (seasonErr || !seasons?.length){ message(seasonErr?.message || 'No active season found.',true); return; }
  activeSeason = seasons[0];
  $('homeSeasonName').textContent = `${activeSeason.name} Season`;
  $('accountTeamInfo').textContent = `${activeTeam.name} · ${activeSeason.name}`;

  await Promise.all([loadDashboard(),loadRoster(),loadSchedule()]);
}

async function loadDashboard(){
  if (!activeSeason) return;
  const { data: counts, error } = await client.rpc('team_dashboard_counts',{p_season_id:activeSeason.id});
  if (!error && counts?.[0]){
    const c=counts[0];
    const values={weighed:`${c.weighed_today}/${c.roster_total}`,notWeighed:c.not_weighed_today,eligible:c.newly_eligible,challenges:c.challenge_queue};
    Object.entries(values).forEach(([k,v])=>{ if($(k)) $(k).textContent=v; if($(k+'2')) $(k+'2').textContent=v; });
  }
  renderAttention();
}

async function loadRoster(){
  if (!activeSeason) return;
  const { data, error } = await client.from('roster_dashboard').select('*').eq('season_id',activeSeason.id).order('last_name');
  if (error){ message(error.message,true); return; }
  rosterRows = data || [];
  const html = rosterRows.length ? rosterRows.map(r=>`
    <div class="roster-card">
      <div><b>${esc(r.first_name)} ${esc(r.last_name)}</b><small>${esc(r.roster_status||'unassigned')} · lineup ${esc(r.current_lineup_class ?? '—')} · eligible ${esc(r.eligible_weight_class ?? '—')}</small></div>
      <div class="weight-value">${esc(r.latest_weight ?? '—')}<small> lb</small></div>
    </div>`).join('') : '<div class="empty-card">No athletes yet. Team Join will feed approved athletes into this roster.</div>';
  $('rosterList').innerHTML=html;
}


function openAddAthlete(){
  $('athleteFirstName').value='';
  $('athleteLastName').value='';
  $('athleteEmail').value='';
  $('athletePhone').value='';
  $('athleteRosterStatus').value='unassigned';
  closeSheets();
  openSheet('addAthleteSheet');
}

async function saveAthlete(){
  if(!activeSeason) return;
  const first=$('athleteFirstName').value.trim();
  const last=$('athleteLastName').value.trim();
  if(!first||!last){ message('Add the athlete\'s first and last name.',true); return; }
  $('saveAthleteBtn').disabled=true;
  $('saveAthleteBtn').textContent='Adding…';
  const { error }=await client.rpc('coach_add_athlete_to_roster',{
    p_season_id:activeSeason.id,
    p_first_name:first,
    p_last_name:last,
    p_email:$('athleteEmail').value.trim()||null,
    p_phone:$('athletePhone').value.trim()||null,
    p_roster_status:$('athleteRosterStatus').value
  });
  $('saveAthleteBtn').disabled=false;
  $('saveAthleteBtn').textContent='Add Athlete';
  if(error){ message(error.message,true); return; }
  await loadRoster();
  await loadDashboard();
  closeSheets();
  message(`${first} ${last} added to the roster.`);
  openSheet('rosterSheet');
}

async function loadSchedule(){
  if (!activeTeam) return;
  const { data, error } = await client.from('team_events').select('*').eq('team_id',activeTeam.id).order('starts_at',{ascending:true});
  if (error){ message(error.message,true); return; }
  scheduleRows=data||[];
  renderSchedule(); renderUpcomingHome(); renderAttention();
}

function renderSchedule(){
  const now=Date.now()-24*60*60*1000;
  let list=scheduleRows.filter(e=>new Date(e.starts_at).getTime()>=now);
  if(scheduleFilter!=='all') list=list.filter(e=>e.event_type===scheduleFilter);
  $('scheduleList').innerHTML=list.length?list.map(eventCard).join(''):'<div class="empty-card">No matching events yet.</div>';
  $('scheduleList').querySelectorAll('[data-event-id]').forEach(btn=>btn.onclick=()=>openEventDetail(btn.dataset.eventId));
}
function renderUpcomingHome(){
  const upcoming=scheduleRows.filter(e=>new Date(e.starts_at)>new Date()).slice(0,3);
  $('upcomingHome').innerHTML=upcoming.length?upcoming.map(eventCard).join(''):'<div class="empty-card">No upcoming events yet.</div>';
  $('upcomingHome').querySelectorAll('[data-event-id]').forEach(btn=>btn.onclick=()=>openEventDetail(btn.dataset.eventId));
}
function eventCard(e){
  const d=new Date(e.starts_at); const day=d.getDate(); const mon=d.toLocaleString(undefined,{month:'short'}).toUpperCase();
  const optional=!e.counts_toward_season_attendance;
  return `<button class="event-card" data-event-id="${e.id}">
    <div class="event-date"><small>${mon}</small><b>${day}</b></div>
    <div class="event-info"><b>${esc(e.title)}</b><small>${eventLabel(e.event_type)} · ${fmtTime(e.starts_at)}${e.location_name?' · '+esc(e.location_name):''}</small></div>
    <div class="event-side"><span>${optional?'OPTIONAL':'SEASON'}</span><small>›</small></div>
  </button>`;
}

function renderAttention(){
  const items=[];
  const upcoming=scheduleRows.filter(e=>new Date(e.starts_at)>new Date()).slice(0,7);
  if(upcoming.length) items.push({title:`${upcoming.length} upcoming event${upcoming.length===1?'':'s'}`,sub:'Review schedule and RSVP settings.'});
  if(!rosterRows.length) items.push({title:'Roster is empty',sub:'Generate a Team Join code when you are ready to add athletes.'});
  $('attentionCount').textContent=items.length;
  $('attentionList').innerHTML=items.length?items.map(x=>`<div class="roster-card"><div><b>${esc(x.title)}</b><small>${esc(x.sub)}</small></div><div>›</div></div>`).join(''):'<div class="empty-card">Nothing needs attention right now.</div>';
}

function prepareEventForm(){
  selectedEventType='practice';
  document.querySelectorAll('.type-btn').forEach(b=>b.classList.toggle('active',b.dataset.type==='practice'));
  $('eventTitle').value='Girls Practice'; $('eventLocation').value=''; $('eventAddress').value=''; $('eventDescription').value='';
  const start=new Date(); start.setMinutes(Math.ceil(start.getMinutes()/15)*15,0,0); start.setHours(start.getHours()+1);
  const end=new Date(start.getTime()+2*60*60*1000);
  $('eventStart').value=localDateTimeValue(start); $('eventEnd').value=localDateTimeValue(end); $('eventArrival').value=''; $('eventWeighIn').value='';
  $('rsvpEnabled').checked=true; $('attendanceRequired').checked=true; $('countsSeason').checked=true; $('checkoutEnabled').checked=false;
  openSheet('eventSheet');
}

function applyEventTypeDefaults(type){
  selectedEventType=type;
  document.querySelectorAll('.type-btn').forEach(b=>b.classList.toggle('active',b.dataset.type===type));
  const titleDefaults={practice:'Girls Practice',open_mat:'Open Mat',dual:'Dual',tournament:'Tournament',camp:'Camp',travel:'Team Travel',weigh_in:'Weigh-In',wrestle_off:'Wrestle-Off',other:''};
  if(!$('eventTitle').value || Object.values(titleDefaults).includes($('eventTitle').value)) $('eventTitle').value=titleDefaults[type]||'';
  $('countsSeason').checked=!['open_mat','camp'].includes(type);
  $('checkoutEnabled').checked=['dual','tournament','camp','travel'].includes(type);
  $('attendanceRequired').checked=!['travel'].includes(type);
}

async function saveEvent(){
  if(!activeTeam||!activeSeason) return;
  const title=$('eventTitle').value.trim(); const start=$('eventStart').value;
  if(!title||!start){ message('Add an event title and start time.',true); return; }
  $('saveEventBtn').disabled=true; $('saveEventBtn').textContent='Creating…';
  const payload={
    team_id:activeTeam.id,season_id:activeSeason.id,event_type:selectedEventType,title,
    description:$('eventDescription').value.trim()||null,starts_at:toIsoOrNull(start),ends_at:toIsoOrNull($('eventEnd').value),arrival_at:toIsoOrNull($('eventArrival').value),weigh_in_at:toIsoOrNull($('eventWeighIn').value),
    location_name:$('eventLocation').value.trim()||null,location_address:$('eventAddress').value.trim()||null,
    attendance_required:$('attendanceRequired').checked,rsvp_enabled:$('rsvpEnabled').checked,checkout_enabled:$('checkoutEnabled').checked,
    counts_toward_season_attendance:$('countsSeason').checked,created_by:session.user.id
  };
  const { error }=await client.from('team_events').insert(payload);
  $('saveEventBtn').disabled=false; $('saveEventBtn').textContent='Create Event';
  if(error){ message(error.message,true); return; }
  closeSheets(); message(`${eventLabel(selectedEventType)} created.`); await loadSchedule();
}

async function openEventDetail(id){
  activeEvent=scheduleRows.find(e=>e.id===id); if(!activeEvent) return;
  $('detailType').textContent=eventLabel(activeEvent.event_type).toUpperCase(); $('detailTitle').textContent=activeEvent.title;
  $('detailMeta').innerHTML=`
    <div class="meta-row"><span>🗓️</span><div><b>${fmtDate(activeEvent.starts_at)}</b><small>${fmtTime(activeEvent.starts_at)}${activeEvent.ends_at?' – '+fmtTime(activeEvent.ends_at):''}</small></div></div>
    ${activeEvent.arrival_at?`<div class="meta-row"><span>⏱️</span><div><b>Meet / arrival</b><small>${fmtDateTime(activeEvent.arrival_at)}</small></div></div>`:''}
    ${activeEvent.weigh_in_at?`<div class="meta-row"><span>⚖️</span><div><b>Weigh-in</b><small>${fmtDateTime(activeEvent.weigh_in_at)}</small></div></div>`:''}
    ${(activeEvent.location_name||activeEvent.location_address)?`<div class="meta-row"><span>📍</span><div><b>${esc(activeEvent.location_name||'Location')}</b><small>${esc(activeEvent.location_address||'')}</small></div></div>`:''}
    <div class="meta-row"><span>${activeEvent.counts_toward_season_attendance?'✓':'○'}</span><div><b>${activeEvent.counts_toward_season_attendance?'Counts toward season attendance':'Optional / does not affect season attendance'}</b><small>${activeEvent.rsvp_enabled?'RSVP enabled':'RSVP disabled'} · ${activeEvent.attendance_required?'Attendance tracked':'Attendance not required'}</small></div></div>
    ${activeEvent.description?`<div class="meta-row"><span>📝</span><div><b>Notes</b><small>${esc(activeEvent.description)}</small></div></div>`:''}`;
  $('attendanceBtn').classList.toggle('hidden',!activeEvent.attendance_required);
  await loadEventParticipants(activeEvent.id);
  openSheet('eventDetailSheet');
}

async function loadEventParticipants(eventId){
  if(!rosterRows.length){ $('rsvpList').innerHTML='<div class="empty-card">No athletes on the active roster yet.</div>'; $('rsvpSummary').textContent='No roster'; return; }
  const { data:rsvps }=await client.from('event_rsvps').select('*').eq('event_id',eventId);
  const map=new Map((rsvps||[]).map(r=>[r.athlete_id,r]));
  const counts={going:0,maybe:0,not_going:0}; (rsvps||[]).forEach(r=>counts[r.response]++);
  $('rsvpSummary').textContent=`${counts.going} going · ${counts.maybe} maybe · ${counts.not_going} not going`;
  $('rsvpList').innerHTML=rosterRows.map(a=>{const r=map.get(a.athlete_id);return `<div class="roster-card"><div><b>${esc(a.first_name)} ${esc(a.last_name)}</b><small>${r?esc(r.response.replace('_',' ')):'No response'}</small></div><div>${r?.response==='going'?'✓':r?.response==='not_going'?'×':'—'}</div></div>`}).join('');
}

async function openAttendance(){
  if(!activeEvent) return;
  $('attendanceEventName').textContent=activeEvent.title;
  $('attendanceInfo').textContent=activeEvent.counts_toward_season_attendance
    ? 'This event counts toward season attendance.'
    : 'Optional event: attendance is tracked, but it will not affect season attendance percentages.';
  await renderAttendanceList(); closeSheets(); openSheet('attendanceSheet');
}

async function renderAttendanceList(){
  if(!activeEvent||!rosterRows.length){ $('attendanceList').innerHTML='<div class="empty-card">No athletes on the active roster yet.</div>'; return; }
  const [{data:att},{data:rsvps}]=await Promise.all([
    client.from('event_attendance').select('*').eq('event_id',activeEvent.id),
    client.from('event_rsvps').select('*').eq('event_id',activeEvent.id)
  ]);
  const amap=new Map((att||[]).map(x=>[x.athlete_id,x])); const rmap=new Map((rsvps||[]).map(x=>[x.athlete_id,x]));
  $('attendanceList').innerHTML=rosterRows.map(a=>{
    const x=amap.get(a.athlete_id); const r=rmap.get(a.athlete_id); const status=x?.status||'expected';
    return `<div class="attendance-card" data-athlete="${a.athlete_id}">
      <div class="attendance-top"><div><b>${esc(a.first_name)} ${esc(a.last_name)}</b><small>RSVP: ${r?esc(r.response.replace('_',' ')):'—'}</small></div><small>${x?.excuse_status&&x.excuse_status!=='none'?esc(x.excuse_status.replace('_',' ')):''}</small></div>
      <div class="attendance-buttons">
        ${['present','late','absent','modified'].map(s=>`<button class="att-btn ${status===s?'active '+s:''}" data-status="${s}" data-athlete-id="${a.athlete_id}">${s[0].toUpperCase()+s.slice(1)}</button>`).join('')}
      </div>
      ${x?.excuse_reason?`<div class="excuse-line">Excuse: ${esc(x.excuse_reason.replace('_',' '))}</div>`:''}
    </div>`;
  }).join('');
  $('attendanceList').querySelectorAll('.att-btn').forEach(btn=>btn.onclick=()=>markAttendance(btn.dataset.athleteId,btn.dataset.status));
}

async function markAttendance(athleteId,status){
  if(!activeEvent) return;
  const { error }=await client.rpc('mark_event_attendance',{p_event_id:activeEvent.id,p_athlete_id:athleteId,p_status:status});
  if(error){ message(error.message,true); return; }
  await renderAttendanceList();
}

async function deleteEvent(){
  if(!activeEvent) return;
  if(!confirm(`Delete ${activeEvent.title}?`)) return;
  const { error }=await client.from('team_events').delete().eq('id',activeEvent.id);
  if(error){ message(error.message,true); return; }
  closeSheets(); activeEvent=null; message('Event deleted.'); await loadSchedule();
}

$('signUpBtn').onclick=async()=>{
  message(''); const email=$('email').value.trim(); const password=$('password').value;
  if(!email||password.length<6){message('Enter an email and a password of at least 6 characters.',true);return;}
  const {data,error}=await client.auth.signUp({email,password}); if(error){message(error.message,true);return;}
  message(data.session?'Account created and signed in.':'Account created. Check your email if confirmation is required.'); await refresh();
};
$('signInBtn').onclick=async()=>{message('');const {error}=await client.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value});if(error){message(error.message,true);return;}await refresh();};
$('signOutBtn').onclick=async()=>{await client.auth.signOut();location.reload();};
$('createTeamBtn').onclick=async()=>{
  const {error}=await client.rpc('bootstrap_wrestling_organization',{p_organization_name:$('orgName').value.trim(),p_team_name:$('teamName').value.trim(),p_team_type:$('teamType').value,p_gender_scope:$('genderScope').value,p_season_name:$('seasonName').value.trim()});
  if(error){message(error.message,true);return;} message('Organization and team created.'); await refresh();
};

$('newEventBtn').onclick=prepareEventForm; $('saveEventBtn').onclick=saveEvent; $('attendanceBtn').onclick=openAttendance; $('deleteEventBtn').onclick=deleteEvent;
$('rosterBtn').onclick=()=>openSheet('rosterSheet'); $('addAthleteBtn').onclick=openAddAthlete; $('saveAthleteBtn').onclick=saveAthlete; $('joinBtn').onclick=()=>openSheet('joinSheet'); $('accountBtn').onclick=()=>openSheet('accountSheet'); $('profileBtn').onclick=()=>openSheet('accountSheet');
$('sheetBackdrop').onclick=closeSheets; document.querySelectorAll('[data-close-sheet]').forEach(x=>x.onclick=closeSheets);
document.querySelectorAll('.type-btn').forEach(btn=>btn.onclick=()=>applyEventTypeDefaults(btn.dataset.type));
document.querySelectorAll('.nav-btn').forEach(btn=>btn.onclick=()=>setTab(btn.dataset.tab));
document.querySelectorAll('[data-go]').forEach(btn=>btn.onclick=()=>{setTab(btn.dataset.go);if(btn.dataset.action==='create-event')setTimeout(prepareEventForm,0);});
document.querySelectorAll('.filter-chip').forEach(btn=>btn.onclick=()=>{scheduleFilter=btn.dataset.filter;document.querySelectorAll('.filter-chip').forEach(x=>x.classList.toggle('active',x===btn));renderSchedule();});

$('joinCodeBtn').onclick=async()=>{
  if(!activeTeam)return; const {data,error}=await client.rpc('create_team_join_code',{p_team_id:activeTeam.id});
  if(error){message(error.message,true);return;} const code=data?.[0]?.join_code||data?.join_code||'Created';
  $('joinCodeBox').innerHTML=`<div class="joincode">${esc(code)}</div><div class="info-banner">Athletes and parents can use the same team code. Coach approval is still required.</div>`;
};

client.auth.onAuthStateChange(()=>setTimeout(refresh,0));
refresh();
