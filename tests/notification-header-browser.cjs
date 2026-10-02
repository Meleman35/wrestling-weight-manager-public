/* Reuse the full synthetic care/inbox fixture and all its existing regressions. */
let source = require('fs').readFileSync('tests/health-notifications-browser.cjs','utf8');
if(process.env.WM_TEST_CHROMIUM)source=source.replace('headless:true,', 'headless:true,executablePath:'+JSON.stringify(process.env.WM_TEST_CHROMIUM)+',');
const marker = 'await p.evaluate(()=>WMAthleteHealth.open());await p.waitForSelector';
if(source.split(marker).length !== 2)throw Error('Care fixture entry changed');
const checks = `
await p.evaluate(()=>{
 document.getElementById('headerTeamName').textContent='Demo Girls Wrestling';
 document.getElementById('headerSeasonName').textContent='2026-27 season';
});
for(const width of [320,390,430,768]){
 await p.setViewportSize({width,height:844});
 for(const count of [0,1,105]){
  await p.evaluate(count=>{healthTest.notices=Array.from({length:count},(_,i)=>({id:'header-'+i,user_id:'trainer',team_id:'team-a',category:'system',title:'Synthetic update',body:'Fixture only',created_at:new Date().toISOString(),read_at:null}));return WMNotificationSync.refresh()},count);
  const layout=await p.evaluate(()=>{
   const rect=id=>{const r=document.getElementById(id).getBoundingClientRect();return {x:r.x,right:r.right,width:r.width,height:r.height}};
   const bell=document.getElementById('roleNotificationsBtn');
   return {team:rect('teamSwitcherBtn'),bell:rect('roleNotificationsBtn'),profile:rect('profileBtn'),icon:bell.querySelectorAll('svg').length,badgeOwner:document.getElementById('teamUnreadBadge').parentElement.id,label:bell.getAttribute('aria-label'),overflow:document.documentElement.scrollWidth>innerWidth+1};
  });
  assert.equal(layout.icon,1);assert.equal(layout.badgeOwner,'roleNotificationsBtn');
  assert.equal(layout.overflow,false);assert.equal(layout.bell.width,44);assert.equal(layout.bell.height,44);
  assert(layout.team.right<=layout.bell.x);assert(layout.bell.right<=layout.profile.x);
  assert(layout.team.width>=width-140);assert.match(layout.label,new RegExp(count+' unread'));
  assert.equal(await p.locator('#teamUnreadBadge').isVisible(),count>0);
  if(count)assert.equal(await p.locator('#teamUnreadBadge').innerText(),count>99?'99+':String(count));
 }
}
pass('Compact bell preserves team-name space at 320/390/430/768px and keeps its icon after unread refresh, including 99+');
await p.setViewportSize({width:390,height:844});
await p.locator('#roleNotificationsBtn').focus();await p.keyboard.press('Enter');
assert(await p.locator('#communicationNotificationsSheet').isVisible());assert.equal(await p.locator('#teamSwitcherSheet').isVisible(),false);
await p.evaluate(()=>closeSheets());await p.locator('#teamSwitcherBtn').click();
assert(await p.locator('#teamSwitcherSheet').isVisible());assert.equal(await p.locator('#communicationNotificationsSheet').isVisible(),false);
await p.evaluate(()=>{closeSheets();healthTest.notices=[];return WMNotificationSync.refresh()});
await p.locator('.app-header').screenshot({path:'validation/notification-header-phone.png'});
pass('Bell keyboard action opens only the inbox; team switcher still opens only team selection; no notification or care access rules changed');
`;
eval(source.replace(marker,checks+'\n'+marker));
