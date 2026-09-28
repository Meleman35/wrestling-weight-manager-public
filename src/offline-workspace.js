/* First offline slice: personal coach accounts, current-season core data, recent text history. */
window.WMOffline=(()=>{
 'use strict';const S=window.WMOfflineStore,$=id=>document.getElementById(id),E=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const WEBSITE='https://theteammanager.app';
 const inNativeApp=()=>!!window.wrestlingManagerNativeShellVersion||window.wrestlingManagerNativeLifecycle===true||!!window.webkit?.messageHandlers?.security;
 function unavailable(){if(inNativeApp())return 'native';if(!window.isSecureContext)return 'secure';if(!navigator.serviceWorker||!window.indexedDB||!window.crypto?.subtle||!window.caches)return 'browser';return '';}
 const ACTIVE='wm.offline.active.v1';let owner='',unlocked=false,packId='',view='home',detail='',generation=0,busy=false,syncing=false,registration,state=null,draftFlight=Promise.resolve();
 const user=()=>session?.user?.id||localStorage.getItem(ACTIVE)||'';
 const current=()=>unlocked&&owner===user()&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&$('appLockOverlay')?.classList.contains('hidden');
 const guard=u=>()=>current()&&owner===u;
 const key=p=>S.packKey(p.team.id,p.season.id);
 const active=p=>!['standby','removed','inactive'].includes(p.roster_status);
 const day=v=>v?new Date(v).toLocaleString():'';
 const localTime=v=>{if(!v)return '';const d=new Date(v);return new Date(d-d.getTimezoneOffset()*60000).toISOString().slice(0,16);};
 const pill=document.createElement('button');pill.id='offlineEntry';pill.type='button';pill.className='wide secondary';pill.textContent=inNativeApp()?'Offline workspace · Safari':'Offline workspace';$('securityBtn').after(pill);
 const entry=document.createElement('button');entry.id='offlineQuickEntry';entry.type='button';entry.textContent='Open saved team';entry.hidden=true;document.body.append(entry);
 const panel=document.createElement('section');panel.id='offlineWorkspace';panel.hidden=true;panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-label','Offline team workspace');panel.innerHTML='<div class="of-header"><button id="ofBack" class="secondary" type="button">Back</button><h2>Offline workspace</h2><button id="ofLock" class="secondary" type="button">Lock</button></div><p id="ofStatus" role="status" aria-live="polite"></p><div id="ofBody"></div>';document.body.append(panel);
 const notice=(text,error=false)=>{$('ofStatus').textContent=text;$('ofStatus').classList.toggle('of-error',error);};
 function lock(){generation++;unlocked=false;state=null;view='home';detail='';$('ofBody').replaceChildren();panel.hidden=true;entry.hidden=navigator.onLine||!localStorage.getItem(ACTIVE);}
 function showAvailability(reason){
  unlocked=false;state=null;$('ofLock').hidden=true;
  const title=reason==='native'?'Offline downloads are available in Safari':reason==='secure'?'Open the secure website':'Use a browser with offline storage';
  const explanation=reason==='native'?'This installed app does not support the new offline team workspace yet. Native offline support needs an app update.':reason==='secure'?'Open the secure website to save your team on this device.':'This browser cannot save the offline workspace. On iPhone or iPad, open the website directly in Safari.';
  $('ofBody').innerHTML=`<article class="of-card of-availability"><h3>${E(title)}</h3><p>${E(explanation)}</p><ol><li>Connect to the internet and open Safari.</li><li>Visit the website below and sign in with your coach account.</li><li>Choose your team, then Profile → Offline workspace.</li><li>Download your team and wait for confirmation before turning on airplane mode.</li></ol><label for="ofWebsite">Website</label><input id="ofWebsite" value="${WEBSITE}" readonly autocomplete="off"><button id="ofCopyWebsite" type="button" class="wide secondary">Copy website address</button><p id="ofCopyStatus" class="fine" role="status"></p><p class="fine">Safari keeps its own sign-in and device PIN. If needed, set your profile PIN in Safari under Profile → Security.</p></article>`;
  $('ofCopyWebsite').onclick=async()=>{const g=generation,ok=await copyText(WEBSITE,{field:$('ofWebsite'),status:$('ofCopyStatus'),isCurrent:()=>g===generation&&!panel.hidden});if(ok&&g===generation&&!panel.hidden)$('ofCopyStatus').textContent='Copied. Paste this address into Safari.';};
 }
 async function shell(){
  if(unavailable())throw Error('Open Offline workspace in Safari on the secure website to download your team.');
  registration=await navigator.serviceWorker.register('./sw.js');
  await Promise.race([navigator.serviceWorker.ready,new Promise((_,reject)=>setTimeout(()=>reject(Error('The offline app download did not finish. Keep internet connected and try again.')),25000))]);
  if(!await caches.match(new URL('./index.html',location.href)))throw Error('The app download is incomplete. Reopen while connected and try again.');
 }
 async function rpc(action,data){const q=client.rpc('offline_coach_request',{p_action:action,p_data:data});const r=await Promise.race([q,new Promise((_,reject)=>setTimeout(()=>reject(Error('Connection interrupted. Your saved work stays on this device.')),18000))]);if(r.error){const e=Error(r.error.message);e.code=r.error.code;throw e;}return r.data;}
 async function open(){
  const selected=user();if(owner!==selected)lock();owner=selected;generation++;view='home';detail='';panel.hidden=false;entry.hidden=true;notice('');$('ofLock').hidden=false;
  const reason=unavailable();if(reason){showAvailability(reason);return;}
  if(!owner){$('ofBody').innerHTML='<p>Sign in online with your personal coach account, then download your team here before going offline.</p>';return;}
  if(managedLogin){$('ofBody').innerHTML='<p>Use your personal coach account for this offline workspace.</p>';return;}
  if(unlocked&&current()){await render();return;}
  unlocked=false;$('ofBody').innerHTML='<p>Unlock saved team data with your existing profile PIN.</p><form id="ofUnlockForm"><label for="ofPIN">Profile PIN</label><input id="ofPIN" type="password" inputmode="numeric" pattern="[0-9]{4,8}" maxlength="8" autocomplete="off" required><button class="wide" type="submit">Unlock workspace</button></form><p class="fine">Set your PIN in Profile → Security while online. Download only on a device you control. Device storage can be removed by browser settings or the operating system.</p>';
  $('ofUnlockForm').onsubmit=async e=>{e.preventDefault();const u=owner,g=generation,b=e.submitter;b.disabled=true;try{await WMProfilePIN.verify(u,$('ofPIN').value);if(g!==generation||u!==user())return;unlocked=true;await render();void sync();}catch(err){notice(err.message,true);}finally{b.disabled=false;}};
 }
 async function pages(action,c){let cursor=null,all=[];do{const page=await rpc(action,{...c,cursor});if(!Array.isArray(page))throw Error('The team download returned incomplete data.');all.push(...page);cursor=page.length===250?(page.at(-1).athlete_id&&action==='roster'?page.at(-1).athlete_id:page.at(-1).thread_id&&action==='threads'?page.at(-1).thread_id:page.at(-1).id):null;if(cursor&&all.length>250000)throw Error('This team needs a larger offline download. No partial copy was saved.');}while(cursor);return all;}
 async function download(){
  const reason=unavailable();if(reason){showAvailability(reason);return;}
  if(busy||!current())return;const u=owner,g=generation,t=activeTeam?.id,s=activeSeason?.id;
  if(!navigator.onLine||session?.user?.id!==u||!t||!s||!isStaff||managedLogin){notice('Connect and select a team with your personal coach account to download.',true);return;}
  busy=true;notice('Downloading app and verifying team access…');try{
   await shell();const c={team_id:t,season_id:s};const manifest=await rpc('manifest',c);
   if(manifest.user_id!==u)throw Error('The signed-in profile changed.');
   notice('Downloading roster, schedule, attendance and conversations…');
   const [roster,events,attendance,threads]=await Promise.all(['roster','events','attendance','threads'].map(a=>pages(a,c)));
   const messages={};for(let i=0;i<threads.length;i++){if(g!==generation||!guard(u)())throw Error('Workspace closed. The previous saved copy is unchanged.');notice(`Downloading conversation ${i+1} of ${threads.length}…`);messages[threads[i].thread_id]=await rpc('messages',{...c,thread_id:threads[i].thread_id});}
   const verified=await rpc('manifest',c),p={...verified,roster,events,attendance,threads,messages,downloaded_at:new Date().toISOString(),blocked:false};
   if(g!==generation||activeTeam?.id!==t||activeSeason?.id!==s)throw Error('Your team changed. Reopen and download that team.');
   await S.update(u,b=>{b.packs[key(p)]=p;},guard(u));localStorage.setItem(ACTIVE,u);packId=key(p);
   let persistent=false;try{persistent=await navigator.storage?.persist?.();}catch{}
   notice('Team saved on this device. '+(persistent?'':'Keep this browser’s app data to retain unsynced work.'));await render();
  }catch(e){notice(e.message,true);if(e.code==='42501')await blockPack(u,S.packKey(t,s),e.message);}
  finally{busy=false;}
 }
 async function blockPack(u,id,reason){await S.update(u,b=>{if(b.packs[id]){b.packs[id].blocked=true;b.packs[id].blocked_reason=reason;}},()=>owner===u&&user()===u);if(current()){view='home';detail='';await render();}}
 function usable(p){return p&&!p.blocked&&new Date(p.expires_at)>new Date();}
 async function render(){
  if(!current())return;const u=owner,g=generation,b=await S.get(u);if(g!==generation||!guard(u)())return;state=b;
  if(!b.packs[packId])packId=Object.keys(b.packs)[0]||'';const p=b.packs[packId],body=$('ofBody');
  const pending=b.queue.length;entry.textContent=pending?`${pending} saved change${pending===1?'':'s'}`:'Open saved team';
  let html=`<p class="of-connection">${pending} change${pending===1?'':'s'} awaiting sync${navigator.onLine?'':' · Offline'}</p>`;
  if(view==='home'){
   html+='<p>Download core team data before leaving service. This first release includes roster, this season’s team events and attendance, plus the latest 80 messages per conversation. Attachments and other app sections need internet.</p>';
   html+='<div class="of-actions"><button id="ofDownload" type="button">Download / update selected team</button><button id="ofSync" class="secondary" type="button">Sync saved work</button></div>';
   html+=Object.entries(b.packs).map(([id,x])=>`<article class="of-card"><h3>${E(x.team.name)}</h3><p>${E(x.season.name)} · Saved ${E(day(x.downloaded_at))}</p><p class="fine">Offline access until ${E(day(x.expires_at))}. Download again online to renew.</p>${usable(x)?`<button data-pack="${E(id)}" type="button">Open saved team</button>`:`<p class="of-error">${E(x.blocked?'Access must be verified again online. Unsynced work is retained.':'Offline access expired. Connect and update this team.')}</p>`}</article>`).join('');
   html+=`<button id="ofQueue" type="button" class="wide secondary">Review saved work (${pending})</button>`;
  }else if(view==='queue'){
   html+='<h3>Saved work</h3><p class="fine">Queued messages have not been sent. A synced message has reached the server; delivery and read status appear in Messages.</p>';
   html+=b.queue.map(q=>`<article class="of-card"><strong>${E(q.label)}</strong><p>${E(q.state==='pending'?'Saved on device · waiting to sync':q.state==='conflict'?'Needs review':q.state==='blocked'?'Could not apply':'Waiting to retry')}</p><p>${E(q.request.body||q.request.status||q.request.values?.title||'')}</p>${q.result?.message?`<p class="of-error">${E(q.result.message)}</p>`:''}${q.state==='conflict'?`<p>Server: ${E(q.request.kind==='attendance'?q.result.value?.status||'Unmarked':JSON.stringify(q.result.value&&eventValues(q.result.value)))}</p><p>Your change: ${E(q.request.kind==='attendance'?q.request.status:JSON.stringify(q.request.values))}</p><button data-server="${q.id}" type="button" class="secondary">Keep server version</button> <button data-mine="${q.id}" type="button">Apply my version</button>`:''}${q.state==='blocked'?`<button data-dismiss="${q.id}" type="button" class="secondary">Acknowledge — keep in history</button>`:''}</article>`).join('')||'<p>No changes awaiting sync.</p>';
   html+=`<button id="ofSync" class="wide" type="button">Sync now</button><h3>Recent results</h3>`+b.history.slice(0,15).map(q=>`<details class="of-card"><summary>${E(q.label)} · ${E(q.state==='applied'?'Synced':q.state==='dismissed'?'Not applied — acknowledged':'Server version kept')}</summary><p>${E(q.request.body||q.request.status||JSON.stringify(q.request.values||{}))}</p>${q.result?.message?`<p>${E(q.result.message)}</p>`:''}</details>`).join('');
  }else if(!usable(p)){view='home';return render();}
  else{
   html+=`<h3>${E(p.team.name)}</h3><p class="fine">Saved ${E(day(p.downloaded_at))}. Other coaches’ latest changes appear after you update this download. Confirm current eligibility online before competition.</p><nav class="of-tabs">${['roster','schedule','messages','queue'].map(v=>`<button data-view="${v}" class="${v===view?'':'secondary'}" type="button">${v==='queue'?'Saved work':v[0].toUpperCase()+v.slice(1)}</button>`).join('')}</nav>`;
   if(view==='roster'){
    html+='<label>Sort roster<select id="ofSort"><option value="last">Last name</option><option value="weight">Weight</option></select></label><div id="ofRoster"></div>';
   }else if(view==='schedule'){
    html+=p.events.slice().sort((a,b)=>a.starts_at.localeCompare(b.starts_at)).map(e=>`<article class="of-card"><h4>${E(e.title)}</h4><p>${E(day(e.starts_at))} · ${E(e.location_name)}</p><button data-att="${e.id}" type="button">Attendance</button> <button data-edit="${e.id}" type="button" class="secondary">Edit event</button></article>`).join('')||'<p>No saved events.</p>';
   }else if(view==='attendance'){
    const e=p.events.find(x=>x.id===detail);if(!e){view='schedule';return render();}html+=`<h3>${E(e.title)}</h3>`;
    html+=p.roster.filter(active).sort((a,b)=>a.last_name.localeCompare(b.last_name)||a.first_name.localeCompare(b.first_name)).map(a=>{const q=b.queue.find(q=>q.request.kind==='attendance'&&q.request.event_id===e.id&&q.request.athlete_id===a.athlete_id),r=p.attendance.find(r=>r.event_id===e.id&&r.athlete_id===a.athlete_id),status=q?.request.status||r?.status||'expected';return `<label class="of-card">${E(a.first_name+' '+a.last_name)}<select data-attendance="${a.athlete_id}" ${q?'disabled':''}>${['expected','present','late','absent','modified'].map(s=>`<option ${s===status?'selected':''} value="${s}">${s==='expected'?'Unmarked':s[0].toUpperCase()+s.slice(1)}</option>`).join('')}</select>${q?'<small>Saved on device · review in Saved work</small>':''}</label>`;}).join('');
   }else if(view==='edit'){
    const e=p.events.find(x=>x.id===detail);if(!e){view='schedule';return render();}html+='<p>Changes apply to this occurrence only. A changed server version will require review.</p><form id="ofEventForm">';
    for(const [k,label,type] of [['title','Title','text'],['starts_at','Start','datetime-local'],['ends_at','End','datetime-local'],['location_name','Location','text'],['location_address','Address','text']])html+=`<label>${label}<input name="${k}" type="${type}" value="${E(type==='datetime-local'?localTime(e[k]):e[k])}" ${['title','starts_at'].includes(k)?'required':''} ${k==='title'?'maxlength="200"':''}></label>`;
    html+=`<label>Notes<textarea name="description" maxlength="10000">${E(e.description)}</textarea></label><button type="submit" class="wide">Save on this device</button></form>`;
   }else if(view==='messages'){
    html+=p.threads.map(t=>`<button data-thread="${t.thread_id}" type="button" class="wide secondary">${E(t.title||t.participant_names||'Conversation')}${t.guardian_mirrored?' · Guardian access':''}</button>`).join('')||'<p>No saved conversations.</p>';
   }else if(view==='thread'){
    const t=p.threads.find(x=>x.thread_id===detail);if(!t){view='messages';return render();}html+=`<h3>${E(t.title)}</h3>${t.guardian_mirrored?'<p class="fine">Guardian access remains active when messages sync.</p>':''}`;
    html+='<div class="of-messages">'+(p.messages[detail]||[]).map(m=>`<article class="of-card ${m.is_mine?'of-mine':''}"><strong>${E(m.sender_name)}</strong><p>${E(m.body)}</p>${m.has_attachment?'<small>Attachment requires internet.</small>':''}${m.safety_level&&m.safety_level!=='none'?`<small>Safety notice: ${E(m.safety_level)}</small>`:''}<small>${E(day(m.created_at))}</small></article>`).join('')+'</div>';
    html+=b.queue.filter(q=>q.request.kind==='message'&&q.request.thread_id===detail).map(q=>`<article class="of-card of-mine" data-queued="${q.id}"><p>${E(q.request.body)}</p><small>${q.state==='pending'?'Saved on device · not sent':'Needs attention in Saved work'}</small></article>`).join('');
    if(t.can_post)html+=`<form id="ofMessageForm"><label for="ofMessage">Message</label><textarea id="ofMessage" maxlength="4000" required>${E(b.drafts[packId+'/'+detail]?.body||'')}</textarea><small id="ofDraftStatus"></small><button type="submit" class="wide">Queue message</button></form><p class="fine">Text messages send after reconnection and permission checks. Guardians, blocks and safety checks still apply.</p>`;
   }
  }
  body.innerHTML=html;bind(p,b);
 }
 function eventValues(e){const v={};for(const k of ['title','description','location_name','location_address','starts_at','ends_at','arrival_at','weigh_in_at','attendance_required','rsvp_enabled','checkout_enabled','counts_toward_season_attendance'])v[k]=e[k]??null;return v;}
 function bind(p,b){
  if($('ofDownload'))$('ofDownload').onclick=download;if($('ofSync'))$('ofSync').onclick=()=>sync(true);if($('ofQueue'))$('ofQueue').onclick=()=>navigate('queue');
  panel.querySelectorAll('[data-pack]').forEach(btn=>btn.onclick=()=>{packId=btn.dataset.pack;navigate('roster');});
  panel.querySelectorAll('[data-view]').forEach(btn=>btn.onclick=()=>navigate(btn.dataset.view));
  panel.querySelectorAll('[data-att]').forEach(btn=>btn.onclick=()=>navigate('attendance',btn.dataset.att));
  panel.querySelectorAll('[data-edit]').forEach(btn=>btn.onclick=()=>navigate('edit',btn.dataset.edit));
  panel.querySelectorAll('[data-thread]').forEach(btn=>btn.onclick=()=>navigate('thread',btn.dataset.thread));
  panel.querySelectorAll('[data-server],[data-mine],[data-dismiss]').forEach(btn=>btn.onclick=()=>resolve(btn.dataset.server||btn.dataset.mine||btn.dataset.dismiss,!!btn.dataset.mine));
  if($('ofSort')){const sort=()=>{const rows=p.roster.slice().sort((a,b)=>$('ofSort').value==='weight'?(Number(a.latest_weight??Infinity)-Number(b.latest_weight??Infinity)||a.last_name.localeCompare(b.last_name)):a.last_name.localeCompare(b.last_name)||a.first_name.localeCompare(b.first_name));$('ofRoster').innerHTML=rows.map(a=>`<article class="of-card"><strong>${E(a.first_name+' '+a.last_name)}</strong><p>${E(a.latest_weight??'No weight')} ${a.latest_weight?'lb':''} · ${E(a.roster_status)}</p></article>`).join('');};$('ofSort').onchange=sort;sort();}
  panel.querySelectorAll('[data-attendance]').forEach(sel=>sel.onchange=async()=>{const athlete=sel.dataset.attendance,e=p.events.find(x=>x.id===detail),a=p.roster.find(x=>x.athlete_id===athlete),r=p.attendance.find(x=>x.event_id===e.id&&x.athlete_id===athlete);sel.disabled=true;await queue({kind:'attendance',event_id:e.id,athlete_id:athlete,status:sel.value,expected:r?.updated_at||null},`Attendance: ${a.first_name} ${a.last_name} · ${e.title}`,p);});
  if($('ofEventForm'))$('ofEventForm').onsubmit=async ev=>{ev.preventDefault();const e=p.events.find(x=>x.id===detail),v=eventValues(e),f=new FormData(ev.currentTarget);for(const k of ['title','description','location_name','location_address'])v[k]=f.get(k).trim();for(const k of ['starts_at','ends_at'])v[k]=f.get(k)?new Date(f.get(k)).toISOString():null;if(v.ends_at&&v.ends_at<=v.starts_at){notice('Choose an end after the start.',true);return;}ev.submitter.disabled=true;await queue({kind:'event',event_id:e.id,expected:e.updated_at,values:v},`Event: ${e.title}`,p);};
  if($('ofMessage')){
   const thread=detail,savedPackId=packId,draftKey=packId+'/'+thread,u=owner,input=$('ofMessage');
   input.oninput=()=>{const text=input.value;const status=$('ofDraftStatus');status.textContent='Saving draft…';draftFlight=draftFlight.catch(()=>{}).then(()=>S.update(u,b=>{if(text)b.drafts[draftKey]={body:text,thread_id:thread,pack:savedPackId};else delete b.drafts[draftKey];},guard(u))).then(()=>{if(input.isConnected&&input.value===text)status.textContent='Draft saved on this device';}).catch(e=>{notice(e.message,true);throw e;});draftFlight.catch(()=>{});};
   $('ofMessageForm').onsubmit=async ev=>{ev.preventDefault();const text=input.value.trim();if(!text)return;ev.submitter.disabled=true;try{await draftFlight;await queue({kind:'message',thread_id:thread,body:text},`Message: ${p.threads.find(x=>x.thread_id===thread).title}`,p,draftKey);}catch(e){notice(e.message,true);ev.submitter.disabled=false;}};
  }
 }
 async function navigate(v,d=''){try{await draftFlight;}catch{return;}view=v;detail=d;notice('');await render();}
 async function queue(request,label,p,draftKey){const u=owner;try{if(!current()||!usable(p))throw Error('Unlock and update your saved team first.');await S.update(u,b=>S.enqueue(b,{...request,team_id:p.team.id,season_id:p.season.id},label,draftKey),guard(u));notice('Saved on this device. Waiting for server confirmation.');await render();void sync();}catch(e){notice(e.message,true);await render();}}
 async function resolve(id,mine){const u=owner;try{await S.update(u,b=>{const q=b.queue.find(x=>x.id===id);if(!q||!['conflict','blocked'].includes(q.state))return;const p=b.packs[S.packKey(q.request.team_id,q.request.season_id)];if(!usable(p))throw Error('Update team access before resolving this work.');if(q.state==='conflict'){if(q.request.kind==='event'&&q.result.value)p.events=p.events.map(x=>x.id===q.request.event_id?q.result.value:x);else{p.attendance=p.attendance.filter(x=>!(x.event_id===q.request.event_id&&x.athlete_id===q.request.athlete_id));if(q.result.value)p.attendance.push(q.result.value);}}
   b.queue=b.queue.filter(x=>x.id!==id);b.history.unshift({...q,state:q.state==='blocked'?'dismissed':'server-kept'});b.history=b.history.slice(0,50);
   if(mine){const req={...q.request,expected:q.result.value?.updated_at||null};delete req.operation_id;S.enqueue(b,req,q.label);}},guard(u));await render();void sync();}catch(e){notice(e.message,true);}}
 async function sync(manual=false){
  if(syncing||busy||unavailable()||!current())return;if(!navigator.onLine||session?.user?.id!==owner){if(manual)notice('Connect and sign in to this profile to sync. Saved work is retained.');return;}
  syncing=true;const u=owner;
  const run=async()=>{const b=await S.get(u);for(const item of b.queue){
   if(!guard(u)()||!navigator.onLine||session?.user?.id!==u)break;if(item.state!=='pending'||(!manual&&item.next_at>Date.now()))continue;
   const p=b.packs[S.packKey(item.request.team_id,item.request.season_id)];if(p?.blocked)continue;
   try{const r=await rpc('apply',item.request);if(!r||!['applied','conflict','blocked','retry'].includes(r.status))throw Error('No valid server confirmation was received.');
    await S.update(u,b=>{if(r.status==='retry'){const q=b.queue.find(x=>x.id===item.id);if(q){q.next_at=Date.now()+65000;q.attempts++;}}else S.accept(b,item.id,r);},guard(u));if(r.status==='retry')break;
   }catch(e){if(!guard(u)())break;if(e.code==='42501'){await blockPack(u,S.packKey(item.request.team_id,item.request.season_id),e.message);notice(e.message,true);break;}
    await S.update(u,b=>{const q=b.queue.find(x=>x.id===item.id);if(q){q.attempts++;q.next_at=Date.now()+Math.min(300000,2000*2**Math.min(q.attempts,7));}},guard(u));if(manual)notice(e.message,true);break;}
  }};
  try{if(navigator.locks)await navigator.locks.request('wm-offline-sync:'+u,{ifAvailable:true},lock=>lock?run():undefined);else await run();if(manual)notice('Sync checked. Review Saved work for any remaining changes.');if(current()){if(!['thread','edit'].includes(view))await render();else{const latest=await S.get(u);panel.querySelectorAll('[data-queued]').forEach(el=>{const id=el.dataset.queued,q=latest.queue.find(x=>x.id===id);el.querySelector('small').textContent=q?(q.state==='pending'?'Saved on device · not sent':'Needs attention in Saved work'):'Synced to server';});const badge=panel.querySelector('.of-connection');if(badge)badge.textContent=latest.queue.length+' changes awaiting sync'+(navigator.onLine?'':' · Offline');}}}
  catch(e){if(current())notice(e.message,true);}finally{syncing=false;}
 }
 async function beforeSignOut(){const u=session?.user?.id;if(u){try{await draftFlight;}catch{message('Your draft has not saved. Return to Offline workspace before signing out.',true);return false;}let b;try{b=await S.get(u);}catch{message('Could not check saved offline work. Reopen the app before signing out.',true);return false;}if(b&&(b.queue.length||Object.keys(b.drafts).length)){message('You have saved offline work or drafts. Open Offline workspace and sync or review them before signing out.',true);return false;}}localStorage.removeItem(ACTIVE);lock();return true;}
 $('ofBack').onclick=async()=>{if(view==='home'){await draftFlight.catch(()=>{});panel.hidden=true;entry.hidden=navigator.onLine||!localStorage.getItem(ACTIVE);}else if(['attendance','edit'].includes(view))navigate('schedule');else if(view==='thread')navigate('messages');else navigate('home');};$('ofLock').onclick=async()=>{try{await draftFlight;lock();}catch{notice('Your draft has not saved. Keep this screen open and try editing it again.',true);}};pill.onclick=entry.onclick=open;
 addEventListener('online',()=>{entry.hidden=true;void sync();});addEventListener('offline',()=>{entry.hidden=!panel.hidden||!localStorage.getItem(ACTIVE);if(!panel.hidden&&current())notice('Offline. Changes save here and sync after reconnection.');});
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)void sync();});
 client.auth.onAuthStateChange((event,next)=>{if(event==='SIGNED_OUT'){localStorage.removeItem(ACTIVE);lock();}else if(owner&&next?.user?.id&&next.user.id!==owner)lock();});
 setInterval(()=>{if(unlocked&&!current())lock();else void sync();},15000);
 if(navigator.onLine&&!unavailable())navigator.serviceWorker.register('./sw.js').catch(()=>{});
 if(!navigator.onLine&&localStorage.getItem(ACTIVE)){entry.hidden=false;setTimeout(open,0);}
 return {open,lock,download,sync,beforeSignOut};
})();
