"""Rebuild this release from its committed baseline, verify modules and preserve native-facing assets."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1];baseline='c469a483ac33b1840ee32292bb537e050d028879';html=(root/'index.html').read_bytes()
with tempfile.TemporaryDirectory() as tmp:
 target=Path(tmp);(target/'scripts').mkdir();(target/'src').mkdir()
 (target/'index.html').write_bytes(subprocess.check_output(['git','show',baseline+':index.html'],cwd=root))
 shutil.copy(root/'scripts/build-tournaments-042.py',target/'scripts')
 for f in ['join-copy.js','clipboard-navigation.js','tournament-provider.js','tournament-alerts.js','tournaments.js','tournaments-042.css']:shutil.copy(root/'src'/f,target/'src')
 subprocess.run(['python',str(target/'scripts/build-tournaments-042.py')],check=True)
 assert (target/'index.html').read_bytes()==html,'Rebuild differs from release HTML'
 subprocess.run(['python',str(target/'scripts/build-tournaments-042.py')],check=True)
 assert (target/'index.html').read_bytes()==html,'Embedding is not idempotent'
 checked=0
 for i,(attrs,body) in enumerate(re.findall(r'<script\b([^>]*)>(.*?)</script\s*>',html.decode(),re.S|re.I)):
  if 'src=' in attrs or 'application/ld+json' in attrs:continue
  f=target/f'script-{i}.js';f.write_text(body);subprocess.run(['node','--check',str(f)],check=True,capture_output=True);checked+=1
preserved=['mat-mode.html','auth-confirm.html','app.js','styles.css','src/athlete-goals.js','src/notification-inbox.js','src/message-reactions.js','src/organization-meetings.js','src/organization-structure.js','src/organization-voting.js']
for f in preserved:assert (root/f).read_bytes()==subprocess.check_output(['git','show',baseline+':'+f],cwd=root),f
subprocess.run(['git','diff','--check'],cwd=root,check=True)
result={'baseline':baseline,'reproducible':True,'idempotent':True,'inline_scripts_syntax_checked':checked,'preserved_files':preserved,'sha256':hashlib.sha256(html).hexdigest()}
(root/'validation/tournaments-042-source.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
