"""Embed 0.20.38 additions into the verified 0.20.37 page without replacing other modules."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
p=root/'index.html'; s=p.read_text()
start='<script id="wmMeetings038">\n'; end='\n</script><!-- /wmMeetings038 -->'
module=start+(root/'src/organization-meetings.js').read_text()+end
if start in s:
 a=s.index(start); b=s.index(end,a)+len(end); s=s[:a]+module+s[b:]
else:
 assert hashlib.sha256(s.encode()).hexdigest()=='80f8d87a542f2b3cd6eb7208adb6c980355595e991bfd556468981e2c02f5e37','Unexpected baseline'
 s=s.replace('v0.20.37','v0.20.38')
 s=s.replace('Clear account creation guidance for team invitations and both login modes.','Server-backed meetings and minutes; What others see profile tab.',1)
 s=s.replace("affiliates:'Affiliate directory',event:","affiliates:'Affiliate directory',meetings:'Meetings & minutes',event:",1)
 s=s.replace("function render(){window.WMOrgStructure?.close();", "function render(){window.WMMeetings?.close();window.WMOrgStructure?.close();",1)
 s=s.replace("$o('opsDivision').disabled=tab==='affiliates';", "$o('opsDivision').disabled=['affiliates','meetings'].includes(tab);",1)
 s=s.replace("if(tab==='teams'){teams();return;}","if(tab==='teams'){teams();return;}\n  if(tab==='meetings'){window.WMMeetings.open({org});return;}",1)
 s=s.replace("['event','📅','Calendar','Board meetings, tournaments and shared dates'],", "['meetings','📝','Meetings & minutes','Agenda, roll call, decisions and saved minutes'],\n   ['event','📅','Calendar','Board meetings, tournaments and shared dates'],",1)
 s=s.replace("function close(){window.WMOrgStructure?.close();", "function close(){window.WMMeetings?.close();window.WMOrgStructure?.close();",1)
 s=s.replace("$o('opsOrg').onchange=async()=>{window.WMOrgStructure?.close();", "$o('opsOrg').onchange=async()=>{window.WMMeetings?.close();window.WMOrgStructure?.close();",1)
 anchor='<script>\n/* v0.20.5 organization operations.'
 assert s.count(anchor)==1
 css='<style>.mt-root label{display:flex;flex-direction:column;gap:6px;margin:12px 0;min-width:0}.mt-root .ops-check{flex-direction:row;align-items:center}.mt-root .ops-check input{width:auto}.mt-root input,.mt-root textarea,.mt-root select{max-width:100%;min-width:0}.mt-root textarea{min-height:100px}.mt-root .ops-actions{flex-wrap:wrap;margin:16px 0}.mt-savebar{position:sticky;top:0;z-index:2;background:var(--soft,#eef3f8);color:var(--ink,#12161b);padding:8px;border:1px solid var(--line,#e3e7ec);border-radius:10px}.mt-savebar p:empty{display:none}.mt-root h4{font-size:18px;margin:28px 0 10px}.mt-root h5{font-size:16px;margin:12px 0}.mt-roll{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,250px),1fr));gap:10px;max-height:520px;overflow:auto;margin:14px 0}.mt-roll small{display:block}.mt-roll-summary{max-height:350px;overflow:auto}.mt-text{white-space:pre-wrap;overflow-wrap:anywhere}.mt-label{font-weight:800;letter-spacing:.04em;color:var(--accent,#e9bc51)}.mt-confidential{border:1px solid #b67b32}.mt-root details summary{cursor:pointer;padding:10px 0}.wp-preview-tabs{display:flex;gap:8px;margin:14px 0}.wp-preview-tabs button{flex:1}.wp-preview-tabs [aria-selected=true]{outline:2px solid var(--accent,#e9bc51);font-weight:800}</style>'
 s=s.replace(anchor,css+'\n'+module+'\n'+anchor,1)
 # Promote the existing server-filtered profile preview into explicit tabs.
 view=' async function view(id,preview=false)'
 assert s.count(view)==1
 tabs=''' function profileViewTabs(id,p,preview){const own=p.manager||p.self||mine.some(x=>x.id===id);return button('All profiles','data-wp-home')+(own?`<div class="wp-preview-tabs" role="tablist" aria-label="Profile view"><button class="secondary" role="tab" aria-selected="${!preview}" data-wp-own="${E(id)}">My profile</button><button class="secondary" role="tab" aria-selected="${preview}" data-wp-preview-id="${E(id)}">What others see</button></div>`:'');}
'''
 s=s.replace(view,tabs+view,1)
 s=s.replace("current={...p,id};status(preview?'Outside view · what another signed-in member can see. Team-only access is separate.':'');", "current={...p,id,preview};status(preview?'What others see · Preview for other signed-in members. Restricted team and family access is separate.':'');",1)
 s=s.replace("button('Back to my profile',`data-wp-open=\"${id}\"`)+'<section", "profileViewTabs(id,p,preview)+'<section",1)
 s=s.replace("${preview?button('Back to my profile',`data-wp-open=\"${id}\"`):button('All profiles','data-wp-home')}", "${profileViewTabs(id,p,preview)}",1)
 s=s.replace("${(p.manager||p.self)&&!preview?button('How others view my profile','data-wp-preview'):''}", '',1)
 s=s.replace("async function handle(b){if(!allowed())return;", "async function handle(b){if(!allowed())return;if(b.dataset.wpOwn)return view(b.dataset.wpOwn,false);if(b.dataset.wpPreviewId)return view(b.dataset.wpPreviewId,true);if(current?.preview&&(b.dataset.wpOpen||b.dataset.wpAffiliation))return;",1)
 # Shared links remain visible in the preview, but cannot lead back into owner tools.
 needle=" hydratePhotos($p('wpBody'));\n const photo=photoRef(p);"
 assert s.count(needle)==1
 s=s.replace(needle," if(preview)$p('wpBody').querySelectorAll('[data-wp-open],[data-wp-affiliation]').forEach(b=>{b.disabled=true;});\n"+needle,1)
p.write_text(s)
