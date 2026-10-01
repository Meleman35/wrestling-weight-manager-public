from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
page = root / 'index.html'
original = page.read_text()
start, end = '<!-- BEGIN MAT MODE ENTRY -->', '<!-- END MAT MODE ENTRY -->'
block = start + '\n<script id="matModeEntryScript">\n' + (root / 'src/mat-mode-entry.js').read_text() + '\n</script>\n' + end
updated = re.sub(re.escape(start) + r'[\s\S]*?' + re.escape(end), lambda _: block, original) if start in original else original.replace('</body>', block + '\n</body>')
if '--check' in sys.argv:
    assert updated == original, 'Mat Mode entry embedding differs'
    print('PASS Mat Mode entry embedding')
else:
    page.write_text(updated)
