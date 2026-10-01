/* Trainer workspace: uses existing health authorization; keeps no offline health cache. */
(() => {
 'use strict';
 const $t=id=>document.getElementById(id);
 const home=$t('homeTab'),panel=document.createElement('section');
 panel.id='trainerDashboardPanel';panel.className='hidden';panel.setAttribute('aria-labelledby','trainerDashboardTitle');home.prepend(panel);
 const entry=document.createElement('button');entry.id='trainerHomeEntry';entry.type='button';entry.className='wide secondary hidden';entry.textContent='Open Trainer Dashboard';panel.after(entry);
 const more=document.createElement('button');more.id='trainerDashboardMoreBtn';more.type='button';more.className='menu-row hidden';more.innerHTML='<span aria-hidden="true">✚</span><div><b>Trainer Dashboard</b><small>Your assigned teams and athlete care</small></div><i aria-hidden="true">›</i>';
 $t('moreTab').querySelector('.toolbox-title').after(more);
 let epoch=0,context='',ready=false,choice=null,busy=false,lastLoad=0,validAccess=false,blocked=false;
 const key=()=>session?.user?.id&&activeTeam?.id?session.user.id+'/'+activeTeam.id:'';
 const memberships=()=>currentTeamMemberships.filter(m=>m.active!==false&&m.team_id===activeTeam?.id);
 const assigned=()=>!!session?.user?.id&&!managedLogin&&memberships().some(m=>m.role==='manager'&&m.permissions?.staff_role==='team_trainer');
 const exclusive=()=>assigned()&&!actualIsStaff&&!familyAthletes.length&&!memberships().some(m=>m.role!=='manager'||m.permissions?.staff_role!=='team_trainer');
 const unlocked=()=>!document.hidden&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&$t('appLockOverlay').classList.contains('hidden')&&!$t('appView').classList.contains('hidden');
 const displayed=()=>ready&&assigned()&&unlocked()&&!home.classList.contains('hidden')&&home.classList.contains('wm-trainer-home')&&!document.querySelector('.sheet:not(.hidden)');
 const current=g=>g===epoch&&context===key()&&displayed()&&navigator.onLine;
 const filters=['all','awaiting','restricted','due','baseline'];
 function localDay(){
  try{return new Intl.DateTimeFormat('en-CA',{timeZone:activeTeam?.timezone||undefined,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())}
  catch{return new Date().toLocaleDateString('en-CA')}
 }
 function matches(a,filter,day,required=true){
  const cases=Array.isArray(a.cases)?a.cases:[];
  if(filter==='awaiting')return cases.some(c=>c.status==='awaiting_trainer');
  if(filter==='restricted')return cases.some(c=>['not_cleared','modified','no_contact'].includes(c.status));
  if(filter==='due')return cases.some(c=>c.review_on&&c.review_on<=day);
  if(filter==='baseline')return required&&!a.baseline;
  return true;
 }
 function counts(data,day){
  if(data?.trainer!==true||data?.assigned_trainer!==true)return null;
  const rows=Array.isArray(data.athletes)?data.athletes:[];
  return Object.fromEntries(filters.map(f=>[f,rows.filter(a=>matches(a,f,day,data.baseline_required!==false)).length]));
 }
 function clear(){epoch++;busy=false;lastLoad=0;validAccess=false;panel.replaceChildren()}
 function reset(){clear();context='';choice=null;ready=false;blocked=false;home.classList.remove('wm-trainer-home');show(panel.id,false);show(entry.id,false);show(more.id,false)}
 function suspend(){reset()}
 function prepared(){ready=true;sync()}
 function chrome(){
  panel.innerHTML='<div class="trainer-heading"><div><div class="eyebrow">ATHLETE CARE</div><h2 id="trainerDashboardTitle">Trainer Dashboard</h2><p id="trainerTeamName" class="muted"></p></div><button id="trainerRefresh" type="button" class="secondary">Refresh</button></div><div class="trainer-team-choice"><label for="trainerAssignedTeams">Assigned teams</label><select id="trainerAssignedTeams"></select></div><div id="trainerDashboardBody" aria-live="polite"></div><button type="button" id="trainerReturnHome" class="wide secondary">Team / Family Home</button><p class="fine">Team and family permissions stay separate. Care records are online only. For an urgent concern, contact the trainer directly.</p>';
  $t('trainerTeamName').textContent=activeTeam?.name||'Selected team';
  const ids=new Set(teamMemberships.filter(m=>m.active!==false&&m.user_id===session?.user?.id&&m.role==='manager'&&m.permissions?.staff_role==='team_trainer').map(m=>m.team_id));
  const teams=availableTeams.filter(t=>ids.has(t.id));
  const select=$t('trainerAssignedTeams');
  for(const t of teams){const o=document.createElement('option');o.value=t.id;o.textContent=t.name;o.selected=t.id===activeTeam.id;select.append(o)}
  if(!teams.some(t=>t.id===activeTeam.id)){const o=document.createElement('option');o.value=activeTeam.id;o.textContent=activeTeam.name;select.append(o)}
  select.disabled=select.options.length<2;
  select.onchange=async()=>{const id=select.value;if(!ids.has(id)||!teams.some(t=>t.id===id))return;select.disabled=true;try{await activateTeam(id);if(assigned()){choice='trainer';setTab('home');sync()}}catch{sync()}};
  $t('trainerRefresh').onclick=()=>{blocked=false;clear();chrome();void load()};
  $t('trainerReturnHome').onclick=()=>{choice='team';clear();sync()};
 }
 function notice(text){if(!$t('trainerDashboardBody'))chrome();$t('trainerDashboardBody').replaceChildren();const p=document.createElement('p');p.className='empty-card';p.textContent=text;$t('trainerDashboardBody').append(p)}
 function render(data){
  const totals=counts(data,localDay());
  if(!totals){
   notice(data?.assigned_trainer===true?'Accept your Team Trainer responsibility before opening athlete care records.':'Trainer access is not available for this team. Ask the team administrator to check your assignment.');
   if(data?.assigned_trainer===true){const b=document.createElement('button');b.type='button';b.id='trainerAcceptRole';b.textContent='Review & Accept Trainer Role';b.onclick=()=>{clear();WMAthleteHealth.open()};$t('trainerDashboardBody').append(b)}
   return;
  }
  const names={awaiting:'Awaiting review',restricted:'Activity restrictions',due:'Reviews due',baseline:'Missing baselines'};
  $t('trainerDashboardBody').innerHTML=`<p class="fine">${totals.all} authorized athlete${totals.all===1?'':'s'} · Counts below are athletes, not diagnoses.</p><div class="trainer-metrics">${Object.entries(names).map(([f,label])=>`<button type="button" class="trainer-metric" data-trainer-filter="${f}"><strong>${totals[f]}</strong><span>${label}</span></button>`).join('')}</div><p class="fine">An empty concern list or a completed baseline does not establish medical clearance.</p><div class="trainer-links"><button type="button" id="trainerAthletes">Athletes & Baselines</button><button type="button" id="trainerCareUpdates" class="secondary">Care Updates</button><button type="button" id="trainerSchedule" class="secondary">Team Schedule · read only</button></div><p class="fine">Care Updates opens athlete records with private family updates kept separate from coach-shared participation instructions.</p><div id="trainerScheduleBody"></div><p class="fine">Last checked ${esc(new Date().toLocaleTimeString())}. Refresh to check for changes; this is not an urgent-alert service.</p>`;
  const openHealth=filter=>{clear();WMAthleteHealth.open({filter})};
  panel.querySelectorAll('[data-trainer-filter]').forEach(b=>b.onclick=()=>openHealth(b.dataset.trainerFilter));
  $t('trainerAthletes').onclick=()=>openHealth('all');$t('trainerCareUpdates').onclick=()=>openHealth('all');$t('trainerSchedule').onclick=()=>void schedule();
 }
 async function schedule(){
  if(!validAccess||!current(epoch))return;
  const g=epoch,team=activeTeam.id,box=$t('trainerScheduleBody');box.textContent='Loading schedule…';
  try{
   const {data:access,error:denied}=await client.rpc('athlete_health_request',{p_action:'dashboard',p_data:{team_id:team}});
   if(!current(g))return;if(denied||access?.trainer!==true||access?.assigned_trainer!==true)throw Error('Trainer access changed. Refresh to check your assignment.');
   const {data,error}=await client.from('team_events').select('id,title,event_type,starts_at,ends_at,location_name').eq('team_id',team).gte('starts_at',new Date().toISOString()).order('starts_at',{ascending:true}).limit(12);
   if(!current(g))return;if(error)throw Error('Schedule could not load. Try again when connected.');
   box.innerHTML='<h3>Upcoming team events</h3>'+(data?.length?data.map(e=>`<article class="health-card"><b>${esc(e.title||e.event_type||'Team event')}</b><p>${esc(new Date(e.starts_at).toLocaleString())}</p>${e.location_name?'<p>'+esc(e.location_name)+'</p>':''}</article>`).join(''):'<p>No upcoming team events were returned.</p>');
  }catch(e){if(current(g)){box.textContent=e.message;validAccess=false}}
 }
 async function load(){
  if(busy||blocked||!displayed()||!navigator.onLine)return;
  busy=true;const g=epoch,team=activeTeam.id;notice('Checking trainer access…');
  try{
   const {data,error}=await client.rpc('athlete_health_request',{p_action:'dashboard',p_data:{team_id:team}});
   if(!current(g))return;if(error)throw Error('Trainer access could not be checked. Refresh when connected.');
   validAccess=data?.trainer===true&&data?.assigned_trainer===true;lastLoad=Date.now();render(data);
  }catch(e){if(current(g)){validAccess=false;blocked=true;notice(e.message)}}finally{if(g===epoch)busy=false}
 }
 function sync(){
  const k=key();if(context!==k){clear();context=k;choice=null;blocked=false}
  const candidate=ready&&assigned()&&unlocked();show(more.id,candidate);
  if(!candidate){if(panel.childNodes.length)clear();home.classList.remove('wm-trainer-home');show(panel.id,false);show(entry.id,false);return}
  const use=choice==='trainer'||(choice===null&&exclusive());home.classList.toggle('wm-trainer-home',use);show(panel.id,use);show(entry.id,!use);
  if(!use||home.classList.contains('hidden')||document.querySelector('.sheet:not(.hidden)')){if(panel.childNodes.length)clear();return}
  if(!navigator.onLine){if(validAccess||busy)clear();notice('Reconnect to view the Trainer Dashboard. Private care records are not stored offline.');return}
  if(!panel.childNodes.length)chrome();
  if(!lastLoad&&!busy&&!blocked)void load();
 }
 function open(){if(!ready||!assigned()||!unlocked())return;choice='trainer';blocked=false;clear();closeSheets();setTab('home');sync()}
 entry.onclick=open;more.onclick=open;
 window.addEventListener('offline',()=>{clear();sync()});window.addEventListener('online',()=>{blocked=false;sync()});
 document.addEventListener('visibilitychange',()=>{clear();blocked=false;sync()});
 setInterval(()=>{sync();if(displayed()&&navigator.onLine&&lastLoad&&Date.now()-lastLoad>15000&&!busy&&!blocked)void load()},500);
 window.WMTrainerDashboard={open,reset,suspend,prepared,sync,matches,counts};
})();
