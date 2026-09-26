from pathlib import Path
import subprocess,re,json
root=Path(__file__).resolve().parents[1]
s=(root/'index.html').read_text();base=subprocess.check_output(['git','show','82e89ca:index.html'],cwd=root,text=True)
scripts=lambda text: re.findall(r'<script\b[^>]*>.*?</script>',text,re.S)
before=scripts(base);after=scripts(s)
changed=[i for i,b in enumerate(before) if b not in after]
assert len(changed)==2, changed
# Main application role/team hooks and Match Book observation are the only old-script edits.
assert 'function applyRoleUI()' in before[changed[0]]
assert 'window.WMMatch=' in before[changed[1]]
scoring=lambda text:text[text.index('window.WMScoring ='):text.index('window.WMMatch=')]
assert scoring(base)==scoring(s), 'Shared scoring and rules must stay unchanged'
for file in ['mat-mode.html','app.js','styles.css','auth-confirm.html']:
 assert (root/file).read_bytes()==subprocess.check_output(['git','show','82e89ca:'+file],cwd=root),file
for name in ['video-pilot-core','video-upload','video-pilot','video-pilot-native','match-video']:
 assert (root/f'src/{name}.js').read_text() in s
subprocess.run(['python','scripts/embed-video-pilot.py'],cwd=root,check=True)
assert s==(root/'index.html').read_text(), 'Embedding must be idempotent'
result={'unrelatedInlineScriptsUnchanged':len(before)-2,'scoringEngineUnchanged':True,'standaloneMatModeUnchanged':True,'embeddingIdempotent':True,'releaseBuildLabel':'0.20.46'}
(root/'validation/video-pilot-source.json').write_text(json.dumps(result,indent=2))
print('PASS preservation of existing features, shared scoring, Mat Mode and idempotent embedding')
