"""Small, idempotent Match Book hooks; preserve held branches and standalone Mat Mode."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html'; s=p.read_text()
def change(old,new):
 global s
 if new in s: return
 assert old in s, old[:100]
 s=s.replace(old,new,1)
change("async function activateTeam(teamId,{persist=true}={}){", "async function activateTeam(teamId,{persist=true}={}){\n  window.WMVideoPilot?.reset();")
change("if(session?.user?.id!==nextSession?.user?.id){", "if(session?.user?.id!==nextSession?.user?.id){window.WMVideoPilot?.reset();")
change("function persist(){if(!match||!owner||!team)return;try{localStorage.setItem(key()", "function persist(){if(!match||!owner||!team)return;window.WMVideoPilot?.onScore(videoSnapshot());try{localStorage.setItem(key()")
change("timer=setInterval(tick,100);persist();}", "timer=setInterval(tick,100);persist();window.WMVideoPilot?.sync();}")
change("openSheet('matchListSheet');el('matchListStatus')", "openSheet('matchListSheet');window.WMVideoPilot?.sync();el('matchListStatus')")
change("function close(){version++;if(match)", "function close(){window.WMVideoPilot?.leaving();version++;if(match)")
change("async function nextMatch(){if(!validContext()||busy)return;", "async function nextMatch(){if(!validContext()||busy)return;if(window.WMVideoPilot?.active()){status('Stop and save the video before opening the next match.',true);return;}")
if "function videoSnapshot()" not in s:
 change("return{open,close,parseTime,remaining,scores};", """function videoSnapshot(){
   if(!validContext())return null;
   const state={id:match.id,red_id:match.red_id,other_id:match.other_id,red_name:match.red_name,other_name:match.other_name,
    style:match.style,book_type:match.book_type,status:match.status,period:match.period,phase:match.phase,
    phaseLabel:match.phase==='timeout'?match.timeoutLabel:match.phase==='break'?'Break':'Period '+(match.period+1),
    remainingMs:remaining(),running:match.deadline!==null,ledger:structuredClone(match.ledger)};
   state.token=JSON.stringify([match.id,match.ledger,match.period,match.phase,match.remainingMs,match.deadline,match.status,match.red_name,match.other_name]);
   return state;
  }
  return{open,close,parseTime,remaining,scores,videoSnapshot};""")
# Normalize only our role hooks, including earlier draft revisions.
s=re.sub(r"function applyRoleUI\(\)\{\n(?:  (?:setTimeout\(\(\)=>window\.WMMatchVideo\?\.sync\(\),0\);|window\.WMVideoPilot\?\.reset\(\);(?:window\.WMMatchVideo\?\.reset\(\);)?)\n)*", "function applyRoleUI(){\n  window.WMVideoPilot?.reset();window.WMMatchVideo?.reset();\n  setTimeout(()=>window.WMMatchVideo?.sync(),0);\n", s)
# Athlete entry points and a scoped scoring save path; existing scoring engine stays intact.
change("  closeSheets();openSheet('athleteViewSheet');", "  closeSheets();openSheet('athleteViewSheet');window.WMMatchVideo?.profile(athleteId);")
change("  closeSheets();openSheet('athleteProfileSheet');", "  closeSheets();openSheet('athleteProfileSheet');window.WMMatchVideo?.profile(athleteId,'athleteProfileSheet');")
change("const row=await WMOperations.rpc(true,{action:'match',id:match.id,team_id:team,season_id:season,challenge_id:challenge,revision,data});", "const row=match.bout_id?await WMMatchVideo.rpc('save',{id:match.id,revision,data}):await WMOperations.rpc(true,{action:'match',id:match.id,team_id:team,season_id:season,challenge_id:challenge,revision,data});")
change("const state={id:match.id,red_id:match.red_id", "const state={id:match.id,bout_id:match.bout_id,event_id:match.event_id,athlete_id:match.athlete_id,bout_number:match.bout_number,red_id:match.red_id")
change("return{open,close,parseTime,remaining,scores,videoSnapshot};", """async function openVideo(row){
  if(window.WMVideoPilot?.active())return;
  closeSheets();owner=session?.user?.id;team=activeTeam?.id;
  if(!owner||!team||managedLogin||row.team_id!==team)return;
  await showScore(row);await window.WMVideoPilot?.sync();
 }
 return{open,openVideo,close,parseTime,remaining,scores,videoSnapshot};""")
# Team-member scorebooks route to scoped recording actions, not coach-only operations.
change("A personal team coach or administrator must score matches.", "Use your personal team account to score and record matches.")
change("return;}closeSheets();owner=session?.user?.id;team=activeTeam?.id;season=activeSeason?.id||null;", "return;}if(!actualIsStaff){try{return await WMMatchVideo.scorebook();}catch(err){message(err.message,true);return;}}closeSheets();owner=session?.user?.id;team=activeTeam?.id;season=activeSeason?.id||null;")
change("async function save(){if(!validContext()||busy)return false;busy=true;", "async function save(){if(!validContext()||busy)return false;if(match.video_test===true){persist();status('Test score saved on this device.');return true;}busy=true;")
change("return;}const source=match;pause();if(!await WMOperations.confirmAction('Save this match and open setup for the next bout?", "return;}if(!actualIsStaff&&(match.bout_id||match.video_test)){if(await save())await WMMatchVideo.scorebook();return;}const source=match;pause();if(!await WMOperations.confirmAction('Save this match and open setup for the next bout?")
# A fall is an explicit final result, separate from injury-stoppage scoring.
change("el('matchImminent').hidden=!match.nfhs;", "el('matchImminent').hidden=!match.nfhs||match.status==='complete'||match.phase!=='timeout'||!['Injury','HNC'].includes(match.timeoutInfo?.type);")
change("Referee award · injury stopped scoring", "Injury stoppage · record awarded points")
change("${e(label.replace(/ · \\d$/,''))}${typeof points==='number'&&points>0?' +'+points:''}</button>`).join('')}</div></div>`).join('');", "${e(label.replace(/ · \\d$/,''))}${typeof points==='number'&&points>0?' +'+points:''}</button>`).join('')}</div>${match.style!=='beach'?`<button type=\"button\" class=\"match-fall-button\" data-fall=\"${c}\" ${match.status==='complete'?'disabled':''}>Fall / pin</button>`:''}</div>`).join('');")
change("el('matchCorners').querySelectorAll('[data-award]').forEach(b=>b.onclick=()=>award(b.dataset.corner,b.dataset.award));", "el('matchCorners').querySelectorAll('[data-award]').forEach(b=>b.onclick=()=>award(b.dataset.corner,b.dataset.award));\n  el('matchCorners').querySelectorAll('[data-fall]').forEach(b=>b.onclick=()=>finish(b.dataset.fall,'Fall'));")
change("async function finish(){if(!validContext()||match.status==='complete')return;pause();const answer=", "async function finish(selectedWinner=null,selectedResult=null){if(!validContext()||match.status==='complete')return;const source=match;pause();const answer=")
change("value:scores().other>scores().red?'other':'red'},{id:'result'", "value:['red','other'].includes(selectedWinner)?selectedWinner:scores().other>scores().red?'other':'red'},{id:'result'")
change("value:match.style==='beach'?'Points / tie criteria':'Decision'}],submit:'Save final result'});if(!answer||!validContext())return;", "value:match.style==='beach'?'Points / tie criteria':selectedResult==='Fall'?'Fall':'Decision'}],submit:'Save final result'});if(!answer||source!==match||!validContext())return;")
# Surface the existing NFHS overtime stages; only the presentation changes.
change("el('matchAdvance').disabled=match.status==='complete';}", "el('matchAdvance').disabled=match.status==='complete';const nextOT=match.nfhs?WMNFHS.stages[match.nfhsOT?.length||0]:null;el('matchOvertime').textContent=match.nfhs?(nextOT?nextOT.label+' (OT)':'Overtime complete'):'Add overtime';const sc=scores();window.WMVideoUI?.overtime(!!nextOT&&match.status!=='complete'&&match.phase==='period'&&remaining()<=0&&match.period===match.periods.length-1&&match.periods.length===3+(match.nfhsOT?.length||0)&&(nextOT.key==='tb2'||sc.red===sc.other));}")
for name in ['video-pilot-core','video-upload','video-workspace','video-pilot','video-pilot-native','match-video']:
 tag='<script id="wm-'+name+'-046">\n'+(root/f'src/{name}.js').read_text()+'\n</script>'
 s=re.sub(r'\n*<script id="wm-'+name+r'-046">.*?</script>\n*','',s,flags=re.S)
 s=s.replace('</body>',tag+'\n</body>')
tag='<style id="wm-video-pilot-046">\n'+(root/'src/video-pilot.css').read_text()+'\n</style>'
s=re.sub(r'<style id="wm-video-pilot-046">.*?</style>\n*','',s,flags=re.S)
s=s.replace('</head>',tag+'\n</head>');p.write_text(s)
print('Embedded guarded Video Pilot; release label preserved.')
