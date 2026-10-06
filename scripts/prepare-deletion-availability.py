"""Keep account-deletion availability visible without granting erasure authority."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
check = '--check' in sys.argv

def put(path, text):
    target = root / path
    if check:
        assert target.read_text() == text, 'Generated file differs: ' + path
    else:
        target.write_text(text)

def once(text, old, new):
    if new in text:
        return text
    assert text.count(old) == 1, 'Source drift near ' + old[:100]
    return text.replace(old, new, 1)

path = 'src/account-deletion-phone-test.js'
s = (root / path).read_text()
s = once(s, '/* Enrolled deletion choices. Each action requires its own server capability. */',
         '/* Visible deletion availability. Each action still requires its own server capability. */')
s = once(s, "document.getElementById('signOutBtn').after(card);return card;", "document.getElementById('signOutBtn').before(card);return card;")
start = s.index(' // Showing an entry is not authorization.') if ' // Showing an entry is not authorization.' in s else s.index(' async function refresh(){')
end = s.index(' // Clear account data immediately', start)
s = s[:start] + ''' // Showing an entry is not authorization. Counts and actions require a fresh,
 // validated current-account response; unavailable/error states have neither.
 function availability(status, text, retry=true){
  admitted=false;const box=mount();box.replaceChildren();
  box.dataset.availability=status;
  box.append(element('summary','Account deletion'));
  const message=element('p',text,'fine');message.id='deletionAvailabilityStatus';
  message.setAttribute('role','status');message.setAttribute('aria-live','polite');box.append(message);
  if(retry){const button=element('button','Check availability again','secondary wide');
   button.id='deletionAvailabilityRetry';button.type='button';button.onclick=()=>refresh();box.append(button);}
  return box;
 }
 async function preflight(){
  let timer;
  try{return await Promise.race([
   client.rpc('account_deletion_scope_preflight'),
   new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('unavailable')),12000);})
  ]);}finally{clearTimeout(timer);}
 }
 async function refresh(){
  const uid=actor();if(!uid||!visible()){reset();return;}
  closeConfirmation();const g=++epoch,token=session.access_token;
  const valid=()=>epoch===g&&actor()===uid&&session?.access_token===token&&visible();
  availability('checking','Checking account-deletion availability…',false);
  if(!navigator.onLine){availability('offline','Connect to the internet to check account deletion. No new deletion request has been started.');return;}
  try{
   const {data,error}=await preflight();
   if(!valid())return;
   if(error)throw Error('unavailable');
   if(data?.enabled===false){
    availability('unavailable','Account deletion is not available for this session. This beta currently limits deletion to approved test accounts. No new deletion request has been started.');return;
   }
   if(data?.enabled!==true||typeof data.deletion_enabled!=='boolean'||!validScopes(data)||data.subject_id!==uid||!Number.isFinite(Date.parse(data.checked_at))||fields.some(([key])=>!Number.isSafeInteger(data.counts?.[key])||data.counts[key]<0))throw Error('invalid response');
   admitted=true;const box=mount();box.dataset.availability='ready';box.replaceChildren();heading(box,data.actions);
   box.append(element('h3','Your personal account data'));box.append(element('p','These counts belong to your personal account. Choose the action below after reviewing them.','fine'));
   const list=element('dl');list.style.cssText='display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px 16px;margin:16px 0';
   for(const [key,label] of fields){list.append(element('dt',label));const n=element('dd',String(data.counts[key]));n.style.margin='0';n.dataset.count=key;list.append(n);}box.append(list);
   if(data.counts.teams_needing_handoff)box.append(element('p','Before personal account deletion: arrange another administrator or separately review closing each affected team or organization.','fine'));
   box.append(element('p','Counts can overlap and include retained records. Linked team and child records need a separate review. Files saved only on this phone are not counted.','fine'));
   box.append(element('p','Last checked '+new Date(data.checked_at).toLocaleString(),'fine'));
   scopeChoices(box,data.scopes,data.actions);
  }catch{
   if(!valid())return;
   availability('error','Account-deletion availability could not be checked. Reconnect and try again. No new deletion request has been started.');
  }
 }
''' + s[end:]
put(path, s)
path='tests/account-deletion-phone-browser.cjs'
s=(root/path).read_text()
s=once(s,"e.previousElementSibling.id==='signOutBtn'","e.nextElementSibling.id==='signOutBtn'")
s=once(s,'Account deletion is collapsed at the bottom; expanding shows counts and the final Delete Account button at phone width','Account deletion is collapsed above Sign Out; expanding shows counts and the final Delete Account button at phone width')
s=once(s,"await page.getByText('Stored data could not be checked. Reconnect and try again.').waitFor();","await page.getByText('Account-deletion availability could not be checked. Reconnect and try again. No new deletion request has been started.').waitFor();")
s=once(s,"fixture.preflight.enabled=false;return WMDeletionPhoneTest.refresh();});assert.equal(await page.locator('#deletionPhoneTestCard').count(),0);", "fixture.preflight.enabled=false;return WMDeletionPhoneTest.refresh();});assert.equal(await page.locator('#deletionPhoneTestCard').count(),1);assert.equal(await page.locator('[data-count]').count(),0);assert.equal(await page.locator('#deletionScopeType').count(),0);assert.equal(await page.locator('#deletionPhoneTestCard').getAttribute('data-availability'),'unavailable');")
put(path,s)
path='scripts/prepare-notification-header.py'
s=(root/path).read_text()
s=once(s,"assert 'Build v0.20.117' in html and 'wm-shell-0.20.117' in (root / 'sw.js').read_text()", "assert any('Build v'+v in html and 'wm-shell-'+v in (root / 'sw.js').read_text() for v in ('0.20.117','0.20.118','0.20.120','0.20.121','0.20.122','0.20.123'))")
put(path,s)
for path in ['index.html','sw.js','scripts/prepare-launch-information.py','scripts/prepare-linked-creator-release.py']:
    s=(root/path).read_text()
    if path.endswith('.py'):
        s=s.replace("'0.20.116','0.20.117'", "'0.20.116','0.20.117','0.20.118'") if "'0.20.118'" not in s else s
    else:
        s=s.replace('0.20.117','0.20.118')
    put(path,s)
subprocess.run([sys.executable,str(root/'scripts/patch-deletion-phone-test.py')]+(['--check'] if check else []),cwd=root,check=True)
print('PASS visible deletion availability and 0.20.118 embedding; no server authority changed')
