#!/usr/bin/env python3
"""Verify candidate syntax and preservation. Pass the original 0.20.35 file as arg 1."""
from pathlib import Path
from html.parser import HTMLParser
import hashlib,json,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
class Scripts(HTMLParser):
    def __init__(self): super().__init__(convert_charrefs=False);self.out=[];self.current=None
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='script':self.current={'id':a.get('id',''), 'external':'src' in a, 'type':a.get('type',''), 'text':''}
    def handle_data(self,data):
        if self.current is not None:self.current['text']+=data
    def handle_endtag(self,tag):
        if tag=='script' and self.current is not None:self.out.append(self.current);self.current=None

def scripts(text):
    p=Scripts();p.feed(text);return p.out
new=(ROOT/'index.html').read_text();results=[]
with tempfile.TemporaryDirectory() as td:
    for i,s in enumerate(scripts(new)):
        if s['external'] or s['type'] not in ('','module','text/javascript','application/javascript'):continue
        f=Path(td)/f'{i}.js';f.write_text(s['text'])
        r=subprocess.run(['node','--check',str(f)],capture_output=True,text=True)
        assert r.returncode==0,r.stderr
        results.append({'check':'syntax','script':s['id'] or str(i),'passed':True})
if len(sys.argv)>1:
    old=Path(sys.argv[1]).read_text();assert hashlib.sha256(old.encode()).hexdigest()=='a703ee1ad1b27cd1876be000d63c8d537ac26f0675691f76a8185d8d406079a4'
    anchor='/* Team-scoped people editor; staff and guardian roles can coexist. */'
    def block(text):
        start=text.index(anchor);end=text.index('</script>',start);return text[start:end]
    assert block(old)==block(new),'Invitation/people editor changed unexpectedly'
    results.append({'check':'Invitation email / people editor preserved byte-for-byte','passed':True})
    oldblocks=scripts(old);newblocks=scripts(new);
    for i,ob in enumerate(oldblocks):
        if '/* v0.20.5 organization operations.' in ob['text']:
            anchor='/* Position-aware score options.'
            nb=next(n for n in newblocks if '/* v0.20.5 organization operations.' in n['text'])
            assert ob['text'][ob['text'].index(anchor):]==nb['text'][nb['text'].index(anchor):], 'Scoring changed'
            continue
        assert any(ob==nb for nb in newblocks), 'Unexpected existing script change '+str(i)
    results.append({'check':'All unrelated scripts and scoring preserved byte-for-byte','passed':True})
    old_scripts={s['id']:s['text'] for s in scripts(old) if s['id']}
    for s in scripts(new):
        if s['id'] and ('profile-pin' in s['id'] or 'biometric' in s['id'] or 'wmMeetHub' in s['id']):
            assert old_scripts[s['id']]==s['text'];results.append({'check':'Native/security bridge preserved','script':s['id'],'passed':True})
(ROOT/'validation').mkdir(exist_ok=True)
(ROOT/'validation'/'source-checks.json').write_text(json.dumps(results,indent=2))
print(f'{len(results)} source checks passed ({sum(r["check"]=="syntax" for r in results)} syntax checks).')
