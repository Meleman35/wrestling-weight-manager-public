from pathlib import Path
import re,subprocess,sys
root=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'scripts/build-tournaments-042.py')],check=True)
p=root/'index.html';s=p.read_text()
s=s.replace('<!-- Wrestling Manager v0.20.42: Reliable team link copying, customizable Clipboard categories and manual Tournament Day. -->','<!-- Wrestling Manager v0.20.43: Tournament alert choices and private background preparation. -->').replace('Build v0.20.42','Build v0.20.43')
s=re.sub(r'<script id="wm-tournament-alert-preferences-043">.*?</script>\n?', '',s,flags=re.S)
module='<script id="wm-tournament-alert-preferences-043">\n'+(root/'src/tournament-alert-preferences.js').read_text()+'\n</script>\n'
s=s.replace('<script id="wm-tournaments-042">',module+'<script id="wm-tournaments-042">')
css='<style id="wm-tournament-alerts-043">\n'+(root/'src/tournament-alerts-043.css').read_text()+'\n</style>'
if '<style id="wm-tournament-alerts-043">' in s:s=re.sub(r'<style id="wm-tournament-alerts-043">.*?</style>',lambda _:css,s,flags=re.S)
else:s=s.replace('</head>',css+'\n</head>')
s=re.sub(r'</script>\s*<script id="wm-tournament-provider-042">', '</script>\n<script id="wm-tournament-provider-042">',s)
p.write_text(s)
print('Embedded tournament alert choices (delivery inactive)')
