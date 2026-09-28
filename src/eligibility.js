window.WMEligibility=(()=>{
 'use strict';let generation=0,rows=new Map(),scope='',busy=false;
 const key=()=>WMRoster.key();
 function reset(){generation++;rows.clear();scope='';busy=false;}
 async function load(){
  const g=++generation,k=key();rows.clear();scope='';WMRoster.setExtras([],k);
  const r=await client.rpc('roster_eligibility_request',{p_action:'list',p_data:{season_id:activeSeason?.id}});
  if(g!==generation||k!==key())return;
  if(r.error){message('Competition eligibility could not load. Reopen Roster before changing eligibility.',true);return;}
  rows=new Map((r.data||[]).map(x=>[x.athlete_id,x]));scope=k;WMRoster.setExtras(r.data||[],k);renderCoachWeightClassBoard();
 }
 async function change(id,record){
  if(busy||!isStaff||managedLogin||scope!==key()||!record)return;
  const eligible=record.eligible===false,name=[...rosterRows,...rosterManagementRows].find(r=>r.athlete_id===id);
  if(!confirm(`${eligible?'Restore competition eligibility for':'Mark ineligible for competition:'} ${name?.first_name||''} ${name?.last_name||''}?\n\nThe profile, history, practice attendance and family access stay intact.`))return;
  busy=true;const k=key();
  try{const r=await client.rpc('roster_eligibility_request',{p_action:'save',p_data:{season_id:activeSeason.id,athlete_id:id,eligible,revision:record.revision}});if(k!==key())return;if(r.error)throw r.error;await load();message(eligible?'Competition eligibility restored.':'Athlete moved out of the active competition roster.');}
  catch(e){if(k===key())message(e.message,true);}finally{busy=false;}
 }
 // These are presentation lists only; practice/weight/family rosters stay complete.
 function forEvent(list,event){return ['dual','tournament','wrestle_off'].includes(event?.event_type)&&scope===key()?list.filter(r=>rows.get(r.athlete_id)?.eligible!==false):list;}
 return {load,change,reset,forEvent};
})();
