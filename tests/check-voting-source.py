"""Byte preservation outside explicit 0.20.39 meeting/voting integrations."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib,json,subprocess,tempfile
root=Path(__file__).resolve().parents[1];base='f74ba2ba1d92b59d47d316c3332f79bac05aa2b5'
class Scripts(HTMLParser):
 def __init__(self):super().__init__(convert_charrefs=False);self.blocks=[];self.current=None
 def handle_starttag(self,t,a):
  if t=='script':self.current={'attrs':dict(a),'text':''}
 def handle_data(self,d):
  if self.current is not None:self.current['text']+=d
 def handle_endtag(self,t):
  if t=='script' and self.current is not None:self.blocks.append(self.current);self.current=None
old,new=Scripts(),Scripts();old.feed(subprocess.check_output(['git','show',base+':index.html'],cwd=root).decode());html=(root/'index.html').read_text();new.feed(html)
for key,file in [('wmVoting039','organization-voting.js'),('wmMeetings038','organization-meetings.js')]:
 blocks=[x for x in new.blocks if x['attrs'].get('id')==key];assert len(blocks)==1;assert blocks[0]['text']=='\n'+(root/'src'/file).read_text()+'\n'
others=[x for x in new.blocks if x['attrs'].get('id')!='wmVoting039'];assert len(others)==len(old.blocks)
preserved=0
for a,b in zip(old.blocks,others):
 assert a['attrs']==b['attrs'];x=a['text'].replace('v0.20.38','v0.20.39');y=b['text']
 if a['attrs'].get('id')=='wmMeetings038':continue
 if '/* v0.20.5 organization operations.' in x:
  y=y.replace('window.WMVoting?.close();','').replace("voting:'Private voting',",'').replace("['affiliates','meetings','voting'].includes(tab)","['affiliates','meetings'].includes(tab)")
  y=y.replace("\n  if(tab==='voting'){window.WMVoting.open({org});return;}",'').replace("['voting','🗳️','Private voting','Board and club ballots with results after closing'],\n   ",'')
 assert x==y,'Unexpected change outside voting integration';preserved+=1
syntax=0
with tempfile.TemporaryDirectory() as tmp:
 for i,b in enumerate(new.blocks):
  if 'src' in b['attrs'] or b['attrs'].get('type','') not in ('','module','text/javascript','application/javascript'):continue
  p=Path(tmp)/(str(i)+'.js');p.write_text(b['text']);subprocess.run(['node','--check',str(p)],check=True,capture_output=True);syntax+=1
result={'release':'0.20.39','baseline':base,'syntax_checks':syntax,'preserved_script_checks':preserved,'embedded_sources':2,'index_sha256':hashlib.sha256(html.encode()).hexdigest(),'bytes':len(html.encode())}
(root/'validation/voting-source.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
