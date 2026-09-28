/* Eligibility is independent of active team membership and practice attendance. */
window.WMEligibility=(()=>{
 'use strict';const $=id=>document.getElementById(id),E=esc;
 let generation=0,rows=new Map(),scope='',busy=false,editor=null,editorVersion=0;
 const key=()=>WMRoster.key();
 const sheet=document.createElement('section');sheet.id='eligibilitySheet';sheet.className='sheet hidden';sheet.setAttribute('role','dialog');sheet.setAttribute('aria-label','Athlete eligibility');sheet.innerHTML='<div class="sheet-head"><h2>Eligibility</h2><button type="button" class="icon-close" id="eligibilityClose" aria-label="Close eligibility">×</button></div><p id="eligibilityStatus" role="status"></p><div id="eligibilityBody"></div>';document.body.append(sheet);$('eligibilityClose').onclick=()=>closeSheets();
 function closeEditor(){editorVersion++;editor=null;busy=false;sheet.classList.add('hidden');$('eligibilityBody').replaceChildren();}
 function reset(){generation++;rows.clear();scope='';closeEditor();}
 function day(at=new Date(),tz=Intl.DateTimeFormat().resolvedOptions().timeZone){
  const parts=new Intl.DateTimeFormat('en-US',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(at));
  const val=k=>parts.find(p=>p.type===k).value;return `${val('year')}-${val('month')}-${val('day')}`;
 }
 function effective(record,at=new Date()){
  if(!record)return {};
  if(record.rules_version!==2)return {...record,practice_eligible:true};
  const d=day(at,record.timezone||'UTC'),inPeriod=(!record.restricted_from||d>=record.restricted_from)&&(!record.restricted_through||d<=record.restricted_through);
  return {...record,eligible:!inPeriod||record.competition_allowed!==false,practice_eligible:!inPeriod||record.practice_allowed!==false};
 }
 function summary(record){
  if(!record||record.rules_version!==2||(record.competition_allowed!==false&&record.practice_allowed!==false))return '';
  const d=day(new Date(),record.timezone||'UTC');
  if(record.restricted_through&&d>record.restricted_through)return 'Restriction ended '+record.restricted_through;
  const start=record.restricted_from&&d<record.restricted_from?'Starts '+record.restricted_from+' · ':'';
  return start+(record.restricted_through?'Through '+record.restricted_through:'Until cleared by coach');
 }
 async function load(){
  const g=++generation,k=key();if(scope!==k){rows.clear();scope='';WMRoster.setExtras([],k);}
  const r=await client.rpc('roster_eligibility_request',{p_action:'list',p_data:{season_id:activeSeason?.id}});
  if(g!==generation||k!==key())return;
  if(r.error){message('Competition eligibility could not load. Reopen Roster before changing eligibility.',true);return;}
  rows=new Map((r.data||[]).map(x=>[x.athlete_id,x]));scope=k;WMRoster.setExtras(r.data||[],k);renderCoachWeightClassBoard();
 }
 function change(id,record){
  if(busy||!isStaff||managedLogin||scope!==key()||!record)return;
  if(record.rules_version!==2){message('Eligibility settings are updating. Reopen Roster in a moment.',true);return;}
  const name=[...rosterRows,...rosterManagementRows].find(r=>r.athlete_id===id);
  closeEditor();const tz=record.timezone||Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';editor={id,record,key:key(),version:editorVersion,timezone:tz};
  $('eligibilityStatus').textContent='';
  $('eligibilityBody').innerHTML=`<h3>${E(name?.first_name||'')} ${E(name?.last_name||'')}</h3><form id="eligibilityForm">
   <label>Competition<select id="eligibilityCompetition"><option value="yes">Eligible</option><option value="no">Ineligible during restriction</option></select></label>
   <label>Practice<select id="eligibilityPractice"><option value="yes">Allowed</option><option value="no">Restricted by school / coach</option></select></label>
   <div id="eligibilityDates"><label>Restriction starts<input id="eligibilityFrom" type="date" value="${E(record.restricted_from||day(new Date(),tz))}"></label>
   <label>Restriction ends<select id="eligibilityEndMode"><option value="manual">When a coach clears it</option><option value="date">After a set date</option></select></label>
   <label id="eligibilityThroughLabel">Last restricted day<input id="eligibilityThrough" type="date" value="${E(record.restricted_through||'')}"></label>
   <p class="fine">Dates use ${E(tz)}. Eligibility returns the day after the last restricted day. Choose coach clearance for grade checks or other school requirements.</p></div>
   <p class="fine">Competition restrictions leave practice allowed unless you change it above. The athlete stays on the team and keeps their attendance, profile and history.</p>
   <button type="submit" class="wide">Save eligibility</button><button id="eligibilityClear" type="button" class="wide secondary">Clear restrictions</button></form>`;
  $('eligibilityCompetition').value=record.competition_allowed===false?'no':'yes';$('eligibilityPractice').value=record.practice_allowed===false?'no':'yes';$('eligibilityEndMode').value=record.restricted_through?'date':'manual';
  function sync(){const restricted=$('eligibilityCompetition').value==='no'||$('eligibilityPractice').value==='no',dated=restricted&&$('eligibilityEndMode').value==='date';$('eligibilityDates').hidden=!restricted;$('eligibilityFrom').required=restricted;$('eligibilityThroughLabel').hidden=!dated;$('eligibilityThrough').required=dated;$('eligibilityThrough').min=$('eligibilityFrom').value;}
  for(const id of ['eligibilityCompetition','eligibilityPractice','eligibilityEndMode','eligibilityFrom'])$(id).onchange=sync;
  $('eligibilityClear').onclick=()=>{if(busy)return;$('eligibilityCompetition').value='yes';$('eligibilityPractice').value='yes';sync();$('eligibilityForm').requestSubmit();};
  $('eligibilityForm').onsubmit=save;sync();openSheet(sheet.id);
 }
 async function save(ev){
  ev.preventDefault();if(busy||!editor||editor.key!==key()||managedLogin||!isStaff)return;
  const state=editor,version=editorVersion,valid=()=>editorVersion===version&&editor===state&&state.key===key()&&!sheet.classList.contains('hidden');
  const eligible=$('eligibilityCompetition').value==='yes',practice=$('eligibilityPractice').value==='yes',restricted=!eligible||!practice;
  const from=restricted?$('eligibilityFrom').value:null,through=restricted&&$('eligibilityEndMode').value==='date'?$('eligibilityThrough').value:null;
  if(restricted&&(!from||($('eligibilityEndMode').value==='date'&&!through))){$('eligibilityStatus').textContent='Choose the restriction dates.';return;}
  if(through&&through<from){$('eligibilityStatus').textContent='The last restricted day must be on or after the start.';return;}
  busy=true;ev.currentTarget.querySelectorAll('button,input,select').forEach(b=>b.disabled=true);$('eligibilityStatus').textContent='Saving eligibility…';
  try{
   const r=await client.rpc('roster_eligibility_request',{p_action:'save',p_data:{season_id:activeSeason.id,athlete_id:state.id,eligible,practice_allowed:practice,restricted_from:from,restricted_through:through,timezone:state.timezone,revision:state.record.revision,rules_version:2}});
   if(!valid())return;if(r.error)throw r.error;await load();if(!valid())return;
   editor.record=rows.get(state.id)||r.data;$('eligibilityStatus').textContent=restricted?'Eligibility restrictions saved.':'Competition and practice eligibility restored.';
  }catch(e){if(valid())$('eligibilityStatus').textContent=e.message;}
  finally{if(valid()){busy=false;$('eligibilityForm').querySelectorAll('button,input,select').forEach(b=>b.disabled=false);}}
 }
 // Use the scheduled event date, not today's status, for upcoming competition lists.
 function forEvent(list,event){
  const active=WMRoster.activeRows(list);if(scope!==key())return active;
  const competition=['dual','tournament','wrestle_off'].includes(event?.event_type),practice=['practice','open_mat','camp'].includes(event?.event_type);
  return active.filter(r=>{const e=effective(rows.get(r.athlete_id),event?.starts_at||new Date());return competition?e.eligible!==false:practice?e.practice_eligible!==false:true;});
 }
 // Refresh computed date boundaries without writing or relying on a scheduled job.
 function refresh(){if(scope===key()&&isStaff&&!document.hidden){WMRoster.setExtras([...rows.values()],scope);renderCoachWeightClassBoard();}}
 document.addEventListener('visibilitychange',refresh);setInterval(refresh,60000);
 return {load,change,reset,forEvent,effective,summary,closeEditor};
})();
