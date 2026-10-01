"""Prepare trainer-filtered health navigation, embed workspace, and check source consistency."""
from pathlib import Path
import sys,subprocess
root=Path(__file__).resolve().parents[1];p=root/'src/athlete-health.js';s=p.read_text();check='--check' in sys.argv
marker='/* Trainer Dashboard filters v1. */\n'
if not s.startswith(marker):
 def replace(old,new):
  global s
  if s.count(old)!=1:raise RuntimeError('Unexpected health source: '+old[:80])
  s=s.replace(old,new,1)
 replace("let epoch=0,owner=''", "let rosterFilter='all',epoch=0,owner=''")
 replace("function reset(){epoch++;owner='';", "function reset(){epoch++;rosterFilter='all';owner='';")
 replace("async function open(){", "async function open(options={}){")
 replace("reset();owner=actor();$h('healthSubtitle')", "reset();rosterFilter=['all','awaiting','restricted','due','baseline'].includes(options?.filter)?options.filter:'all';owner=actor();$h('healthSubtitle')")
 replace("<div id=\"healthRoster\"></div>", "${state.trainer?'<label for=\"healthFilter\">Show athletes</label><select id=\"healthFilter\"><option value=\"all\">All athletes</option><option value=\"awaiting\">Awaiting trainer review</option><option value=\"restricted\">Recorded activity restrictions</option><option value=\"due\">Reviews due</option><option value=\"baseline\">Missing required baselines</option></select>':''}<div id=\"healthRoster\"></div>")
 replace("$h('healthSearch').oninput=renderRoster;", "if(!state.trainer)rosterFilter='all';if($h('healthFilter')){$h('healthFilter').value=rosterFilter;$h('healthFilter').onchange=()=>{rosterFilter=$h('healthFilter').value;renderRoster()}}\n  $h('healthSearch').oninput=renderRoster;")
 replace("rows=state.athletes.filter(a=>a.name.toLowerCase().includes(q));", "rows=state.athletes.filter(a=>a.name.toLowerCase().includes(q)&&(!state.trainer||!window.WMTrainerDashboard||window.WMTrainerDashboard.matches(a,rosterFilter,today(),state.baseline_required)));")
 s=marker+s
if check:assert p.read_text()==s,'Health filter source differs'
else:p.write_text(s)
for script in ['patch-athlete-health.py','patch-trainer-dashboard.py']:
 subprocess.run([sys.executable,str(root/'scripts'/script)]+(['--check'] if check else []),cwd=root,check=True)
print('PASS Trainer workspace source preparation')
