"""Synchronize reviewed public support/privacy pages with their in-app views.

The standalone pages are the source of truth. Keep published disclosure guards;
release versioning belongs to prepare-web-updates.py. This does not activate a
service or establish completion of the outstanding device/privacy acceptance.
"""
from pathlib import Path
import re
import sys
from launch_privacy_disclosures import preserve_privacy

ROOT = Path(__file__).resolve().parents[1]
CHECK = '--check' in sys.argv
privacy = preserve_privacy((ROOT / 'privacy.html').read_text())
support = (ROOT / 'support.html').read_text()

# Fail if regeneration would silently remove reviewed permissions or boundaries.
for passage in (
    'Younger athletes and guardian authority',
    'An adult reviewer is not automatically a legal guardian',
    'A season or membership period is not a retention schedule.',
    'Render',
    'Production subscriptions remain disabled',
    'Account deletion does not cancel an Apple subscription',
):
    assert passage in privacy, 'Missing privacy disclosure: ' + passage
for page in (privacy, support):
    assert 'October 5, 2026' in page, 'Unexpected disclosure checkpoint'
    assert 'My Account → Account deletion' in page
    assert 'specifically enrolled test accounts' not in page
    assert 'specifically enrolled disposable accounts' not in page
    assert 'support@theteammanager.app' in page

index = (ROOT / 'index.html').read_text()
for kind, page in [('Support', support), ('Privacy', privacy)]:
    body = re.search(r'</nav>([\s\S]*?)<footer class="wm-doc-footer">', page)
    assert body, 'Missing page content: ' + kind
    pattern = r'(<template id="wm' + kind + r'Template">)[\s\S]*?(</template>)'
    assert len(re.findall(pattern, index)) == 1, 'Unexpected template: ' + kind
    index = re.sub(pattern, lambda match: match[1] + body[1] + match[2], index)
for name, text in [('privacy.html', privacy), ('index.html', index)]:
    target = ROOT / name
    if CHECK:
        assert target.read_text() == text, 'Generated information differs: ' + name
    else:
        target.write_text(text)
print('PASS current public/embedded support and privacy match; preserved disclosure boundaries')
