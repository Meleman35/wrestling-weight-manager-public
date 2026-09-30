"""Embed the read-only phone inventory. No network or deletion capability."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[1]
p = root / 'index.html'
s = original = p.read_text()
source = (root / 'src/account-deletion-phone-test.js').read_text()
block = '<script id="deletionPhoneTestScript">\n' + source + '</script>\n'
if '<script id="deletionPhoneTestScript">' in s:
    s, n = re.subn(r'<script id="deletionPhoneTestScript">.*?</script>\n', lambda _: block, s, flags=re.S)
    assert n == 1
else:
    assert s.count('</body>') == 1
    s = s.replace('</body>', block + '</body>')
def replace(old, new):
    global s
    if new in s:
        assert old not in s
        return
    assert s.count(old) == 1, old
    s = s.replace(old, new)
replace("async function openAccountSheet(){\n  const profile=", "async function openAccountSheet(){\n  window.WMDeletionPhoneTest?.reset();\n  const profile=")
replace("  openSheet('accountSheet');\n}\n\nasync function refreshProfileNames", "  openSheet('accountSheet');\n  void window.WMDeletionPhoneTest?.refresh();\n}\n\nasync function refreshProfileNames")
replace("function lockApp(){\n  if(!session", "function lockApp(){\n  window.WMDeletionPhoneTest?.reset();\n  if(!session")
if 'Build v0.20.94' in s:
    s=s.replace('Build v0.20.94','Build v0.20.95')
    s=s.replace('Wrestling Manager v0.20.94: Quiet first-load schedule badges and account/team-safe schedule responses.', 'Wrestling Manager v0.20.95: Private read-only deletion test setup.')
if 'Build v0.20.95' in s:
    s=s.replace('Build v0.20.95','Build v0.20.96')
    s=s.replace('Wrestling Manager v0.20.95: Private read-only deletion test setup.', 'Wrestling Manager v0.20.96: Bottom account-deletion dropdown and typed confirmation preview.')
sw=root / 'sw.js'
w=sw.read_text()
updated=w.replace("const CACHE='wm-shell-0.20.94';", "const CACHE='wm-shell-0.20.96';").replace("const CACHE='wm-shell-0.20.95';", "const CACHE='wm-shell-0.20.96';")
if '--check' in sys.argv:
    assert s == original, 'Phone setup bundle differs from source'
    assert updated == w, 'Service worker version differs'
    print('PASS exact phone test embedding')
else:
    p.write_text(s)
    sw.write_text(updated)
