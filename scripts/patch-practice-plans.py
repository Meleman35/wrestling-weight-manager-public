from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1];p=root/'index.html';s=p.read_text()
start='<!-- BEGIN PRACTICE PLANS -->';end='<!-- END PRACTICE PLANS -->'
block=start+'\n<style>\n'+(root/'src/practice-plans.css').read_text()+'\n</style>\n<script>\n'+(root/'src/practice-plans.js').read_text()+'\n</script>\n'+end
new=re.sub(re.escape(start)+r'[\s\S]*?'+re.escape(end),lambda _:block,s) if start in s else s.replace('</body>',block+'\n</body>')
new=re.sub(r'(<script id="wm-clipboard-0.20.29">)[\s\S]*?(</script>)',lambda m:m[1]+'\n'+(root/'src/clipboard-navigation.js').read_text()+'\n'+m[2],new)
if '--check' in sys.argv:assert new==s,'Practice plans embedding differs';print('PASS Practice plans embedding')
else:p.write_text(new)
