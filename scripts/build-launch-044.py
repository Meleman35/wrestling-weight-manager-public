from pathlib import Path
import re, subprocess, sys

root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(root/'scripts/build-tournament-alerts-043.py')], check=True)
p = root/'index.html'
s = p.read_text()
s = s.replace('Wrestling Manager v0.20.43: Tournament alert choices and private background preparation.', 'Wrestling Manager v0.20.44: Team plan foundation and connected inventory tools.').replace('Build v0.20.43', 'Build v0.20.44')

def replace(old, new):
    global s
    if s.count(old) != 1:
        raise ValueError('Expected one anchor: '+old[:100])
    s = s.replace(old, new, 1)

if 'id="teamPlanSheet"' not in s:
    replace('<button id="communicationPreferencesBtn"', '<button id="teamPlanBtn" class="menu-row" type="button"><span>📋</span><div><b>Team Plan</b><small>This team’s access &amp; annual plan</small></div><i>›</i></button>\n    <button id="communicationPreferencesBtn"')
    replace('<section id="layoutEditorSheet"', '<section id="teamPlanSheet" class="sheet hidden" role="dialog" aria-modal="true" aria-labelledby="teamPlanTitle"><div class="sheet-handle"></div><div class="sheet-head"><div><div class="eyebrow">YOUR TEAM</div><h2 id="teamPlanTitle">Team Plan</h2></div><button type="button" class="icon-close" data-close-sheet aria-label="Close team plan">×</button></div><button type="button" id="teamPlanRefresh" class="secondary">Refresh plan</button><p id="teamPlanStatus" role="status" aria-live="polite"></p><div id="teamPlanBody"></div></section>\n<section id="layoutEditorSheet"')
    replace('function applyRoleUI(){', 'function applyRoleUI(){\n  window.WMTeamPlan?.sync();')
    replace('function closeSheets(){', 'function closeSheets(){\n  window.WMTeamPlan?.reset();')
    replace("['tournamentSheet','agreementRecordsSheet'", "['teamPlanSheet','tournamentSheet','agreementRecordsSheet'")
    replace('async function activateTeam(teamId,{persist=true}={}){', "async function activateTeam(teamId,{persist=true}={}){\n  window.WMTeamPlan?.reset();show('teamPlanSheet',false);")
    replace('if(session?.user?.id!==nextSession?.user?.id){', "if(session?.user?.id!==nextSession?.user?.id){window.WMTeamPlan?.reset();show('teamPlanSheet',false);")
    replace("$('clipboardEquipmentBtn')?.addEventListener('click',()=>message('Equipment tracking is already reserved in Clipboard and will activate when the equipment module is connected.'));", "$('clipboardEquipmentBtn')?.addEventListener('click',()=>window.WMExtras?.equipment().catch(e=>message(e.message,true)));")
    replace("$('clipboardFilesBtn')?.addEventListener('click',()=>message('Files & Photos is reserved in Clipboard and will activate when the file module is connected.'));", "$('clipboardFilesBtn')?.addEventListener('click',()=>window.WMExtras?.media().catch(e=>message(e.message,true)));")

start = s.index(' async function equipment(){') if '/* EQUIPMENT_044_START */' not in s else s.index('/* EQUIPMENT_044_START */')
end = s.index(' const tokenKey=id=>', start)
s = s[:start]+'/* EQUIPMENT_044_START */\n'+(root/'src/equipment-launch.js').read_text()+'/* EQUIPMENT_044_END */\n'+s[end:]
s = re.sub(r'\n*<script id="wm-team-plan-044">.*?</script>\n*', '', s, flags=re.S)
s = s.replace('</body>', '\n<script id="wm-team-plan-044">\n'+(root/'src/team-plan.js').read_text()+'\n</script>\n</body>')
css = '<style id="wm-team-plan-044">\n'+(root/'src/team-plan.css').read_text()+'\n</style>'
if '<style id="wm-team-plan-044">' in s:
    s = re.sub(r'<style id="wm-team-plan-044">.*?</style>', lambda _: css, s, flags=re.S)
else:
    s = s.replace('</head>', css+'\n</head>')
s = re.sub(r'</script>\s*<script id="wm-tournament-provider-042">', '</script>\n<script id="wm-tournament-provider-042">', s)
p.write_text(s)
print('Embedded team plan status and inventory tools; purchases remain unavailable')
