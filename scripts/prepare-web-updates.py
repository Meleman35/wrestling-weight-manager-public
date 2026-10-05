"""Embed the public version check without changing worker activation or account data."""
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1]
check='--check' in sys.argv
def put(path,text):
 target=root/path
 if check: assert target.read_text()==text,'Generated source differs: '+path
 else: target.write_text(text)
source=(root/'src/web-updates.js').read_text()
assert "const CURRENT='0.20.123'" in source
html=(root/'index.html').read_text()
script='<script id="wm-web-updates">\n'+source+'\n</script>'
if 'id="wm-web-updates"' in html:
 html,count=re.subn(r'<script id="wm-web-updates">.*?</script>',lambda _:script,html,flags=re.S);assert count==1
else:
 assert html.count('</body>')==1
 html=html.replace('</body>',script+'\n</body>')
html=html.replace('0.20.118','0.20.123').replace('0.20.120','0.20.123').replace('0.20.122','0.20.123')
put('index.html',html)
put('sw.js',(root/'sw.js').read_text().replace('0.20.118','0.20.123').replace('0.20.120','0.20.123').replace('0.20.122','0.20.123'))
for path in ['scripts/prepare-linked-creator-release.py','scripts/prepare-notification-header.py','scripts/prepare-deletion-availability.py']:
 text=(root/path).read_text()
 if "'0.20.123'" not in text:
  assert "'0.20.120'" in text
  text=text.replace("'0.20.120'","'0.20.120','0.20.123'")
 put(path,text)
assert 'Build v0.20.123' in html
assert "const CACHE='wm-shell-0.20.123';" in (root/'sw.js').read_text()
print('PASS paired web 0.20.123 and public update check; no activation, reload or private-data changes')
