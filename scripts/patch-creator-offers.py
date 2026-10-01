from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1];p=root/'index.html';s=p.read_text()
start='<!-- BEGIN CREATOR OFFERS -->';end='<!-- END CREATOR OFFERS -->'
block=start+'\n<style>\n'+(root/'src/creator-offers.css').read_text()+'\n</style>\n<script>\n'+(root/'src/creator-offers.js').read_text()+'\n</script>\n'+end
new=re.sub(re.escape(start)+r'[\s\S]*?'+re.escape(end),lambda _:block,s) if start in s else s.replace('</body>',block+'\n</body>')
if '--check' in sys.argv:assert new==s,'Creator offers embedding differs';print('PASS Creator offers embedding')
else:p.write_text(new)
