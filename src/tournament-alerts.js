/* Pure simulation reducer. No push, notification writes, polling or provider calls. */
(function(root){
 const active=new Set(['queued','in_hole','on_deck','up_next','on_mat']);
 const labels={in_hole:'In the hole',on_deck:'On deck',up_next:'Up next',on_mat:'On mat'};
 function step(prior,rows,now,preferences){
  const prefs=preferences||{countdown_minutes:[60,30,15,10,5],readiness:true,changes:true};
  const state=JSON.parse(JSON.stringify(prior||{})),alerts=[];
  for(const row of rows){
   const id=row.id,stamp=Date.parse(row.updated_at),version=row.revision||0;
   if(!id||!Number.isFinite(stamp))continue;
   const old=state[id];if(old&&(version<old.version||stamp<old.stamp))continue;
   const s=state[id]=old||{seen:{},version:0,stamp:0};
   const emit=(key,body,enabled=true)=>{if(!s.seen[key]){s.seen[key]=true;if(enabled)alerts.push({bout_id:id,kind:key,body});}};
   const where=`Bout ${row.bout_number} · ${row.mat?'Mat '+row.mat:'Mat pending'}`;
   const fresh=now-stamp<=600000&&stamp<=now+60000&&!row.stale;
   if(fresh&&(row.visibility==='mat_only'||active.has(row.status))){
    if(old&&s.mat!==row.mat)emit('mat:'+version+':'+stamp,where+' · Mat assignment changed',prefs.changes);
    // Mat-only projection intentionally carries no status, ETA, opponent or bracket.
    if(row.visibility!=='mat_only'&&active.has(row.status)){
     if(labels[row.status])emit('status:'+row.status,where+' · '+labels[row.status],prefs.readiness);
     const eta=Date.parse(row.estimated_start),minutes=(eta-now)/60000;
     if(old&&Number.isFinite(eta)&&s.eta&&Math.abs(eta-s.eta)>=120000)emit('reschedule:'+version+':'+stamp,where+' · Estimated start changed',prefs.changes);
     if(row.status!=='on_mat'&&Number.isFinite(minutes)&&minutes>=0){
      const threshold=[5,10,15,30,60].find(t=>minutes<=t&&prefs.countdown_minutes.includes(t));
      if(threshold)emit('minutes:'+threshold,where+' · About '+Math.max(1,Math.ceil(minutes))+' minutes');
      for(const t of [5,10,15,30,60])if(t>=minutes)s.seen['minutes:'+t]=true;
     }
    }
   }
   Object.assign(s,{version,stamp,mat:row.mat,eta:Date.parse(row.estimated_start)||null,status:row.status});
  }
  return {state,alerts};
 }
 const api={step};root.WMTournamentAlerts=api;if(typeof module!=='undefined')module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
