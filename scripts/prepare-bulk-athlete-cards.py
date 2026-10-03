from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'index.html'
s=p.read_text()
if 'id="wm-bulk-athlete-cards"' not in s:
    module=(root/'src/athlete-card-export.mjs').read_text().replace('export ','')
    ui=(root/'src/athlete-card-export-ui.js').read_text()
    s=s.replace('</body>','<script id="wm-bulk-athlete-cards">\n'+module+'\n'+ui+'\n</script>\n</body>')
    p.write_text(s)
