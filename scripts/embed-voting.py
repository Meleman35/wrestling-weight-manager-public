"""Embed private voting into the verified 0.20.38 baseline; preserve other features."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1];p=root/'index.html';s=p.read_text()
start='<script id="wmVoting039">\n';end='\n</script><!-- /wmVoting039 -->'
module=start+(root/'src/organization-voting.js').read_text()+end
if start in s:
 a=s.index(start);b=s.index(end,a)+len(end);s=s[:a]+module+s[b:]
else:
 assert hashlib.sha256(s.encode()).hexdigest()=='0beba69dc056f3581756c4e88c067258cda1b520eeee59b9ae36b4e8c84e2885','Unexpected baseline'
 s=s.replace('v0.20.38','v0.20.39').replace('Server-backed meetings and minutes; What others see profile tab.','Private board/club ballots and deletable test meetings.',1)
 s=s.replace("meetings:'Meetings & minutes',event:","meetings:'Meetings & minutes',voting:'Private voting',event:",1)
 s=s.replace("function render(){window.WMMeetings?.close();", "function render(){window.WMVoting?.close();window.WMMeetings?.close();",1)
 s=s.replace("['affiliates','meetings'].includes(tab)","['affiliates','meetings','voting'].includes(tab)",1)
 s=s.replace("if(tab==='meetings'){window.WMMeetings.open({org});return;}","if(tab==='meetings'){window.WMMeetings.open({org});return;}\n  if(tab==='voting'){window.WMVoting.open({org});return;}",1)
 s=s.replace("['meetings','📝','Meetings & minutes','Agenda, roll call, decisions and saved minutes'],", "['meetings','📝','Meetings & minutes','Agenda, roll call, decisions and saved minutes'],\n   ['voting','🗳️','Private voting','Board and club ballots with results after closing'],",1)
 s=s.replace("function close(){window.WMMeetings?.close();", "function close(){window.WMVoting?.close();window.WMMeetings?.close();",1)
 s=s.replace("$o('opsOrg').onchange=async()=>{window.WMMeetings?.close();", "$o('opsOrg').onchange=async()=>{window.WMVoting?.close();window.WMMeetings?.close();",1)
 anchor='<script>\n/* v0.20.5 organization operations.'
 css='<style>.vb-root label{display:flex;flex-direction:column;gap:6px;margin:12px 0;min-width:0}.vb-root .ops-check{flex-direction:row;align-items:center}.vb-root .ops-check input{width:auto}.vb-root textarea{min-height:100px}.vb-root h4{margin-top:24px}.vb-root .ops-actions{display:flex;flex-wrap:wrap;gap:10px;margin:18px 0}.vb-root fieldset{border:1px solid var(--line);border-radius:12px}.vb-root .vb-participants{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,250px),1fr));gap:10px;max-height:480px;overflow:auto}.vb-test{color:var(--warn);padding:10px;border:1px solid var(--warn);border-radius:10px}.vb-policy{display:grid;grid-template-columns:1fr 1fr;gap:8px}.vb-policy dd{margin:0;overflow-wrap:anywhere}.vb-counts{display:flex;gap:20px;flex-wrap:wrap}.vb-counts p{display:flex;flex-direction:column;align-items:center}.vb-counts b{font-size:28px}.vb-root #vbStatus{position:sticky;top:0;background:var(--card);z-index:2;white-space:pre-wrap}.vb-root #vbStatus:not(:empty){padding:12px;border:1px solid var(--line);border-radius:10px}</style>'
 assert s.count(anchor)==1;s=s.replace(anchor,css+'\n'+module+'\n'+anchor,1)
# Meeting source is patched deliberately alongside this release.
a=s.index('<script id="wmMeetings038">\n');b=s.index('\n</script><!-- /wmMeetings038 -->',a)
s=s[:a]+'<script id="wmMeetings038">\n'+(root/'src/organization-meetings.js').read_text()+s[b:]
p.write_text(s)
