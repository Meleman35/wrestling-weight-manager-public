/* Saved per-account/team choices. This release prepares drafts; delivery is inactive. */
(function(root){
 const defaults=()=>({countdown_minutes:[],readiness:false,changes:false,revision:0,delivery_active:false});
 const sampleDefaults=()=>({countdown_minutes:[60,30,15,10,5],readiness:true,changes:true});
 function controls(p){
  return `<fieldset><legend>Estimated start reminders</legend><div class="tournament-alert-options">${[60,30,15,10,5].map(n=>`<label><input type="checkbox" data-alert-minute="${n}" ${p.countdown_minutes.includes(n)?'checked':''}> ${n} min</label>`).join('')}</div></fieldset><label class="tournament-alert-option"><input type="checkbox" data-alert-readiness ${p.readiness?'checked':''}> In the hole, on deck, up next &amp; on mat</label><label class="tournament-alert-option"><input type="checkbox" data-alert-changes ${p.changes?'checked':''}> Mat changes &amp; estimated start changes</label>`;
 }
 function read(box){return {countdown_minutes:[...box.querySelectorAll('[data-alert-minute]:checked')].map(n=>Number(n.dataset.alertMinute)),readiness:box.querySelector('[data-alert-readiness]').checked,changes:box.querySelector('[data-alert-changes]').checked};}
 async function mount({box,client,teamId,userId,isCurrent,onChange}){
  let saved=defaults(),busy=false;
  const current=()=>box.isConnected&&isCurrent();
  box.innerHTML='<details class="tournament-alert-settings"><summary>My tournament alert choices</summary><p>Delivery is not active yet. Save your choices, then try them in the sample tournament.</p><p>Choices apply to this account and team. Athlete visibility still controls what an alert may include.</p><form><div data-alert-controls></div><div class="tournament-toolbar"><button type="submit">Save choices</button><button type="button" class="secondary" data-alert-reload>Reload saved choices</button></div><p role="status" aria-live="polite" data-alert-status></p></form></details>';
  const form=box.querySelector('form'),status=box.querySelector('[data-alert-status]'),inputs=box.querySelector('[data-alert-controls]');
  const lock=disabled=>{busy=disabled;form.querySelectorAll('input,button').forEach(n=>n.disabled=disabled);};
  async function request(action){
   if(busy)return;const values=action==='save'?{...read(inputs),revision:saved.revision}:{};lock(true);status.textContent=action==='save'?'Saving choices…':'Loading choices…';
   try{
    const result=await client.rpc('tournament_alert_preferences',{p_action:action,p_data:{team_id:teamId,...values}});
    if(!current())return;if(result.error)throw new Error(result.error.message||'Could not save alert choices.');
    saved=result.data;inputs.innerHTML=controls(saved);onChange(saved);status.textContent=action==='save'?'Choices saved. Delivery is not active yet.':'Delivery is not active yet.';
   }catch(e){if(current())status.textContent=e.message;}
   finally{if(current())lock(false);}
  }
  inputs.innerHTML=controls(saved);form.onsubmit=e=>{e.preventDefault();request('save');};box.querySelector('[data-alert-reload]').onclick=()=>request('get');await request('get');
 }
 function demo(box,p,onChange){box.innerHTML='<details class="tournament-alert-settings"><summary>Sample alert choices</summary><p>Try these choices here. This does not save settings or send notifications.</p>'+controls(p)+'</details>';box.onchange=()=>onChange(read(box));}
 const api={defaults,sampleDefaults,mount,demo};root.WMTournamentAlertPreferences=api;
})(typeof window!=='undefined'?window:globalThis);
