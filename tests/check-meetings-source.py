"""Syntax and byte-preservation gates for 0.20.38."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
base='97a41fe9987555b3c4be6b3d9a047eb877899f8d'
class Scripts(HTMLParser):
 def __init__(self):super().__init__(convert_charrefs=False);self.blocks=[];self.current=None
 def handle_starttag(self,tag,attrs):
  if tag=='script':self.current={'attrs':dict(attrs),'text':''}
 def handle_data(self,data):
  if self.current is not None:self.current['text']+=data
 def handle_endtag(self,tag):
  if tag=='script' and self.current is not None:self.blocks.append(self.current);self.current=None
a,b=Scripts(),Scripts();a.feed(subprocess.check_output(['git','show',base+':index.html'],cwd=root).decode());new=(root/'index.html').read_text();b.feed(new)
added=[x for x in b.blocks if x['attrs'].get('id')=='wmMeetings038'];assert len(added)==1
assert added[0]['text']=='\n'+(root/'src/organization-meetings.js').read_text()+'\n'
others=[x for x in b.blocks if x not in added];assert len(a.blocks)==len(others)
preserved=0
for old,now in zip(a.blocks,others):
 assert old['attrs']==now['attrs']
 x,y=old['text'].replace('v0.20.37','v0.20.38'),now['text']
 if 'window.WMProfiles=(()=>{' in x:
  y=re.sub(r' function profileViewTabs\(id,p,preview\).*?\n','',y,count=1)
  for start,end in [(' async function view(id,preview=false)',' function safeMusic(url)')]:
   x=re.sub(re.escape(start)+r'[\s\S]*?(?='+re.escape(end)+')','',x);y=re.sub(re.escape(start)+r'[\s\S]*?(?='+re.escape(end)+')','',y)
  y=y.replace("if(b.dataset.wpOwn)return view(b.dataset.wpOwn,false);if(b.dataset.wpPreviewId)return view(b.dataset.wpPreviewId,true);if(current?.preview&&(b.dataset.wpOpen||b.dataset.wpAffiliation))return;",'',1)
 elif '/* v0.20.5 organization operations.' in x:
  y=y.replace('window.WMMeetings?.close();','').replace("meetings:'Meetings & minutes',",'').replace("$o('opsDivision').disabled=['affiliates','meetings'].includes(tab);","$o('opsDivision').disabled=tab==='affiliates';")
  y=y.replace("\n  if(tab==='meetings'){window.WMMeetings.open({org});return;}",'').replace("['meetings','📝','Meetings & minutes','Agenda, roll call, decisions and saved minutes'],\n   ",'')
 assert x==y,'Unexpected modification outside meeting integration/profile view';preserved+=1
syntax=0
with tempfile.TemporaryDirectory() as temp:
 for i,block in enumerate(b.blocks):
  if 'src' in block['attrs'] or block['attrs'].get('type','') not in ('','module','text/javascript','application/javascript'):continue
  file=Path(temp)/(str(i)+'.js');file.write_text(block['text']);subprocess.run(['node','--check',str(file)],check=True,capture_output=True);syntax+=1
result={'release':'0.20.38','baseline':base,'syntax_checks':syntax,'preserved_script_checks':preserved,'index_sha256':hashlib.sha256(new.encode()).hexdigest(),'bytes':len(new.encode())}
(root/'validation/meetings-source.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
