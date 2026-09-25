/* All real data passes through the server's permission-filtered projection. */
window.WMTournaments=(()=>{
 const el=id=>document.getElementById(id),labels={queued:'Queued',in_hole:'In the hole',on_deck:'On deck',up_next:'Up next',on_mat:'On mat',complete:'Complete',bye:'Bye',scratched:'Scratched',forfeit:'Forfeit'};
 const finished=new Set(['complete','bye','scratched','forfeit']);
 let generation=0,identity='',context=null,board=null,eventId='',editing=null,busy=false,demo=false,demoNow=0,alertState={},alertLog=[],timer;
 const account=()=>[session?.user?.id,activeTeam?.id].join(':');
 const visible=()=>!el('tournamentSheet').classList.contains('hidden');
 const allowed=()=>session?.user?.id&&activeTeam?.id&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)');
 const current=g=>generation===g&&identity===account()&&allowed()&&visible();
 function reset(){generation++;clearInterval(timer);context=board=editing=null;eventId='';identity='';busy=false;demo=false;alertState={};alertLog=[];el('tournamentBody').innerHTML='';el('tournamentStatus').textContent='';}
 async function rpc(action,data={},g=generation){
  const teamId=activeTeam?.id;const response=await WMTournamentProviders.manual.request(client,action,{...data,team_id:teamId});
  if(!current(g))return null;if(response.error)throw new Error(response.error.message||'Could not load tournament data.');return response.data;
 }
 function note(text,bad=false){el('tournamentStatus').textContent=text;el('tournamentStatus').className=bad?'error':'fine';}
 function time(iso,tz){if(!iso)return 'Time unknown';try{return new Intl.DateTimeFormat(undefined,{month:'short',day:'numeric',hour:'numeric',minute:'2-digit',timeZone:tz||undefined,timeZoneName:'short'}).format(new Date(iso));}catch{return 'Time unknown';}}
 const options=(rows,value)=>rows.map(r=>`<option value="${esc(r.id)}" ${r.id===value?'selected':''}>${esc(r.title||r.name)}</option>`).join('');
 function shell(){
  el('tournamentBody').innerHTML=`<div class="tournament-source"><b>${demo?'DEMO · Sample athletes':'COACH ENTERED'}</b><span>USA Bracketing connection pending</span></div><div class="tournament-toolbar"><label>Tournament<select id="tournamentEvent">${demo?'<option>Sample Wrestling Invitational</option>':'<option value="">Choose an event</option>'+options(context?.events||[],eventId)}</select></label><button type="button" id="tournamentDemo" class="secondary">${demo?'Exit demo':'Try sample tournament'}</button></div><div id="tournamentContent"></div><div id="tournamentFamily"></div>${!demo&&context?.can_manage?'<details class="tournament-family"><summary>Scoring &amp; weigh-in tools</summary><p>Open your existing records. Nothing is submitted to USA Bracketing from these tools.</p><div class="tournament-toolbar"><a class="button" href="./mat-mode.html">Mat Mode</a><button id="tournamentMatchBook" type="button" class="secondary">Match Book</button><button id="tournamentWeighSheets" type="button" class="secondary">Official weigh-in sheets</button></div></details>':''}`;
  el('tournamentEvent').disabled=demo;el('tournamentEvent').onchange=async e=>{eventId=e.target.value;editing=null;await loadBoard();};
  el('tournamentDemo').onclick=()=>demo?open():openDemo();
  el('tournamentMatchBook')?.addEventListener('click',()=>{closeSheets();window.WMMatch?.open();});el('tournamentWeighSheets')?.addEventListener('click',()=>{closeSheets();el('officialWeighInSheetsBtn')?.click();});
  if(!demo)renderFamily();
 }
 function renderFamily(){
  const people=(context?.athletes||[]).filter(a=>a.can_set_visibility),box=el('tournamentFamily');if(!box)return;
  box.innerHTML=people.length?`<details class="tournament-family"><summary>What my athletes can see</summary><p>Your parent view keeps full information. These choices apply to the athlete's Tournament Day view across their teams.</p>${people.map(a=>`<div class="tournament-visibility"><label>${esc(a.name)}<select data-tournament-visibility="${a.id}"><option value="full" ${a.visibility==='full'?'selected':''}>Full bout details & bracket links</option><option value="upcoming" ${a.visibility==='upcoming'?'selected':''}>Next bout, status & time · no opponent</option><option value="mat_only" ${a.visibility==='mat_only'?'selected':''}>Mat & bout number only</option></select></label><button type="button" data-tournament-save-visibility="${a.id}">Save</button></div>`).join('')}</details>`:'';
  box.querySelectorAll('[data-tournament-save-visibility]').forEach(btn=>btn.onclick=async()=>{
   if(busy)return;const a=people.find(x=>x.id===btn.dataset.tournamentSaveVisibility),level=box.querySelector(`[data-tournament-visibility="${a.id}"]`).value,g=generation;busy=true;btn.disabled=true;el('tournamentContent').innerHTML='';
   try{const result=await rpc('visibility',{athlete_id:a.id,level,revision:a.visibility_revision},g);if(!result)return;context=result;note('Athlete visibility saved.');shell();if(eventId)await loadBoard();else renderBoard();}catch(e){if(current(g)){note(e.message,true);board=null;renderBoard();}}finally{if(current(g)){busy=false;btn.disabled=false;}}
  });
 }
 function projectedDemo(){
  const level=el('tournamentDemoView')?.value||'full';return board.bouts.map(b=>{
   const common={id:b.id,athlete_id:b.athlete_id,athlete_name:b.athlete_name,bout_number:b.bout_number,mat:b.mat,updated_at:b.updated_at,stale:b.stale,source:'demo',visibility:level};
   if(level==='mat_only')return common;
   const next={...common,division:b.division,weight_class:b.weight_class,status:b.status,estimated_start:b.estimated_start,queue_order:b.queue_order};return level==='full'?{...b,visibility:level}:next;
  });
 }
 function cards(){
  if(!board)return;let rows=demo?projectedDemo():board.bouts;
  const athlete=el('tournamentAthleteFilter')?.value||'',mat=el('tournamentMatFilter')?.value||'';
  rows=rows.filter(b=>(!athlete||b.athlete_id===athlete)&&(!mat||b.mat===mat));
  const now=demo?demoNow:Date.now();
  el('tournamentCards').innerHTML=rows.length?rows.map(b=>{
   const stale=b.stale||now-Date.parse(b.updated_at)>600000,mins=b.estimated_start?Math.ceil((Date.parse(b.estimated_start)-now)/60000):null;
   const next=board.bouts.filter(x=>x.athlete_id===b.athlete_id&&!finished.has(x.status)).sort((a,c)=>{const rank=x=>({on_mat:0,up_next:1,on_deck:2,in_hole:3,queued:4}[x.status]??5);return rank(a)-rank(c)||a.queue_order-c.queue_order||String(a.estimated_start||'z').localeCompare(c.estimated_start||'z')||a.id.localeCompare(c.id);})[0]?.id===b.id;
   return `<article class="tournament-bout ${stale?'tournament-stale':''}" data-tournament-bout="${esc(b.id)}"><div class="tournament-card-head"><div><small>${next?'NEXT BOUT':finished.has(b.status)?'RESULT':'BOUT'}</small><h3>${esc(b.athlete_name)}</h3></div>${b.status?`<span class="tournament-status-pill">${esc(labels[b.status]||b.status)}</span>`:''}</div><div class="tournament-assignment"><b>${b.mat?'Mat '+esc(b.mat):'Mat pending'}</b><b>Bout ${esc(b.bout_number)}</b></div>${b.division?`<p>${esc(b.division)} · ${esc(b.weight_class)}</p>`:''}${b.visibility!=='mat_only'?`<p class="tournament-time">${stale?'Update needed':b.estimated_start?mins<0?'Estimate passed · confirm at the mat':`~${mins} min · ${esc(time(b.estimated_start,board.timezone))}`:'Time unknown'}</p>`:''}${b.opponent?`<p>Opponent: <b>${esc(b.opponent)}</b></p>`:''}${b.result?`<p>Coach-entered result: ${esc(b.result)}</p>`:''}${b.bracket_url&&/^https:\/\//.test(b.bracket_url)?`<a href="${esc(b.bracket_url)}" target="_blank" rel="noopener noreferrer">Open bracket reference ↗</a>`:''}<small>${demo?'Sample data':'Coach entered'} · Updated ${esc(time(b.updated_at,board.timezone))}${stale?' · May be out of date':''}</small>${board.can_manage&&!demo?`<button type="button" class="secondary" data-tournament-edit="${esc(b.id)}">Edit bout</button>`:''}</article>`;
  }).join(''):'<div class="empty-card">No bout assignments are available for this view yet.</div>';
  el('tournamentCards').querySelectorAll('[data-tournament-edit]').forEach(b=>b.onclick=()=>editBout(board.bouts.find(x=>x.id===b.dataset.tournamentEdit)));
 }
 function renderBoard(){
  const box=el('tournamentContent');if(!box)return;
  if(!eventId&&!demo){box.innerHTML='<div class="empty-card">Choose a tournament from the team schedule, or try the sample tournament.</div>';return;}
  if(!board){box.innerHTML='<div class="empty-card">Tournament data is unavailable. Tap Refresh to try again.</div>';return;}
  if(!board.workspace_id&&!demo){box.innerHTML=`<div class="empty-card"><h3>${esc(board.title)}</h3><p>No bout board has been set up yet.</p>${board.can_manage?'<label>Event timezone<input id="tournamentTimezone" value="America/Denver" maxlength="80"></label><button type="button" id="tournamentSetup">Set up manual bout board</button>':'Your coach can set up the bout board.'}</div>`;el('tournamentSetup')?.addEventListener('click',()=>mutate('setup',{timezone:el('tournamentTimezone').value}));return;}
  box.innerHTML=`<div class="tournament-heading"><div><h3>${esc(board.title)}</h3><p>${demo?'Simulated times and alerts. No team records or messages are changed.':'Assignments and results are entered by a coach. Confirm timing with the event.'}</p></div>${board.can_manage&&!demo?'<button id="tournamentAdd" type="button">＋ Add bout</button>':''}</div>${demo?'<div class="tournament-demo-controls"><label>Sample viewer<select id="tournamentDemoView"><option value="full">Coach / parent · full</option><option value="upcoming">Athlete · next bout</option><option value="mat_only">Athlete · mat & bout only</option></select></label><div class="tournament-toolbar"><button data-sim="advance" type="button">Advance 5 min</button><button data-sim="delay" type="button" class="secondary">Delay 10 min</button><button data-sim="mat" type="button" class="secondary">Change mat</button><button data-sim="status" type="button" class="secondary">Next status</button><button data-sim="unknown" type="button" class="secondary">Unknown time</button><button data-sim="stale" type="button" class="secondary">Stale update</button></div><p id="tournamentDemoClock" class="fine"></p></div>':''}<details class="tournament-filter-details"><summary>Filter athletes &amp; mats</summary><div class="tournament-filters"><label>Athlete<select id="tournamentAthleteFilter"><option value="">All available athletes</option>${options(board.athletes||[],'')}</select></label><label>Mat<select id="tournamentMatFilter"><option value="">All mats</option>${[...new Set(board.bouts.map(b=>b.mat).filter(Boolean))].map(m=>`<option>${esc(m)}</option>`).join('')}</select></label></div></details><div id="tournamentEdit"></div><div id="tournamentCards" class="tournament-cards"></div>${demo?'<details open class="tournament-alerts"><summary>Simulated alert preview</summary><p>No notifications are sent. Duplicate countdowns stay suppressed when the estimate moves.</p><div id="tournamentAlertLog"></div></details>':''}`;
  el('tournamentAdd')?.addEventListener('click',()=>editBout(null));el('tournamentAthleteFilter').onchange=cards;el('tournamentMatFilter').onchange=cards;
  el('tournamentDemoView')?.addEventListener('change',()=>{alertState={};alertLog=[];simulate();});
  box.querySelectorAll('[data-sim]').forEach(b=>b.onclick=()=>{
   const target=board.bouts[0],now=demoNow;target.revision++;
   if(b.dataset.sim==='advance'){demoNow+=300000;for(const row of board.bouts){row.updated_at=new Date(demoNow).toISOString();row.stale=false;}}
   if(b.dataset.sim==='delay')target.estimated_start=new Date((Date.parse(target.estimated_start)||now)+600000).toISOString();
   if(b.dataset.sim==='mat')target.mat=target.mat==='1'?'3':'1';
   if(b.dataset.sim==='status'){const order=['queued','in_hole','on_deck','up_next','on_mat','complete'];target.status=order[(order.indexOf(target.status)+1)%order.length];}
   if(b.dataset.sim==='unknown')target.estimated_start=null;
   target.updated_at=new Date(demoNow).toISOString();target.stale=false;
   if(b.dataset.sim==='stale'){target.updated_at=new Date(demoNow-660000).toISOString();target.stale=true;}
   simulate();
  });cards();if(demo)simulate();
 }
 function simulate(){const result=WMTournamentAlerts.step(alertState,projectedDemo(),demoNow);alertState=result.state;alertLog.push(...result.alerts);el('tournamentDemoClock').textContent='Sample clock: '+time(new Date(demoNow).toISOString(),board.timezone);el('tournamentAlertLog').innerHTML=alertLog.length?alertLog.slice(-20).map(a=>`<p class="notice">${esc(a.body)}</p>`).join(''):'<p class="fine">No new alerts for this view.</p>';cards();}
 function editBout(b){
  if(busy||!board?.can_manage||demo)return;editing=b||{id:crypto.randomUUID(),revision:0,athlete_id:board.athletes[0]?.id||'',status:'queued'};
  const fields=[['division','Division',80],['weight_class','Weight class (include unit)',40],['bout_number','Displayed bout number',40],['mat','Mat (blank if unknown)',40],['opponent','Opponent (optional)',160],['result','Result / correction note (optional)',240],['bracket_url','Bracket reference URL (optional)',1000]];
  el('tournamentEdit').innerHTML=`<form id="tournamentBoutForm" class="tournament-editor"><h3>${b?'Edit bout':'Add bout'}</h3><label>Athlete<select name="athlete_id" required>${options(board.athletes,editing.athlete_id)}</select></label><div class="tournament-form-grid">${fields.map(([k,label,len])=>`<label>${label}<input name="${k}" maxlength="${len}" ${['division','weight_class','bout_number'].includes(k)?'required':''} ${k==='bracket_url'?'type="url" placeholder="https://…"':''} value="${esc(editing[k]||'')}"></label>`).join('')}<label>Status<select name="status">${Object.entries(labels).map(([k,v])=>`<option value="${k}" ${editing.status===k?'selected':''}>${v}</option>`).join('')}</select></label><label>Queue order<input name="queue_order" type="number" min="0" max="1000000" step="1" value="${editing.queue_order||0}"></label><label>Estimated start (your device time)<input name="estimated_start" type="datetime-local" value="${editing.estimated_start?esc(localDateTimeValue(new Date(editing.estimated_start))):''}"></label></div><p class="fine">Leave the estimated start blank if unknown. Queue order resolves upcoming bouts with the same status; bout numbers do not determine timing.</p><div class="tournament-toolbar"><button type="submit">Save bout</button><button id="tournamentCancelEdit" class="secondary" type="button">Cancel</button></div></form>`;
  el('tournamentCancelEdit').onclick=()=>{editing=null;el('tournamentEdit').innerHTML='';};el('tournamentBoutForm').onsubmit=async e=>{e.preventDefault();const values=Object.fromEntries(new FormData(e.target));values.queue_order=Number(values.queue_order);values.estimated_start=values.estimated_start?new Date(values.estimated_start).toISOString():null;await mutate('save_bout',{...values,id:editing.id,revision:editing.revision});};el('tournamentEdit').scrollIntoView({block:'start'});
 }
 async function mutate(action,values){if(busy)return;const g=generation;busy=true;el('tournamentContent').querySelectorAll('button').forEach(b=>b.disabled=true);try{const result=await rpc(action,{event_id:eventId,...values},g);if(!result)return;board=result;editing=null;context.athletes=result.athletes;renderBoard();note('Saved. This is a coach-entered record.');}catch(e){if(current(g))note(e.message,true);}finally{if(current(g)){busy=false;el('tournamentContent').querySelectorAll('button').forEach(b=>b.disabled=false);}}}
 async function loadBoard(){const g=++generation;board=null;el('tournamentContent').innerHTML='<p>Checking access and loading bouts…</p>';if(!eventId){renderBoard();return;}
  try{const result=await rpc('board',{event_id:eventId},g);if(!result)return;board=result;context.athletes=result.athletes;renderBoard();renderFamily();note('');}catch(e){if(current(g)){board=null;renderBoard();note(e.message,true);}}
 }
 async function open(id=''){
  if(!allowed()){message('Sign in to your personal team account to open Tournament Day.',true);return;}
  closeSheets();openSheet('tournamentSheet');identity=account();const g=++generation;note('Loading tournaments…');
  try{const data=await rpc('context',{},g);if(!data)return;context=data;eventId=data.events.some(e=>e.id===id)?id:'';shell();if(eventId)await loadBoard();else{renderBoard();note('');}timer=setInterval(()=>refresh(false),20000);}catch(e){if(current(g)){note(e.message,true);el('tournamentBody').innerHTML='<p>Try Refresh after checking your connection.</p>';}}
 }
 function openDemo(){generation++;demo=true;editing=null;demoNow=Date.now();alertState={};alertLog=[];board={workspace_id:'demo',title:'Sample Wrestling Invitational',timezone:Intl.DateTimeFormat().resolvedOptions().timeZone,can_manage:false,athletes:[{id:'sample-a',name:'Sample Wrestler A'},{id:'sample-b',name:'Sample Wrestler B'}],bouts:[{id:'sample-bout-a',athlete_id:'sample-a',athlete_name:'Sample Wrestler A',division:'16U',weight_class:'120 lb',bout_number:'101',mat:'1',opponent:'Sample Opponent A',status:'queued',estimated_start:new Date(demoNow+35*60000).toISOString(),updated_at:new Date(demoNow).toISOString(),queue_order:1,revision:1},{id:'sample-bout-b',athlete_id:'sample-b',athlete_name:'Sample Wrestler B',division:'Junior',weight_class:'145 lb',bout_number:'101',mat:'2',opponent:'Sample Opponent B',status:'on_deck',estimated_start:null,updated_at:new Date(demoNow).toISOString(),queue_order:2,revision:1}]};shell();renderBoard();note('Demo only · no live tournament connection or notifications.');}
 async function refresh(force){if(!visible()||document.hidden)return;if(identity!==account()||!allowed()){reset();show('tournamentSheet',false);return;}if(busy||demo)return;if(editing&&!force)return;if(force)editing=null;if(!context){await open(eventId);return;}await loadBoard();}
 function sync(){show('tournamentDayBtn',!!activeTeam&&!managedLogin);show('tournamentScheduleBtn',!!activeTeam&&!managedLogin);if(visible()&&(identity!==account()||!allowed())){reset();show('tournamentSheet',false);}}
 el('tournamentRefresh').onclick=()=>refresh(true);el('tournamentDayBtn').onclick=()=>open();el('tournamentScheduleBtn').onclick=()=>open();el('eventTournamentBtn').onclick=()=>open(activeEvent?.id);
 window.addEventListener('focus',()=>refresh(true));document.addEventListener('visibilitychange',()=>{if(document.hidden&&!demo&&visible()){board=null;el('tournamentContent')&&(el('tournamentContent').innerHTML='');}else refresh(true);});
 const observer=new MutationObserver(()=>{if(visible()&&!allowed()){reset();show('tournamentSheet',false);}});observer.observe(document.body,{attributes:true,attributeFilter:['class']});if(el('appLockOverlay'))observer.observe(el('appLockOverlay'),{attributes:true,attributeFilter:['class']});
 return {open,reset,sync,refresh,providers:WMTournamentProviders};
})();
