"""Embed the trainer workspace and narrowly hook team lifecycle; no native changes."""
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1]
check='--check' in sys.argv
p=root/'index.html';s=p.read_text()
def once(old,new):
 global s
 if new in s:return
 if s.count(old)!=1:raise RuntimeError('Unexpected app source: '+old[:90])
 s=s.replace(old,new,1)
once("  const res = await client.auth.getSession();\n  session = res.data.session;", "  window.WMTrainerDashboard?.reset();\n  const res = await client.auth.getSession();\n  session = res.data.session;")
once("  if(myWeightCheckActive)resetMyWeightCheck();\n  ++weightTestVersion;", "  window.WMTrainerDashboard?.suspend();\n  if(myWeightCheckActive)resetMyWeightCheck();\n  ++weightTestVersion;")
once("    message(`${team.name} does not have an active season yet.`,true);\n    return;", "    window.WMTrainerDashboard?.prepared();\n    message(`${team.name} does not have an active season yet.`,true);\n    return;")
once("  if(persist) message(`Switched to ${team.name}.`);\n}","  window.WMTrainerDashboard?.prepared();\n  if(persist) message(`Switched to ${team.name}.`);\n}")
start='<!-- BEGIN TRAINER DASHBOARD -->';end='<!-- END TRAINER DASHBOARD -->'
block=start+'\n<style>\n'+(root/'src/trainer-dashboard.css').read_text()+'\n</style>\n<script>\n'+(root/'src/trainer-dashboard.js').read_text()+'\n</script>\n'+end
s=re.sub(re.escape(start)+r'[\s\S]*?'+re.escape(end),lambda _:block,s) if start in s else s.replace('</body>',block+'\n</body>')
if check:assert p.read_text()==s,'Trainer embedding or lifecycle hooks differ'
else:p.write_text(s)
print('PASS Trainer Dashboard embedding and lifecycle hooks')
