/* Deterministic reports from saved scorebooks. No network, credentials or writes. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.WMStatisticsEngine=api;})(typeof globalThis!=='undefined'?globalThis:this,()=>{
 const styles={folkstyle:'Folkstyle',freestyle:'Freestyle',greco:'Greco-Roman',beach:'Beach'};
 const labels={td:'Takedowns',escape:'Escapes',reversal:'Reversals',nearfall:'Near falls',hold2:'Two-point holds',action4:'Four-point actions',action5:'Five-point actions',exposure:'Exposures',stepout:'Step outs',penalty:'Penalty points',locked:'Locked-hands awards',activity:'Activity points',utb_rideout:'Tiebreaker ride-outs',beach1:'Ground contacts',beach3:'Back-exposure throws',beachout:'Out of bounds',beachcaution:'Caution points',beachchallenge:'Challenge points',correction:'Score adjustments',unclassified:'Other recorded points'};
 const pair=()=>({for:0,against:0,pointsFor:0,pointsAgainst:0});
 const int=n=>Number.isInteger(n)&&Math.abs(n)<=99;
 function report(rows,{teamId,athleteIds,style,seasonId=null}={}){
  if(!teamId||!Array.isArray(athleteIds)||!athleteIds.length||!Object.hasOwn(styles,style))throw Error('Choose a team, wrestler and wrestling style.');
  const ids=new Set(athleteIds),unique=new Map();
  for(const r of rows||[]){if(!r||!r.id||r.team_id!==teamId)continue;const prior=unique.get(r.id);if(!prior||Number(r.revision||0)>Number(prior.revision||0))unique.set(r.id,r);}
  const out={matches:0,wins:0,losses:0,noContest:0,pointsFor:0,pointsAgainst:0,winPercent:null,averageFor:null,averageAgainst:null,actions:Object.create(null),periods:Object.create(null),positions:{neutral:pair(),top:pair(),bottom:pair(),grounded:pair(),unknown:pair()},results:Object.create(null),history:[],excluded:0,unclassifiedPoints:0};
  for(const r of unique.values()){
   const d=r.data||{};if(d.style!==style||seasonId&&r.season_id!==seasonId)continue;
   if(d.status!=='complete'||d.video_test||d.test_only||d.demo||r.challenge_id||(d.book_type&&d.book_type!=='competition')){out.excluded++;continue;}
   const red=ids.has(d.red_id),other=ids.has(d.other_id);if(red===other||!Array.isArray(d.ledger)||!['red','other','none'].includes(d.winner)){out.excluded++;continue;}
   const own=red?'red':'other',opp=red?'other':'red',ledger=d.ledger.filter(a=>a&&a.voided!==true);
   if(ledger.some(a=>['red','other'].includes(a.corner)&&!int(a.points??0))){out.excluded++;continue;}
   const score={red:0,other:0};for(const a of ledger)if(['red','other'].includes(a.corner))score[a.corner]+=a.points||0;
   if(score.red<0||score.other<0){out.excluded++;continue;}
   const noContest=d.winner==='none'||d.result==='No contest',win=!noContest&&d.winner===own;
   out.matches++;out[noContest?'noContest':win?'wins':'losses']++;out.pointsFor+=score[own];out.pointsAgainst+=score[opp];
   const result=String(d.result||'Unspecified');out.results[result]??=pair();out.results[result][win?'for':'against']+=noContest?0:1;
   let position=d.flowVersion?'neutral':'unknown';const seen=new Set();
   for(const a of ledger){
    const points=a.points||0;
    if(['red','other'].includes(a.corner)&&points!==0){
     const side=a.corner===own?'for':'against',ps=side==='for'?'pointsFor':'pointsAgainst';
     let action=/^nf[2345]$/.test(a.action_id||'')||a.action_id==='stoppage'?'nearfall':Object.hasOwn(labels,a.action_id)?a.action_id:'unclassified';
     out.actions[action]??=pair();out.actions[action][ps]+=points;
     // A stoppage adjustment augments the original near-fall award, not a second near fall.
     if(points>0&&action!=='correction'&&!(a.adjusts&&seen.has(a.adjusts)))out.actions[action][side]++;
     if(action==='unclassified')out.unclassifiedPoints+=Math.abs(points);
     const period=Number.isInteger(a.period)&&a.period>0&&a.period<=30?String(a.period):'Unknown';
     out.periods[period]??=pair();out.periods[period][ps]+=points;
     const pos=position==='neutral'?'neutral':position===own?'top':position===opp?'bottom':position==='grounded'?'grounded':'unknown';out.positions[pos][ps]+=points;
    }
    if(a.id)seen.add(a.id);
    if(['neutral','red','other','grounded','unknown'].includes(a.position_after))position=a.position_after;
   }
   out.history.push({id:r.id,source:r.source,seasonId:r.season_id,date:r.created_at,opponent:red?d.other_name:d.red_name,label:d.label||'',bout:d.bout_number||'',result,win:noContest?null:win,pointsFor:score[own],pointsAgainst:score[opp]});
  }
  const decisions=out.wins+out.losses;out.winPercent=decisions?100*out.wins/decisions:null;
  if(out.matches){out.averageFor=out.pointsFor/out.matches;out.averageAgainst=out.pointsAgainst/out.matches;}
  out.history.sort((a,b)=>String(b.date||'').localeCompare(String(a.date||''))||a.id.localeCompare(b.id));return out;
 }
 function csv(report){const quote=x=>'"'+String(x??'').replace(/^[=+@\-\t\r]/,"'$&").replace(/"/g,'""')+'"';return [['Date','Opponent','Event','Bout','Result','Outcome','Points for','Points against'],...report.history.map(r=>[r.date,r.opponent,r.label,r.bout,r.result,r.win===null?'No contest':r.win?'Win':'Loss',r.pointsFor,r.pointsAgainst])].map(r=>r.map(quote).join(',')).join('\r\n');}
 return {styles,labels,report,csv};
});
