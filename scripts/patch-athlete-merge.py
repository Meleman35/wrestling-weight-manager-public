from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1];path=root/'index.html';html=path.read_text();start='<!-- BEGIN ATHLETE MERGE -->';end='<!-- END ATHLETE MERGE -->';block=start+'\n<script>\n'+(root/'src/athlete-merge.js').read_text()+'</script>\n'+end
if '--check' in sys.argv:
 assert block in html,'Athlete merge source is not embedded';sys.exit(0)
if start in html:html=html[:html.index(start)]+block+html[html.index(end)+len(end):]
else:html=html.replace('</body>',block+'\n</body>')
path.write_text(html)
