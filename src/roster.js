/* Roster presentation only: membership and history remain server-owned. */
window.WMRoster = (() => {
 'use strict';
 const $=id=>document.getElementById(id), E=esc;
 let sort='last', context='', extras=new Map(),photos=new Map();
 const inactive=r=>r.active===false||['standby','removed','inactive'].includes(r.roster_status);
 const key=()=>`${session?.user?.id||''}:${activeTeam?.id||''}:${activeSeason?.id||''}`;
 function compare(a,b){
  if(sort==='weight'){
   const weight=r=>r.current_lineup_class==null||r.current_lineup_class===''||!Number.isFinite(Number(r.current_lineup_class))?Infinity:Number(r.current_lineup_class);
   const aw=weight(a),bw=weight(b);
   if(aw!==bw)return aw-bw;
  }
  const name=r=>sort==='first'?`${r.first_name||''} ${r.last_name||''}`:`${r.last_name||''} ${r.first_name||''}`;
  return name(a).localeCompare(name(b),undefined,{numeric:true,sensitivity:'base'})||String(a.athlete_id).localeCompare(String(b.athlete_id));
 }
 const button=(label,attrs)=>`<button type="button" class="roster-access-btn" ${attrs}>${E(label)}</button>`;
 function row(r,off=false){
  const id=E(r.athlete_id), extra=window.WMEligibility?.effective(extras.get(r.athlete_id))||extras.get(r.athlete_id)||{};
  return `<div class="roster-card${off?' roster-muted-card':''}" data-roster-athlete="${id}">
   <div class="roster-identity"><span class="roster-avatar" data-roster-photo="${id}" aria-hidden="true">${E((r.first_name||'')[0]||'')}${E((r.last_name||'')[0]||'')}</span><button class="roster-name-link" type="button" data-view-athlete="${id}">${E(r.first_name)} ${E(r.last_name)}</button><small>${E(rosterStatusLabel(r.roster_status))}</small><small>Class ${E(r.current_lineup_class==null?'—':displayTeamWeightClass(r.current_lineup_class))}</small>${extra.eligible===false?'<small class="roster-ineligible">Ineligible for competition</small>':''}${extra.practice_eligible===false?'<small class="roster-ineligible">Practice restricted</small>':''}${window.WMEligibility?.summary(extra)?`<small>${E(WMEligibility.summary(extra))}</small>`:''}</div>
   <div class="roster-actions" tabindex="0" role="region" aria-label="Controls for ${E(r.first_name)} ${E(r.last_name)}">
    ${button('View profile',`data-view-athlete="${id}"`)}${button('Edit Profile',`data-profile-athlete="${id}"`)}
    ${!off?button(r.current_lineup_class==null?'Set Class':'Change Class',`data-set-lineup-class="${id}"`):''}
    ${r.latest_weight!=null?`<div class="weight-value">${E(r.latest_weight)}<small>Latest lb</small></div>`:''}${r.eligible_weight_class!=null?`<small class="roster-status-note">Weight certification: ${E(displayTeamWeightClass(r.eligible_weight_class))}</small>`:''}
    ${!off&&window.WMAttendance?button('Attendance',`data-roster-attendance="${id}"`):''}
    ${window.WMEligibility?button('Eligibility',`data-eligibility-athlete="${id}" ${extra.revision==null?'disabled':''}`):''}
    ${isTeamAdmin?button('Teams / Transfer',`data-athlete-teams="${id}"`):''}
    ${!off?button('Invite',`data-access-athlete="${id}"`):''}
    ${off?button('Reactivate',`data-team-status="active" data-status-athlete="${id}"`):rosterManageButtons(r.athlete_id)}
    ${r.status_reason?`<small class="roster-status-note">${E(r.status_reason)}</small>`:''}
   </div></div>`;
 }
 function bind(box){
  for(const [attr,fn] of [['view-athlete',openAthleteOverview],['profile-athlete',openAthleteProfile],['set-lineup-class',openLineupClassSheet],['athlete-teams',openAthleteTeams],['access-athlete',openAthleteAccess]])box.querySelectorAll(`[data-${attr}]`).forEach(b=>b.onclick=()=>fn(b.getAttribute('data-'+attr)));
  box.querySelectorAll('[data-roster-attendance]').forEach(b=>b.onclick=()=>WMAttendance.open(b.dataset.rosterAttendance));
  box.querySelectorAll('[data-eligibility-athlete]').forEach(b=>b.onclick=()=>WMEligibility.change(b.dataset.eligibilityAthlete,extras.get(b.dataset.eligibilityAthlete)));
  bindRosterManagementActions(box);
 }
 function render(){
  if(!isStaff)return;
  $('rosterSheet').classList.remove('family-profile-picker');
  if(context!==key()){context=key();extras.clear();photos.clear();try{sort=localStorage.getItem('wm-roster-sort:'+context)||'last';}catch{sort='last';}if(!['first','last','weight'].includes(sort))sort='last';$('inactiveRosterSection').open=false;}
  $('rosterSort').value=sort;
  const manage=new Map(rosterManagementRows.map(r=>[r.athlete_id,r]));
  const active=rosterRows.filter(r=>!inactive({...r,...manage.get(r.athlete_id)})).map(r=>({...r,...manage.get(r.athlete_id)})).sort(compare);
  const eligible=r=>(window.WMEligibility?.effective(extras.get(r.athlete_id))||extras.get(r.athlete_id))?.eligible!==false;
  const competition=active.filter(eligible),ineligible=active.filter(r=>!eligible(r));
  $('rosterList').innerHTML=competition.map(r=>row(r)).join('')||'<div class="empty-card">No active competition athletes.</div>';
  $('rosterActiveCount').textContent=`${competition.length} athlete${competition.length===1?'':'s'}`;
  const off=rosterManagementRows.filter(inactive).sort(compare);
  $('inactiveRosterSection').classList.toggle('hidden',!isTeamAdmin);
  $('inactiveRosterSummary').textContent=`Standby / Removed (${off.length})`;
  $('inactiveRosterList').innerHTML=off.map(r=>row(r,true)).join('')||'<div class="empty-card">No athletes on standby or removed.</div>';
  if($('ineligibleRosterList')){
   $('ineligibleRosterSection').classList.toggle('hidden',!ineligible.length);
   $('ineligibleRosterSummary').textContent=`Ineligible for competition (${ineligible.length})`;
   $('ineligibleRosterList').innerHTML=ineligible.map(r=>row(r)).join('');bind($('ineligibleRosterList'));
  }
  bind($('rosterList'));bind($('inactiveRosterList'));
  const expected=key();document.querySelectorAll('[data-roster-photo]').forEach(async el=>{const path=extras.get(el.dataset.rosterPhoto)?.photo_path;if(!path)return;try{if(!photos.has(path))photos.set(path,athletePhotoUrl(path));const url=await photos.get(path);if(url&&expected===key()&&el.isConnected){const img=document.createElement('img');img.src=url;img.alt='';el.replaceChildren(img);}}catch{}});
 }
 function setExtras(rows,expected){if(expected!==key())return;extras=new Map(rows.map(r=>[r.athlete_id,r]));render();}
 $('rosterBtn').addEventListener('click',()=>render());
 $('rosterSort').onchange=()=>{sort=$('rosterSort').value;try{localStorage.setItem('wm-roster-sort:'+key(),sort);}catch{}render();};
 function activeRows(list=rosterRows){const manage=new Map(rosterManagementRows.map(r=>[r.athlete_id,r]));return list.filter(r=>!inactive({...r,...manage.get(r.athlete_id)})).sort(compare);}
 return {render,key,setExtras,compare,activeRows};
})();
