from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html'
s=p.read_text()
module=(root/'src/athlete-card-export.mjs').read_text().replace('export ','')
ui=(root/'src/athlete-card-export-ui.js').read_text()
block='<script id="wm-bulk-athlete-cards">\n'+module+'\n'+ui+'\n</script>\n'
pattern=r'<script id="wm-bulk-athlete-cards">[\s\S]*?</script>\n?'
matches=list(re.finditer(pattern,s))
if len(matches)>1 or s.count('</body>')!=1:
    raise SystemExit('Unexpected card integration markers; index.html was not changed.')
if matches:
    s=re.sub(pattern,lambda _:block,s,count=1)
else:
    s=s.replace('</body>',block+'</body>')
p.write_text(s)
