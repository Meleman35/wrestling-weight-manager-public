from pathlib import Path
import hashlib,json,re,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1];baseline='82e89ca2ec9cd3f28ed205e19ce3a9d28fb62eb4';html=(root/'index.html').read_bytes()
with tempfile.TemporaryDirectory() as tmp:
 target=Path(tmp);(target/'scripts').mkdir();shutil.copytree(root/'src',target/'src')
 (target/'index.html').write_bytes(subprocess.check_output(['git','show',baseline+':index.html'],cwd=root))
 for name in ['build-tournaments-042.py','build-tournament-alerts-043.py']:shutil.copy(root/'scripts'/name,target/'scripts')
 for _ in range(2):
  subprocess.run(['python',str(target/'scripts/build-tournament-alerts-043.py')],check=True)
  assert (target/'index.html').read_bytes()==html,'Rebuild/idempotence mismatch'
 checked=0
 for i,(attrs,body) in enumerate(re.findall(r'<script\b([^>]*)>(.*?)</script\s*>',html.decode(),re.S|re.I)):
  if 'src=' in attrs or 'application/ld+json' in attrs:continue
  f=target/f'script-{i}.js';f.write_text(body);subprocess.run(['node','--check',str(f)],check=True,capture_output=True);checked+=1
preserved=['mat-mode.html','auth-confirm.html','app.js','styles.css','src/join-copy.js','src/clipboard-navigation.js','src/tournament-provider.js','src/athlete-goals.js','src/notification-inbox.js','src/message-reactions.js']
for f in preserved:assert (root/f).read_bytes()==subprocess.check_output(['git','show',baseline+':'+f],cwd=root),f
sql=(root/'supabase/migrations/20260925043538_tournament_alert_preferences_02043.sql').read_text()
assert not re.search(r'cron\.(schedule|alter_job)|net\.http|insert into (public\.)?communication_',sql,re.I)
subprocess.run(['git','diff','--check'],cwd=root,check=True)
result={'baseline':baseline,'reproducible':True,'idempotent':True,'inline_scripts_syntax_checked':checked,'preserved_files':preserved,'scheduler_or_delivery_writes':False,'sha256':hashlib.sha256(html).hexdigest()}
(root/'validation/tournament-alerts-043-source.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
