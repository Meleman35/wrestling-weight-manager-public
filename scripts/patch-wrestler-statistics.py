from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1];p=root/'index.html';s=p.read_text()
start='<!-- BEGIN WRESTLER STATISTICS -->';end='<!-- END WRESTLER STATISTICS -->'
block=start+'\n'+''.join('<script>\n'+(root/name).read_text()+'\n</script>\n' for name in ['src/wrestler-statistics-engine.js','src/wrestler-statistics.js'])+end
new=re.sub(re.escape(start)+r'[\s\S]*?'+re.escape(end),lambda _:block,s) if start in s else s.replace('</body>',block+'\n</body>')
if '--check' in sys.argv:
 assert new==s,'Statistics embedding differs';print('PASS statistics embedding')
else:p.write_text(new)
