#!/usr/bin/env python3
"""Check 0.20.101 syntax and preserve code outside the two login UI functions."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib, json, re, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = '1e5340dd4a8eb54af640e5287339c38de37ee8d8'
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
# Biometric credential reads, enrollment, and server authentication must be unchanged.
for start,end in [(' async function signIn(){', ' async function enroll(ev){'), (' async function enroll(ev){', ' async function forget(){'), (' async function forget(){', ' function auto(){')]:
    assert old[old.index(start):old.index(end)] == new[new.index(start):new.index(end)], 'Biometric authentication flow changed'
syntax = 0
with tempfile.TemporaryDirectory() as temp:
    for i, (before, after) in enumerate(zip(a.blocks, b.blocks)):
        assert before['attrs'] == after['attrs'], 'Script attributes changed'
        def outside_login_ui(text):
            for start, end in [('function chooseSignInMode(team){', 'async function callTeamLogin('), ('function openSignUp(){', 'async function createPersonalAccount('), ('function refresh(){', 'function isTeamRecorderLogin('), ('window.WMQuickSignIn=(()=>{', 'if(window.wrestlingManagerSignInReady)')]:
                text = re.sub(re.escape(start) + r'[\s\S]*?(?=' + re.escape(end) + ')', '', text)
            return text
        assert outside_login_ui(before['text']) == outside_login_ui(after['text']), f'Unexpected code change in script {i}'
        if 'src' in after['attrs'] or after['attrs'].get('type', '') not in ('', 'module', 'text/javascript', 'application/javascript'): continue
        file = Path(temp) / (str(i) + '.js')
        file.write_text(after['text'])
        subprocess.run(['node', '--check', str(file)], check=True, capture_output=True)
        syntax += 1
result = {'release': '0.20.101', 'baseline_commit': BASE, 'syntax_checks': syntax,
          'preservation': 'Account creation, invitations, authorization and biometric credential/enrollment flows are byte-identical. Changes are limited to login navigation, refresh notification and the biometric preference/prompt UI.',
          'index_sha256': hashlib.sha256(new.encode()).hexdigest()}
(ROOT / 'validation/login-onboarding-source.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'{syntax} syntax checks passed; unrelated script code preserved.')
