"""Embed credential-free role previews. No real account provisioning or data writes."""
from pathlib import Path
import base64,hashlib,json,re,sys
root=Path(__file__).resolve().parents[1]
check='--check' in sys.argv
css=(root/'src/role-preview-demo.css').read_text()
js=(root/'src/role-preview-demo.js').read_text()
sha=base64.b64encode(hashlib.sha256(js.encode()).digest()).decode()
html='''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'sha256-HASH'; style-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Role Views · Fictional Demo</title><style>CSS</style></head><body>
<section class="preview-controls"><div><div class="notice"><b>DEMO ONLY · Fictional people</b><br>Representative screens, not a live account. Do not enter personal information.</div><div class="controls-grid"><div><label for="demoRole">Whose experience?</label><select id="demoRole"><option value="athlete">Athlete</option><option value="coach">Coach</option><option value="trainer">Athletic Trainer</option><option value="team_mom">Team Mom</option><option value="parent">Parent / Guardian</option><option value="admin">Team Administrator</option></select></div><div id="demoScenario" class="scenario"></div></div><nav class="preview-pages" aria-label="Preview pages"><button type="button" data-demo-page="home">Home</button><button type="button" data-demo-page="profile">Profile</button><button type="button" data-demo-page="schedule">Schedule</button><button type="button" data-demo-page="access">Access</button></nav></div></section>
<header class="preview-team"><div><div><small>FICTIONAL TEAM</small><b>Summit Demo Wrestling</b><small id="demoPersona"></small></div><div id="demoAvatar" class="avatar-small" aria-hidden="true"></div></div></header>
<main class="screen"><div id="demoScreen" tabindex="-1"></div><p id="demoStatus" role="status"></p><button id="demoReset" type="button" class="link">Reset this demo</button></main><footer class="footer">Preview pages simplify navigation. Actual account views depend on assignments, age, family permissions and released features. This is not a live permission test.</footer><script>JS</script></body></html>'''.replace('HASH',sha).replace('CSS',css).replace('>JS</script>','>'+js+'</script>')
# Escape markup in the host script literal, including closing script sequences.
payload='window.WMRolePreviewDocument='+json.dumps(html,ensure_ascii=True).replace('<','\\u003c')+';'
start='<!-- BEGIN CREATOR ROLE PREVIEW -->';end='<!-- END CREATOR ROLE PREVIEW -->'
block=start+'\n<style>\n'+(root/'src/creator-role-preview.css').read_text()+'\n</style>\n<script>\n'+payload+'\n</script>\n<script>\n'+(root/'src/creator-role-preview.js').read_text()+'\n</script>\n'+end
p=root/'index.html';s=p.read_text()
if start in s:s=re.sub(re.escape(start)+r'[\s\S]*?'+re.escape(end),lambda _:block,s)
else:
 assert s.count('</body>')==1,'Unexpected document boundary'
 s=s.replace('</body>',block+'\n</body>')
old='window.WMAthleteHealth?.close();window.WMCreatorOffers?.close();'
new=old+'window.WMCreatorRolePreview?.close();'
if new not in s:
 assert s.count(old)==1,'Unexpected sheet cleanup'
 s=s.replace(old,new)
s=s.replace('0.20.112','0.20.113').replace('Trainer Dashboard with assigned-team care navigation.','Creator role previews with fictional, isolated account views.')
for p,text in [(p,s),(root/'sw.js',(root/'sw.js').read_text().replace('0.20.112','0.20.113'))]:
 if check:assert p.read_text()==text,'Generated role preview differs: '+p.name
 else:p.write_text(text)
print('PASS role preview embedding, sandbox document and paired web/service-worker release')
