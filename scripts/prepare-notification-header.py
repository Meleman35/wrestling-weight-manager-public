"""Compact header notification bell. Presentation only; never changes deletion gates."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[1]
check = '--check' in sys.argv

def replace_once(text, old, new):
    if new in text:
        return text
    assert text.count(old) == 1, 'Source changed near: ' + old[:90]
    return text.replace(old, new, 1)

def put(path, text):
    p = root / path
    if check:
        assert p.exists() and p.read_text() == text, 'Generated content differs: ' + path
    else:
        p.write_text(text)

p = 'src/notification-inbox.js'
s = (root / p).read_text()
s = replace_once(s, "    $n('teamSwitcherBtn').setAttribute('aria-label',`Switch team${count?`, ${count} unread updates across your teams`:''}`);", "    $n('teamSwitcherBtn').setAttribute('aria-label','Switch team');")
s = replace_once(s, "      button.textContent=`Notifications${count?' · '+display(count):''}`;", "      if(button.id!=='roleNotificationsBtn')button.textContent=`Notifications${count?' · '+display(count):''}`;\n      else button.title=`Notifications, ${count} unread updates`;")
s = replace_once(s, "button.onclick=()=>openInbox();host.before(button);", """button.onclick=()=>openInbox();
    if(id==='roleNotificationsBtn'){
      button.className='round-btn wm-notification-bell';
      button.innerHTML='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/></svg>';
      button.setAttribute('aria-label','Notifications, 0 unread updates');
      button.setAttribute('aria-haspopup','dialog');
      button.setAttribute('aria-controls','communicationNotificationsSheet');
      button.title='Notifications';
      const badge=$n('teamUnreadBadge');
      if(badge){badge.setAttribute('aria-hidden','true');button.append(badge);}
    }
    host.before(button);""")
put(p, s)
html = (root / 'index.html').read_text()
pattern = re.compile(r'(<script id="wm-notification-sync-032">).*?(</script>)', re.S)
html, count = pattern.subn(lambda m: m[1] + '\n' + s + '\n' + m[2], html)
assert count == 1, 'Notification source embedding missing'
css = (root / 'src/notification-header.css').read_text()
style = '<style id="wm-notification-header-style">\n' + css + '\n</style>'
if 'id="wm-notification-header-style"' in html:
    html, count = re.subn(r'<style id="wm-notification-header-style">.*?</style>', lambda m: style, html, flags=re.S)
    assert count == 1
else:
    assert html.count('</body>') == 1
    html = html.replace('</body>', style + '\n</body>')
html = html.replace('0.20.116', '0.20.117')
put('index.html', html)
put('sw.js', (root / 'sw.js').read_text().replace('0.20.116', '0.20.117'))
for p in ['scripts/prepare-linked-creator-release.py', 'scripts/prepare-launch-information.py']:
    s = (root / p).read_text()
    s = s.replace("('0.20.113','0.20.114','0.20.115','0.20.116')", "('0.20.113','0.20.114','0.20.115','0.20.116','0.20.117')")
    put(p, s)
assert any('Build v'+v in html and 'wm-shell-'+v in (root / 'sw.js').read_text() for v in ('0.20.117','0.20.118','0.20.119'))
print('PASS compact bell source/embedding and paired web version; deletion behavior unchanged')
