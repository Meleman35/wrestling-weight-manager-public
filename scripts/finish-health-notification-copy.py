"""Final copy review; never call hosted services or alter recipient permissions."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];check='--check' in sys.argv
p=root/'src/athlete-health.js';s=p.read_text()
old='<p class="fine">Private to the trainer, connected family with permission, and you. You can add a photo after saving. Contact the trainer directly for urgent concerns.</p>'
new='<p class="fine">${state.trainer?\'The selected audience applies only to this new update. Previous private notes and attachments stay private.\':\'Private to the trainer, connected family with permission, and you.\'} You can add a private attachment after saving. Contact the trainer directly for urgent concerns.</p>'
if new not in s:
 assert s.count(old)==1
 s=s.replace(old,new,1)
if check:assert p.read_text()==s
else:p.write_text(s)
subprocess.run([sys.executable,'scripts/patch-athlete-health.py']+(['--check'] if check else []),cwd=root,check=True)
print('PASS New-case copy does not falsely promise a shared update is private')
