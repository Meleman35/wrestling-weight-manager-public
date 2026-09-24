"""Embed the source module; exact base guard prevents replacing a newer app."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
start='<script id="wmOrgStructure036">\n';end='\n</script><!-- /wmOrgStructure036 -->'
module=start+(root/'src/organization-structure.js').read_text()+end
if start in s:
 a=s.index(start);b=s.index(end,a)+len(end);s=s[:a]+module+s[b:]
else:
 assert hashlib.sha256(s.encode()).hexdigest()=='a703ee1ad1b27cd1876be000d63c8d537ac26f0675691f76a8185d8d406079a4','Unexpected baseline'
 s=s.replace('v0.20.35','v0.20.36')
 s=s.replace('Clipboard Organization card and cross-organization team switching.','Server-backed organization positions and affiliate directory.')
 s=s.replace("const labels={home:'Overview',", "const labels={home:'Overview',positions:'Positions',affiliates:'Affiliate directory',",1)
 s=s.replace("function render(){if(!hub)return;", "function render(){window.WMOrgStructure?.close();if(!hub)return;$o('opsDivision').disabled=tab==='affiliates';",1)
 s=s.replace("if(tab==='teams'){teams();return;}","if(tab==='teams'){teams();return;}\n  if(['positions','affiliates'].includes(tab)){window.WMOrgStructure.open({org,hub,kind:tab,scope:division});return;}",1)
 s=s.replace("['person','🪪','Staff & credentials'", "['positions','🏛️','Positions','Vacancies, adult assignments and explicit access'],\n   ['affiliates','🔗','Affiliate directory','Clubs, schools and membership review'],\n   ['person','🪪','Staff & credentials'",1)
 s=s.replace("async function open(wantedOrg=null,wantedRecord=null,wantedTab='home'){", "async function open(wantedOrg=null,wantedRecord=null,wantedTab='home'){\n  window.WMOrgStructure?.close();",1)
 s=s.replace("function close(){finishDialog(null);generation++;", "function close(){window.WMOrgStructure?.close();finishDialog(null);generation++;",1)
 s=s.replace("$o('opsOrg').onchange=async()=>{org=value('opsOrg');", "$o('opsOrg').onchange=async()=>{window.WMOrgStructure?.close();org=value('opsOrg');",1)
 anchor='<script>\n/* v0.20.5 organization operations.'
 assert s.count(anchor)==1
 s=s.replace(anchor,'<style>.gs-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));gap:14px}.gs-root label{display:flex;flex-direction:column;gap:6px;min-width:0}.gs-root .ops-check{flex-direction:row;align-items:flex-start}.gs-root input,.gs-root select,.gs-root textarea{max-width:100%;min-width:0}.gs-root .ops-check input{width:auto;flex:0 0 auto}.gs-root textarea{min-height:88px}.gs-root .ops-actions{margin:14px 0;flex-wrap:wrap}.gs-root .ops-card{overflow-wrap:anywhere}.gs-root #gsStatus:empty{display:none}.gs-root #gsStatus:not(:empty){padding:10px 0}</style>\n'+module+'\n'+anchor,1)
 p.write_text(s)
