"""Reconcile the linked Creator UI with released trainer and role-preview features.
No hosted connection, identity provisioning, permission grant or deletion is performed.
"""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
check='--check' in sys.argv

def put(path,text):
 p=root/path
 if check:
  assert p.read_text()==text, 'Generated release source differs: '+path
 else:p.write_text(text)
def replace_once(s,old,new):
 if new in s:return s
 assert s.count(old)==1, 'Unexpected release source near '+old[:70]
 return s.replace(old,new,1)

s=(root/'src/creator-offers.js').read_text()
s=replace_once(s,"<div id=\"creatorOfferStatus\" role=\"status\"></div>","<button id=\"creatorDashboardRolePreviewBtn\" type=\"button\" class=\"wide secondary hidden\">Explore Role Views · Demo</button><div id=\"creatorOfferStatus\" role=\"status\"></div>")
s=replace_once(s,"const actor=()=>identity()&&!document.body.classList.contains('kiosk-locked')", "const actor=()=>identity()&&!document.hidden&&!document.body.classList.contains('kiosk-locked')")
s=replace_once(s,"show('creatorReturnToTeam',false);status('');", "show('creatorReturnToTeam',false);show('creatorDashboardRolePreviewBtn',false);status('');")
s=replace_once(s,"show('creatorReturnToTeam',data.home_mode==='team'||accessMode==='team');", "show('creatorReturnToTeam',data.home_mode==='team'||accessMode==='team');\n  show('creatorDashboardRolePreviewBtn',!!window.WMCreatorRolePreview);")
s=replace_once(s,"$c('creatorReturnToTeam').onclick=()=>closeSheets();", "$c('creatorReturnToTeam').onclick=()=>closeSheets();\n $c('creatorDashboardRolePreviewBtn').onclick=()=>window.WMCreatorRolePreview?.open();")
put('src/creator-offers.js',s)
p=(root/'src/creator-role-preview.js').read_text()
p=replace_once(p,"function exit(){const target=opener;closeSheets();if(target?.isConnected&&!target.classList.contains('hidden'))target.focus()}","function exit(){const target=opener,returnToDashboard=target?.id==='creatorDashboardRolePreviewBtn'&&owner===context()&&unlocked()&&navigator.onLine;closeSheets();if(returnToDashboard){void window.WMCreatorOffers?.open();return}if(target?.isConnected&&!target.classList.contains('hidden'))target.focus()}")
put('src/creator-role-preview.js',p)
# The generated test keeps every original linked-workspace assertion and adds real
# dashboard -> sandbox -> dashboard clicks without copying a session into the demo.
t=(root/'tests/creator-linked-access-browser.cjs').read_text()
old=" await ctx.setOffline(true);await p.waitForSelector('#creatorOffersSheet.hidden',{state:'attached'});"
new=""" await p.locator('#creatorDashboardRolePreviewBtn').click();
 await p.waitForSelector('#creatorRolePreviewFrame');
 const demo=p.frameLocator('#creatorRolePreviewFrame');
 await demo.locator('#demoRole').selectOption('trainer');
 assert.equal(await p.evaluate(()=>session.user.id),'linked-personal');
 assert.equal(await p.evaluate(()=>JSON.stringify([activeTeam,activeSeason,availableTeams,actualIsStaff,isStaff,actualIsTeamAdmin,isTeamAdmin,canWeighIn])===teamBefore),true);
 const content=await p.locator('#creatorRolePreviewFrame').getAttribute('srcdoc');
 assert(!content.includes('linked-personal'));assert(!content.includes('team-fixture'));
 assert.equal(await p.evaluate(()=>fixture.writes.length),0);
 await p.screenshot({path:'validation/creator-linked-role-preview-phone.png'});
 await p.locator('#creatorRolePreviewClose').click();
 await p.waitForSelector('#creatorNewOffer');
 assert.equal(await p.locator('#creatorRolePreviewFrame').count(),0);
 assert.equal(await p.locator('#creatorReturnToTeam').isVisible(),true);
 assert.equal(await p.evaluate(()=>session.user.id),'linked-personal');
 await p.screenshot({path:'validation/creator-linked-complete-dashboard-phone.png'});
 console.log('PASS Personal login opens fictional role previews from Creator and returns to the same dashboard without changing team context');
 await ctx.setOffline(true);await p.waitForSelector('#creatorOffersSheet.hidden',{state:'attached'});"""
assert t.count(old)==1,'Unexpected linked browser test boundary'
put('tests/creator-linked-release-browser.cjs',t.replace(old,new))
for script in ['patch-creator-offers.py','patch-creator-role-preview.py']:
 subprocess.run([sys.executable,str(root/'scripts'/script)]+(['--check'] if check else []),check=True,cwd=root)
for path in ['index.html','sw.js']:
 s=(root/path).read_text()
 assert '0.20.113' in s or '0.20.114' in s,'Unexpected release version: '+path
 put(path,s.replace('0.20.113','0.20.114').replace('Creator role previews with fictional, isolated account views.','Shared Creator dashboard with personal-login access and fictional role previews.'))
print('PASS Linked Creator release embeds previews and keeps web/service-worker version paired')
