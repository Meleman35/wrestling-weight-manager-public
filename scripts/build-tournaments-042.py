from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
s=s.replace('<!-- Wrestling Manager v0.20.41: Cross-team notification badges, wrestling reactions and invite email reminders. -->','<!-- Wrestling Manager v0.20.42: Reliable team link copying, customizable Clipboard categories and manual Tournament Day. -->').replace('Build v0.20.41','Build v0.20.42')
def replace(old,new):
 global s
 if old not in s: raise ValueError('Missing anchor: '+old[:100])
 s=s.replace(old,new,1)
if 'const JOIN_PUBLIC_BASE_042' not in s:
 replace("function teamJoinUrl(code){\n  const u=new URL(location.href);","const JOIN_PUBLIC_BASE_042 = 'https://meleman35.github.io/wrestling-weight-manager-public/';\nfunction teamJoinUrl(code){\n  const u=new URL(/^https?:$/.test(location.protocol)?location.href:JOIN_PUBLIC_BASE_042);")
if 'id="clipboardCustomizeBtn"' not in s:
 replace('<div id="clipboardCategories">','<div id="clipboardCategories">\n <button id="clipboardCustomizeBtn" type="button" class="wide secondary">↕ Customize Clipboard</button>')
 replace('<h3 class="subhead">More</h3>','<div id="clipboardLayoutEditors"></div><h3 class="subhead">Toolbox</h3>')
 replace("group==='quick'?document.querySelector('.quick-grid'):$('moreMenuCard');", "group==='quick'?document.querySelector('.quick-grid'):group==='more'?$('moreMenuCard'):window.WMClipboard?.parent(group);")
 replace("||(group==='more'&&key==='account');", "||(group==='more'&&key==='account')||(group==='clipboard'&&key==='settings')||(group==='clip_settings'&&key==='accountBtn');")
 replace('function normalizedLayout(source={}){','function normalizedLayout(source={}){\n source=window.WMClipboard?.upgrade(source)||source;')
 replace("renderLayoutGroup('quick','quickLayoutEditor');}","renderLayoutGroup('quick','quickLayoutEditor');window.WMClipboard?.editors();}")
 # Live-copy handler is embedded once into the main script, preserving global call sites.
 start=s.index('async function copyText(text)');end=s.index('function shareByText',start)
 s=s[:start]+'/* JOIN_COPY_042_START */\n'+(root/'src/join-copy.js').read_text()+'/* JOIN_COPY_042_END */\n'+s[end:]
 start=s.index('async function showTeamJoin(){',s.index('async function submitJoinRequest') if 'async function submitJoinRequest' in s else s.index('function shareByText'))
 end=s.index('/* Request updates are invalidation',start)
 s=s[:start]+s[end:]
else:
 s=re.sub(r'/\* JOIN_COPY_042_START \*/.*?/\* JOIN_COPY_042_END \*/',lambda m:'/* JOIN_COPY_042_START */\n'+(root/'src/join-copy.js').read_text()+'/* JOIN_COPY_042_END */',s,flags=re.S)
s=re.sub(r'<script id="wm-clipboard-0.20.29">.*?</script>',lambda m:'<script id="wm-clipboard-0.20.29">\n'+(root/'src/clipboard-navigation.js').read_text()+'\n</script>',s,flags=re.S)
if 'id="tournamentSheet"' not in s:
 replace('<button id="teamGoalsBtn"', '<button id="tournamentDayBtn" type="button" class="menu-row"><span>🤼</span><div><b>Tournament Day</b><small>Bouts, mats &amp; next-match updates</small></div><i>›</i></button><button id="teamGoalsBtn"')
 replace('<section id="scheduleTab" class="tabview hidden">','<section id="scheduleTab" class="tabview hidden"><button type="button" id="tournamentScheduleBtn" class="wide secondary">🤼 Tournament Day</button>')
 replace('<div id="detailMeta"', '<button type="button" id="eventTournamentBtn" class="wide hidden">Open Tournament Day</button><div id="detailMeta"')
 replace("  openSheet('eventDetailSheet');\n}", "  show('eventTournamentBtn',activeEvent.event_type==='tournament'&&!managedLogin);\n  openSheet('eventDetailSheet');\n}")
 replace('function applyRoleUI(){','function applyRoleUI(){\n  window.WMTournaments?.sync();')
 replace('function closeSheets(){','function closeSheets(){\n  window.WMTournaments?.reset();')
 replace('async function activateTeam(teamId,{persist=true}={}){',"async function activateTeam(teamId,{persist=true}={}){\n  window.WMTournaments?.reset();show('tournamentSheet',false);")
 replace("if(session?.user?.id!==nextSession?.user?.id){", "if(session?.user?.id!==nextSession?.user?.id){window.WMTournaments?.reset();show('tournamentSheet',false);")
 replace("['agreementRecordsSheet'", "['tournamentSheet','agreementRecordsSheet'")
 replace('<section id="layoutEditorSheet"', '<section id="tournamentSheet" class="sheet hidden" aria-modal="true"><div class="sheet-handle"></div><div class="sheet-head"><div><div class="eyebrow">COMPETITION</div><h2>Tournament Day</h2></div><button type="button" class="icon-close" data-close-sheet>×</button></div><button type="button" id="tournamentRefresh" class="secondary">Refresh</button><p id="tournamentStatus" role="status" aria-live="polite"></p><div id="tournamentBody"></div></section>\n<section id="layoutEditorSheet"')
tags=[]
for name in ['tournament-provider','tournament-alerts','tournaments']:
 tag='<script id="wm-'+name+'-042">\n'+(root/('src/'+name+'.js')).read_text()+'\n</script>'
 pattern=r'\n*<script id="wm-'+name+r'-042">.*?</script>\n*'
 s=re.sub(pattern,'',s,flags=re.S)
 tags.append(tag)
s=re.sub(r'\n*</body>',lambda m:'\n'+'\n'.join(tags)+'\n</body>',s)
css='<style id="wm-tournaments-042">\n'+(root/'src/tournaments-042.css').read_text()+'\n</style>'
if '<style id="wm-tournaments-042">' in s:s=re.sub(r'<style id="wm-tournaments-042">.*?</style>',lambda m:css,s,flags=re.S)
else:s=s.replace('</head>',css+'\n</head>')
p.write_text(s)
print('Embedded join copying and Clipboard navigation')
