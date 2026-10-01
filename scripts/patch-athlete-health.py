from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1];p=root/'index.html';s=p.read_text()
start='<!-- BEGIN ATHLETE HEALTH -->';end='<!-- END ATHLETE HEALTH -->'
block=start+'\n<style>\n'+(root/'src/athlete-health.css').read_text()+'\n</style>\n<script>\n'+(root/'src/athlete-health.js').read_text()+'\n</script>\n'+end
new=re.sub(re.escape(start)+r'[\s\S]*?'+re.escape(end),lambda _:block,s) if start in s else s.replace('</body>',block+'\n</body>')
if '--check' in sys.argv:assert new==s,'Athlete Health embedding differs';print('PASS Athlete Health embedding')
else:p.write_text(new)
