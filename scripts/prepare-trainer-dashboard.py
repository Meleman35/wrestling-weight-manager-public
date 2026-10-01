"""Prepare trainer-filtered health navigation and reproducible web release 0.20.112."""
from pathlib import Path
import sys,subprocess
root=Path(__file__).resolve().parents[1];p=root/'src/athlete-health.js';s=p.read_text();check='--check' in sys.argv
marker='/* Trainer Dashboard filters v1. */\n'
def put(path,text):
 target=root/path
 if check:assert target.read_text()==text,'Generated source differs: '+path
 else:target.write_text(text)
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
put('src/athlete-health.js',s)
# Field names checked against the hosted public.team_events schema, without reading events.
for path in ['src/trainer-dashboard.js','tests/trainer-dashboard-browser.cjs']:
 text=(root/path).read_text().replace('starts_at,ends_at,location','starts_at,ends_at,location_name')
 text=text.replace('location_name_name','location_name').replace("location:'Wrestling room'","location_name:'Wrestling room'").replace('e.location?', 'e.location_name?').replace('esc(e.location)', 'esc(e.location_name)')
 put(path,text)
for script in ['patch-athlete-health.py','patch-trainer-dashboard.py']:
 subprocess.run([sys.executable,str(root/'scripts'/script)]+(['--check'] if check else []),cwd=root,check=True)
for path in ['index.html','sw.js']:
 text=(root/path).read_text().replace('0.20.111','0.20.112')
 if path=='index.html':text=text.replace('Native Mat Mode entry and a clear empty saved-bouts screen.','Trainer Dashboard with assigned-team care navigation.')
 put(path,text)
print('PASS Trainer workspace source preparation and paired web/service-worker version')
