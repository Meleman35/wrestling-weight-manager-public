from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
s=(root/'tests/athlete-health-db.mjs').read_text()
marker='await as(ids.coach);\nconst invitation='
assert s.count(marker)==1
s=s[:s.index(marker)]+'\nexport {db,ids,sessions,as,admin,rpc,denied,today,config};\n'
p=root/'tests/health-notification-fixture.mjs'
if '--check' in sys.argv:assert p.read_text()==s
else:p.write_text(s)
print('PASS Existing production-shaped synthetic health fixture reused without real records')
