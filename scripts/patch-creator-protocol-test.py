"""Keep deletion assertions intact while expecting the linked-Creator access protocol."""
from pathlib import Path
import sys
p=Path(__file__).resolve().parents[1]/'tests/account-deletion-phone-browser.cjs'
s=p.read_text()
old="assert.deepEqual(reopenedCalls.find(c=>c.name==='creator_offers_request').args,{p_action:'access',p_data:{}});"
new="assert.deepEqual(reopenedCalls.find(c=>c.name==='creator_offers_request').args,{p_action:'access',p_data:{client:'creator-linked-v1'}});"
assert s.count(old)+s.count(new)==1,'Unexpected Creator read-only protocol assertion'
out=s.replace(old,new)
assert "assert.deepEqual(reopenedCalls.map(c=>c.name).sort(),['account_deletion_scope_preflight','creator_offers_request']);" in out
assert "assert.equal(await page.evaluate(()=>fixture.writes.length),0);" in out
if '--check' in sys.argv:assert s==out,'Expected Creator protocol is stale'
else:p.write_text(out)
print('PASS Exact Creator access protocol; existing deletion assertions unchanged')
