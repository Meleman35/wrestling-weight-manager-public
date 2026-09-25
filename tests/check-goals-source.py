"""Verify the precise 0.20.40 integrations and preserve unrelated app scripts."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib,json,subprocess,tempfile
root=Path(__file__).resolve().parents[1];base='70e6942003c00c0d898f3887a496924151165148'
class Scripts(HTMLParser):
 def __init__(self):super().__init__(convert_charrefs=False);self.blocks=[];self.current=None
 def handle_starttag(self,t,a):
  if t=='script':self.current={'attrs':dict(a),'text':''}
 def handle_data(self,d):
  if self.current is not None:self.current['text']+=d
 def handle_endtag(self,t):
  if t=='script' and self.current is not None:self.blocks.append(self.current);self.current=None
old,new=Scripts(),Scripts();old.feed(subprocess.check_output(['git','show',base+':index.html'],cwd=root).decode());html=(root/'index.html').read_text();new.feed(html)
assert len(old.blocks)==len(new.blocks);preserved=0;embedded=0
for a,b in zip(old.blocks,new.blocks):
 assert a['attrs']==b['attrs'];x=a['text'].replace('v0.20.39','v0.20.40');y=b['text']
 if '/* Team goals 0.20.' in x:
  assert y=='\n'+(root/'src/athlete-goals.js').read_text()+'\n';embedded+=1;continue
 y=y.replace("const next=['board','trophy','team','goals'].includes(name)&&!(name==='goals'&&managedLogin)?name:'board';","const next=['board','trophy','team'].includes(name)?name:'board';")
 y=y.replace("\n  if(next==='goals')window.WMGoals?.locker();else window.WMGoals?.leaveLocker();",'')
 y=y.replace("show('lockerGoalsTab',!managedLogin&&!!activeTeam);",'')
 y=y.replace(" ${window.WMGoals?.sharedProfile(p.shared_goals||[])||''}\n",'')
 assert x==y,'Unexpected change outside goals integration';preserved+=1
syntax=0
with tempfile.TemporaryDirectory() as tmp:
 for i,b in enumerate(new.blocks):
  if 'src' in b['attrs'] or b['attrs'].get('type','') not in ('','module','text/javascript','application/javascript'):continue
  p=Path(tmp)/(str(i)+'.js');p.write_text(b['text']);subprocess.run(['node','--check',str(p)],check=True,capture_output=True);syntax+=1
# The existing profile RPC changes only by adding its filtered goal projection.
sql=next((root/'supabase/migrations').glob('*athlete_goal_accomplishments_02040.sql')).read_text()
prior=(root/'tests/goals-profile-existing.sql').read_text();marker='CREATE OR REPLACE FUNCTION private.wrestling_profiles_request('
function=sql[sql.index(marker):].strip().rstrip(';').strip()
before=prior[prior.index(marker):];before=before[:before.index('$function$',before.index('end $function$'))+len('$function$')].strip()
assert function.replace("jsonb_build_object('shared_goals',private.goals040_profile(pid))||",'')==before,'Unexpected profile RPC change'
result={'release':'0.20.40','baseline':base,'syntax_checks':syntax,'preserved_script_checks':preserved,'embedded_sources':embedded,'profile_rpc_preserved':True,'index_sha256':hashlib.sha256(html.encode()).hexdigest(),'bytes':len(html.encode())}
(root/'validation/goals-source.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
