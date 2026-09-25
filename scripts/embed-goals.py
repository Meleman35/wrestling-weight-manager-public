"""Embed the 0.20.40 goals module into verified 0.20.39."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1];p=root/'index.html';s=p.read_text();marker='/* Team goals 0.20.';a=s.index(marker);b=s.index('</script>',a)
first='/* Team goals 0.20.40:' not in s
if first:assert hashlib.sha256(s.encode()).hexdigest()=='12a778f419edd26600079ad1307c84602ed84ef7081bfda1546cfdd8a1a0ea64'
s=s[:a]+(root/'src/athlete-goals.js').read_text()+'\n'+s[b:]
if first:
 s=s.replace('v0.20.39','v0.20.40').replace('Private board/club ballots and deletable test meetings.','Goal accomplishments, replacements, Locker Room goals and parent-approved profile sharing.',1)
 target='<button type="button" class="locker-room-tab" data-locker-section="team" role="tab" aria-selected="false">👥 Team</button>'
 assert target in s;s=s.replace(target,target+'\n          <button id="lockerGoalsTab" type="button" class="locker-room-tab" data-locker-section="goals" role="tab" aria-selected="false">🎯 Goals</button>',1)
 target='<div id="lockerBoardPane"';assert target in s;s=s.replace(target,'<section id="lockerGoalsPane" class="locker-pane wp-panel hidden" data-locker-pane="goals"><h3 id="lockerGoalsTitle">Goals</h3><p id="lockerGoalsStatus" role="status" aria-live="polite"></p><div id="lockerGoalsBody"></div></section>\n        '+target,1)
 s=s.replace("const next=['board','trophy','team'].includes(name)?name:'board';", "const next=['board','trophy','team','goals'].includes(name)&&!(name==='goals'&&managedLogin)?name:'board';",1)
 s=s.replace("if(next==='team')renderLockerTeamPreview();", "if(next==='team')renderLockerTeamPreview();\n  if(next==='goals')window.WMGoals?.locker();else window.WMGoals?.leaveLocker();",1)
 s=s.replace("show('teamGoalsBtn',!managedLogin&&!!activeTeam);", "show('teamGoalsBtn',!managedLogin&&!!activeTeam);show('lockerGoalsTab',!managedLogin&&!!activeTeam);",1)
 s=s.replace(" ${Array.isArray(d.results)&&d.results.length?", " ${window.WMGoals?.sharedProfile(p.shared_goals||[])||''}\n ${Array.isArray(d.results)&&d.results.length?",1)
 s=s.replace('.locker-room-tabs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));', '.locker-room-tabs{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));',1)
 css='''<style id="goals040Style">.goal-star{color:#b67700}.goal-celebration{display:flex;align-items:center;gap:16px;margin:16px 0;padding:18px;border:1px solid #e5b545;border-radius:18px;background:#fff8df;color:#583d08}.goal-celebration>span{font-size:42px;animation:goal-star-pop .45s ease-out}.goal-celebration p{margin:5px 0 0;white-space:pre-wrap}.goal-history,.goal-profile-sharing{margin:24px 0}.goal-card [readonly]{background:#f6f8fa;color:#475467}.goal-card [data-goal-replace]{margin-top:10px}#lockerGoalsPane label{display:flex;flex-direction:column;gap:7px;margin:10px 0}#lockerGoalsPane .toggle-row{flex-direction:row}#lockerGoalsStatus:not(:empty){padding:10px;border:1px solid var(--line);border-radius:10px}#lockerGoalsPane .goal-text{white-space:pre-wrap;overflow-wrap:anywhere}@keyframes goal-star-pop{from{transform:scale(.65)}to{transform:scale(1)}}@media(prefers-reduced-motion:reduce){.goal-celebration>span{animation:none}}@media(max-width:430px){.locker-room-tab{font-size:11px!important;padding:11px 3px!important}}</style>'''
 s=s.replace('/* Team goals 0.20.40:', '/* Team goals 0.20.40:',1)
 anchor='<script>\n/* Team goals 0.20.40:';assert anchor in s;s=s.replace(anchor,css+'\n'+anchor,1)
p.write_text(s)
