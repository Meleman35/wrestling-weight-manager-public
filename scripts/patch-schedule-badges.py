"""Idempotent, fail-closed embedding of the schedule-only correction. No network access."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
p = root / 'index.html'
s = p.read_text()
original = s
source = (root / 'src/schedule-badges.js').read_text()
start = '<script id="scheduleBadges094Script">'
block = start + '\n' + source + '</script>\n'
if start in s:
    s, n = re.subn(r'<script id="scheduleBadges094Script">.*?</script>\n', lambda _: block, s, flags=re.S)
    assert n == 1
else:
    anchor = '  <script>\nconst INVITE_EMAIL_REMINDER = '
    assert s.count(anchor) == 1
    s = s.replace(anchor, block + anchor)

def replace(old, new):
    global s
    if new in s:
        assert old not in s
        return
    assert s.count(old) == 1, old[:100]
    s = s.replace(old, new)

replace("function markNavSeen(name){\n  if(!session?.user?.id||!activeTeam?.id)return;",
        "function markNavSeen(name){\n  if(name==='schedule'){window.WMScheduleBadges.markSeen();return;}\n  if(!session?.user?.id||!activeTeam?.id)return;")
replace("  const scheduleSeen=navSeenAt('schedule');\n  const scheduleCount=(scheduleRows||[]).filter(row=>new Date(row.updated_at||row.created_at||0).getTime()>scheduleSeen).length;",
        "  const scheduleCount=window.WMScheduleBadges.count();")
replace("  activeTeam=team;\n  syncOrganizationForTeam(team);",
        "  activeTeam=team;\n  window.WMScheduleBadges.reset();scheduleRows=[];setNavBadge('schedule',0,'unseen schedule changes');\n  syncOrganizationForTeam(team);")
replace("if(session?.user?.id!==nextSession?.user?.id){++communicationThreadOpenSequence;",
        "if(session?.user?.id!==nextSession?.user?.id){window.WMScheduleBadges.reset();scheduleRows=[];setNavBadge('schedule',0,'unseen schedule changes');++communicationThreadOpenSequence;")
old = """async function loadSchedule(){
  if (!activeTeam) return;
  const { data, error } = await client.from('team_events').select('*').eq('team_id',activeTeam.id).order('starts_at',{ascending:true});
  if (error){ message(error.message,true); return; }
  const opsTeamId=activeTeam?.id;
  const orgEvents=window.WMOperations?await window.WMOperations.calendar(opsTeamId):[];
  if(activeTeam?.id!==opsTeamId)return;
  scheduleRows=[...(data||[]),...orgEvents].sort((a,b)=>String(a.starts_at).localeCompare(String(b.starts_at)));
  renderSchedule(); renderUpcomingHome(); renderAttention(); updateBottomNavBadges();
}"""
new = """async function loadSchedule(){
  const request=window.WMScheduleBadges.begin();if(!request)return;
  try{
    const {data,error}=await client.from('team_events').select('*').eq('team_id',request.teamId).order('starts_at',{ascending:true});
    if(!window.WMScheduleBadges.valid(request))return;
    if(error)throw error;
    const orgEvents=window.WMOperations?await window.WMOperations.calendar(request.teamId):[];
    if(!window.WMScheduleBadges.valid(request))return;
    scheduleRows=[...(data||[]),...orgEvents].sort((a,b)=>String(a.starts_at).localeCompare(String(b.starts_at)));
    renderSchedule();renderUpcomingHome();renderAttention();
    window.WMScheduleBadges.accept(request,scheduleRows);
    if(!document.hidden&&!$('scheduleTab').classList.contains('hidden'))window.WMScheduleBadges.markSeen();
    updateBottomNavBadges();
  }catch(error){if(window.WMScheduleBadges.valid(request))message(error.message||'Schedule could not load. Please try again.',true);}
}"""
replace(old, new)
# Version changes only apply when preparing this release; future embeddings retain newer versions.
if 'Build v0.20.93' in s:
    s=s.replace('Build v0.20.93','Build v0.20.94')
    s=s.replace('Wrestling Manager v0.20.93: Quiet, read-only conversation review for approved adult helpers.',
                'Wrestling Manager v0.20.94: Quiet first-load schedule badges and account/team-safe schedule responses.')
sw = root / 'sw.js'
w = sw.read_text()
updated_w = w.replace("const CACHE='wm-shell-0.20.93';", "const CACHE='wm-shell-0.20.94';")
if '--check' in sys.argv:
    assert s == original, 'index.html differs from the checked schedule source/patch'
    assert updated_w == w, 'Service worker version does not match this release'
    print('PASS exact schedule embedding and service-worker version')
else:
    p.write_text(s)
    sw.write_text(updated_w)
    print('Prepared schedule badge bundle; no deployment performed')
