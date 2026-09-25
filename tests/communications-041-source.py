"""Verify reproducible integration and JavaScript syntax without altering the checkout."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
baseline='ae781feb52aca942a4a295c4f4c811badb095ded'
html=(root/'index.html').read_bytes()
with tempfile.TemporaryDirectory() as tmp:
 target=Path(tmp);(target/'scripts').mkdir();(target/'src').mkdir()
 (target/'index.html').write_bytes(subprocess.check_output(['git','show',baseline+':index.html'],cwd=root))
 shutil.copy(root/'scripts/build-communications-041.py',target/'scripts')
 for f in ['notification-inbox.js','message-reactions.js','communications-041.css']:shutil.copy(root/'src'/f,target/'src')
 subprocess.run(['python',str(target/'scripts/build-communications-041.py')],check=True)
 assert (target/'index.html').read_bytes()==html,'Rebuild differs from release HTML'
 subprocess.run(['python',str(target/'scripts/build-communications-041.py')],check=True)
 assert (target/'index.html').read_bytes()==html,'Embedding is not idempotent'
 checked=0
 for i,(attrs,body) in enumerate(re.findall(r'<script\b([^>]*)>(.*?)</script\s*>',html.decode(),re.S|re.I)):
  if 'src=' in attrs or 'application/ld+json' in attrs:continue
  f=target/f'script-{i}.js';f.write_text(body);subprocess.run(['node','--check',str(f)],check=True,capture_output=True);checked+=1
preserved=['mat-mode.html','auth-confirm.html','app.js','styles.css']
for f in preserved:assert (root/f).read_bytes()==subprocess.check_output(['git','show',baseline+':'+f],cwd=root),f
subprocess.run(['git','diff','--check'],cwd=root,check=True)
result={'baseline':baseline,'reproducible':True,'idempotent':True,'inline_scripts_syntax_checked':checked,'preserved_files':preserved,'sha256':hashlib.sha256(html).hexdigest()}
(root/'validation/communications-041-source.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
