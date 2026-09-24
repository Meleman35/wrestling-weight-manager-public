#!/usr/bin/env python3
"""Check 0.20.37 syntax and preserve code outside the two login UI functions."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib, json, re, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = '129d8dfc8e2f3c9787c7114af6f3519d760c4882'
class Scripts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.blocks = []
        self.current = None
    def handle_starttag(self, tag, attrs):
        if tag == 'script': self.current = {'attrs': dict(attrs), 'text': ''}
    def handle_data(self, data):
        if self.current is not None: self.current['text'] += data
    def handle_endtag(self, tag):
        if tag == 'script' and self.current is not None:
            self.blocks.append(self.current)
            self.current = None

old = subprocess.check_output(['git', 'show', BASE + ':index.html'], cwd=ROOT).decode()
new = (ROOT / 'index.html').read_text()
a, b = Scripts(), Scripts()
a.feed(old)
b.feed(new)
assert len(a.blocks) == len(b.blocks), 'Unexpected script count change'
syntax = 0
with tempfile.TemporaryDirectory() as temp:
    for i, (before, after) in enumerate(zip(a.blocks, b.blocks)):
        assert before['attrs'] == after['attrs'], 'Script attributes changed'
        def outside_login_ui(text):
            for start, end in [('function chooseSignInMode(team){', 'async function callTeamLogin('), ('function openSignUp(){', 'async function createPersonalAccount(')]:
                text = re.sub(re.escape(start) + r'[\s\S]*?(?=' + re.escape(end) + ')', '', text)
            return text
        assert outside_login_ui(before['text']) == outside_login_ui(after['text']), f'Unexpected code change in script {i}'
        if 'src' in after['attrs'] or after['attrs'].get('type', '') not in ('', 'module', 'text/javascript', 'application/javascript'): continue
        file = Path(temp) / (str(i) + '.js')
        file.write_text(after['text'])
        subprocess.run(['node', '--check', str(file)], check=True, capture_output=True)
        syntax += 1
result = {'release': '0.20.37', 'baseline_commit': BASE, 'syntax_checks': syntax,
          'preservation': 'All script code outside chooseSignInMode and openSignUp is byte-identical, including account creation, invitation handling, permissions and native bridges.',
          'index_sha256': hashlib.sha256(new.encode()).hexdigest()}
(ROOT / 'validation/login-onboarding-source.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'{syntax} syntax checks passed; unrelated script code preserved.')
