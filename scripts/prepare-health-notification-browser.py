from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
s=(root/'tests/athlete-health-browser.cjs').read_text()
marker='await p.evaluate(()=>WMAthleteHealth.open());'
assert marker in s
s=s[:s.index(marker)]+(root/'tests/health-notifications-browser-cases.js').read_text()+"\n})().catch(e=>{console.error(e);process.exit(1)});\n"
p=root/'tests/health-notifications-browser.cjs'
if '--check' in sys.argv:assert p.read_text()==s
else:p.write_text(s)
print('PASS Care-notification browser cases reuse the complete synthetic app harness')
