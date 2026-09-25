from pathlib import Path
from html.parser import HTMLParser
import subprocess,tempfile,shutil,json,re
root=Path(__file__).resolve().parents[1]
class Parser(HTMLParser):
 def __init__(self):super().__init__(convert_charrefs=False);self.blocks=[];self.current=None
 def handle_starttag(self,tag,attrs):
  if tag=='script':self.current=[dict(attrs),'']
 def handle_data(self,data):
  if self.current is not None:self.current[1]+=data
 def handle_endtag(self,tag):
  if tag=='script' and self.current is not None:self.blocks.append(self.current);self.current=None
old=subprocess.check_output(['git','show','82e89ca2ec9cd3f28ed205e19ce3a9d28fb62eb4:index.html'],cwd=root).decode()
new=(root/'index.html').read_text();checks=[]
with tempfile.TemporaryDirectory() as td:
 temp=Path(td);(temp/'scripts').mkdir();(temp/'src').mkdir();(temp/'index.html').write_text(old)
 for rel in ['scripts/build-organization-invitations-045.py','src/organization-invitations.js','src/organization-invitations.css']:shutil.copy(root/rel,temp/rel)
 subprocess.run(['python',str(temp/'scripts/build-organization-invitations-045.py')],check=True)
 assert (temp/'index.html').read_text()==new;checks.append('Exact reproduction from published 0.20.42 base')
 subprocess.run(['python',str(temp/'scripts/build-organization-invitations-045.py')],check=True)
 assert (temp/'index.html').read_text()==new;checks.append('Build is idempotent')
 parser=Parser();parser.feed(new);syntax=0
 for i,(attrs,code) in enumerate(parser.blocks):
  if attrs.get('src') or not code.strip() or attrs.get('type','') not in ('','text/javascript','module'):continue
  f=temp/f'{i}.js';f.write_text(code);subprocess.run(['node','--check',str(f)],capture_output=True,check=True);syntax+=1
 checks.append(f'All {syntax} inline scripts parse')
 before=Parser();before.feed(old)
 protected=[[attrs,code] for attrs,code in before.blocks if any(k in str(attrs) for k in ['profile-pin','biometric','wmMeetHub'])]
 for item in protected:assert item in parser.blocks
 checks.append(f'{len(protected)} native/security script blocks preserved')
 for asset in ['app.js','styles.css','mat-mode.html','auth-confirm.html']:
  assert subprocess.check_output(['git','show','82e89ca2ec9cd3f28ed205e19ce3a9d28fb62eb4:'+asset],cwd=root)==(root/asset).read_bytes()
 checks.append('App assets, mat mode and confirmation page preserved')
sql=re.sub(r'--[^\n]*','',next((root/'supabase/migrations').glob('*_organization_leadership_invitations_02045.sql')).read_text())
for forbidden in ['insert into public.team_memberships','update public.team_memberships','delete from public.team_memberships','team_plan','billing','update private.organization_affiliates']:
 assert forbidden not in sql.lower(),forbidden
checks.append('Migration contains no team membership, affiliate or paid entitlement mutation')
(root/'validation/organization-invitations-source.json').write_text(json.dumps({'passed':len(checks),'tests':checks},indent=2))
for c in checks:print('PASS',c)
