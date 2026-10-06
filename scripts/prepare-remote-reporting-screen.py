#!/usr/bin/env python3
"""Prepare a COPY of index.html with dormant in-app remote reporting registration."""
from pathlib import Path
import argparse
import shutil
import datetime

parser=argparse.ArgumentParser()
parser.add_argument('index',type=Path)
args=parser.parse_args()
path=args.index.resolve()
source=path.read_text()
if 'remoteReportingBtn' in source:
    raise RuntimeError('Remote screen is already prepared. Nothing changed.')
anchors=['<section id="opsHubSheet"','function closeSheets(){','function lockApp(){','async function handleAuthViewChange(event,nextSession){','</body>']
for anchor in anchors:
    if source.count(anchor)!=1:
        raise RuntimeError('App source anchor differs: '+anchor+'. Nothing changed.')
menu='<button id="organizationHubBtn"'
if source.count(menu)!=1:
    raise RuntimeError('More menu anchor differs. Nothing changed.')
source=source.replace(menu,'<button id="remoteReportingBtn" class="menu-row" hidden type="button"><span>⚖️</span><div><b>Remote weigh-ins</b><small>Club and tournament reporting</small></div><i>›</i></button>'+menu)
source=source.replace('<section id="opsHubSheet"','''<section id="remoteReportingSheet" class="sheet ops-sheet hidden" aria-modal="true" role="dialog" aria-labelledby="remoteReportingTitle">
<div class="sheet-handle"></div><div class="sheet-head"><h2 id="remoteReportingTitle">Remote weigh-ins</h2><button class="icon-close" data-close-sheet aria-label="Close">×</button></div><div id="remoteReportingContent"></div></section>
<section id="opsHubSheet"''')
for anchor in ['function closeSheets(){','function lockApp(){']:
    source=source.replace(anchor,anchor+'\n  window.WMRemoteReporting?.close();')
source=source.replace('async function handleAuthViewChange(event,nextSession){','async function handleAuthViewChange(event,nextSession){\n  if(event!==\'TOKEN_REFRESHED\'&&event!==\'INITIAL_SESSION\')window.WMRemoteReporting?.close();')
source=source.replace('</body>','''<script type="module">
import {installRemoteReportingApp} from './src/remote-weighins-app.mjs';
window.WMRemoteReporting=installRemoteReportingApp({
  enabled:false, // Turn on with the reviewed service deployment, not independently.
  button:document.getElementById('remoteReportingBtn'),root:document.getElementById('remoteReportingContent'),
  beforeOpen:()=>closeSheets(),show:()=>openSheet('remoteReportingSheet'),hide:()=>show('remoteReportingSheet',false),
  getSession:async()=>{const {data,error}=await client.auth.getSession();if(error)throw error;return data.session},
  unlocked:()=>!securityState.appLockEnabled||securityUnlockedThisLaunch,
  personal:()=>!!session?.user?.id&&!managedLogin,publishableKey:SUPABASE_KEY
});
</script>
</body>''')
backup=path.with_name(path.name+'.remote-backup-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
shutil.copy2(path,backup)
try:
    path.write_text(source)
except Exception:
    shutil.copy2(backup,path)
    raise
print('Prepared dormant in-app screen registration. Backup:',backup)
print('No production service or feature flag was enabled.')
