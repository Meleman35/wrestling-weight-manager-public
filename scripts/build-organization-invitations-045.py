"""Embed organization invitations and their guarded 0.20.42 integration once."""
from pathlib import Path
import hashlib, re
root=Path(__file__).resolve().parents[1]
p=root/'index.html'; s=p.read_text()
def replace(old,new):
 global s
 assert s.count(old)==1, (old[:100],s.count(old))
 s=s.replace(old,new,1)
if 'id="wmOrgInvites045"' not in s:
 # Reconciled against current 0.20.48 source; specific anchors are asserted below.
 s=s.replace('v0.20.48','v0.20.49')
 replace('Larger Locker Room recording entry for phones.','Direct organization leadership invitations and organization-only onboarding. Draft.')
 replace('Create a team or connect to one you were invited to.','Open your organization, accept an invitation, or connect to a team.')
 replace('<div class="card" id="setupAccountStatus">','<div id="setupOrganizations" class="card hidden"></div>\n    <div class="card" id="setupAccountStatus">')
 s=s.replace('Check Team Access','Check Access')
 replace('Accept a private coach/staff invitation or create your own team. No athlete profile or child connection is required.','Accept a private organization or coach/staff invitation, or create your own team. No athlete profile or child connection is required.')
 replace("if(pendingInviteToken.toUpperCase().startsWith('WMM-'))role='team_leader';","if(/^WM[MO]-/i.test(pendingInviteToken))role='team_leader';")
 replace("role==='team_leader'?'Accept a Coach / Staff Invitation'","role==='team_leader'?'Accept a Leadership Invitation'")
 replace('Paste the private WMM invitation sent by your team administrator.','Paste the WMO organization invitation or WMM staff invitation sent by your administrator.')
 s=s.replace('Use your athlete, parent/guardian, or coach/staff invitation here.','Use your organization, athlete, parent/guardian, or coach/staff invitation here.')
 replace('<b>Joining an existing team?</b><br>Ask its administrator for a Coach / Team Leader invitation from Clipboard → Edit Team Leaders. Use the same email they invite. They choose your role and tools; no athlete profile or child connection is required.','<b>Joining organization leadership?</b><br>Ask an organization administrator to invite you from Organization → Leadership invitations. Use the invited email; no team or athlete profile is required.<br><br>For a team coaching role, ask its administrator for an invitation from Clipboard → Edit Team Leaders.')
 replace('placeholder="WMWA-… / WMWG-… / WMM-…"','placeholder="WMO-… / WMM-… / athlete or parent invite"')
 replace("if(!/^WMM-/i.test(token)){","if(!/^WM[MO]-/i.test(token)){")
 replace("return /^WMM-[a-zA-Z0-9-]+$/.test(token)?token:'';","return /^WM[MO]-[a-zA-Z0-9-]+$/.test(token)?token:'';")
 replace('Enter the private WMM staff invitation. A team join code does not assign staff access.','Enter the private WMO organization or WMM staff invitation. A team code does not assign leadership access.')
 replace("const token=typeof providedToken==='string'?providedToken:$('inviteToken').value.trim();","const raw=typeof providedToken==='string'?providedToken:$('inviteToken').value.trim();\n  const token=staffInvitationToken(raw)||raw;")
 replace("let result;\n    if(token.toUpperCase().startsWith('WMWA-'))", "let result,organizationResult=null;\n    if(token.startsWith('WMO-')){organizationResult=await WMOrgInvites.accept(token);if(!organizationResult){status.textContent='Invitation not accepted. You can open it again when ready.';return;}result={data:organizationResult};}\n    else if(token.toUpperCase().startsWith('WMWA-'))")
 replace('Use an athlete, guardian, or adult staff invitation token.','Use an organization, athlete, guardian, or adult staff invitation token.')
 replace("await refresh();message('Invitation accepted. Welcome to the team.');", "await refresh();if(session?.user?.id!==uid)return;\n    if(organizationResult){await WMOperations.open(organizationResult.organization_id);message(organizationResult.already_accepted?'This organization invitation was already accepted.':'Organization invitation accepted.');}\n    else message('Invitation accepted. Welcome to the team.');")
 replace('async function refreshAccountView(){\n  if(teamProfileChoice||teamLoginSigningOut)return;', 'async function refreshAccountView(){\n  if(teamProfileChoice||teamLoginSigningOut)return;\n  window.WMOrgInvites?.resetHome();')
 replace("if (!orgIds.length && !teamIds.length){\n    show('setupView', true);", "if (!orgIds.length && !teamIds.length){\n    activeTeam=null;availableTeams=[];\n    show('setupView', true);")
 replace('await WMOnboarding.render();WMOnboarding.resume();\n    return;','await WMOnboarding.render();await window.WMOrgInvites?.showHome();WMOnboarding.resume();\n    return;')
 replace("if(!availableTeams.length){ show('setupView',true); show('appView',false); await WMOnboarding.render();WMOnboarding.resume();return; }", "if(!availableTeams.length){ activeTeam=null;show('setupView',true); show('appView',false); await WMOnboarding.render();await window.WMOrgInvites?.showHome();WMOnboarding.resume();return; }")
 replace("const labels={home:'Overview',positions:","const labels={home:'Overview',invitations:'Leadership invitations',positions:")
 s=s.replace('window.WMOrgStructure?.close();','window.WMOrgStructure?.close();window.WMOrgInvites?.close();')
 replace("['affiliates','meetings','voting'].includes(tab)","['invitations','affiliates','meetings','voting'].includes(tab)")
 replace("Object.entries(labels).map(([key,label])=>", "Object.entries(labels).filter(([key])=>key!=='invitations'||hub.admin).map(([key,label])=>")
 replace("if(tab==='home'){home();return;}","if(tab==='home'){home();return;}\n  if(tab==='invitations'){if(hub.admin)WMOrgInvites.open({org});else $o('opsContent').textContent='Organization administrator access required.';return;}")
 replace("const tiles=[\n   ['meetings'", "const tiles=[\n   ...(hub.admin?[['invitations','✉️','Leadership invitations','Invite leaders directly to your organization']]:[]),\n   ['meetings'")
 replace("$o('opsSwitchTeams').onclick=()=>{closeSheets();openTeamSwitcher();};", "$o('opsSwitchTeams').hidden=!availableTeams.length;$o('opsSwitchTeams').nextElementSibling.hidden=!availableTeams.length;\n  $o('opsSwitchTeams').onclick=()=>{closeSheets();openTeamSwitcher();};")
 replace("Give this code to your organization administrator so they can assign your role.","Ask an organization administrator to invite your email from Leadership invitations. A WMO invitation does not require joining a team.")
 replace('</body>','<dialog id="organizationInviteReview" aria-labelledby="oiReviewTitle"></dialog>\n</body>')
 replace('<script>\n/* v0.20.5 organization operations.','<style id="wmOrgInvites045Style"></style>\n<script id="wmOrgInvites045"></script>\n<script>\n/* v0.20.5 organization operations.')
if "chooseSignUpRole(pendingInviteToken.toUpperCase().startsWith('WMM-')?" in s:
 replace("chooseSignUpRole(pendingInviteToken.toUpperCase().startsWith('WMM-')?", "chooseSignUpRole(/^WM[MO]-/i.test(pendingInviteToken)?")
for tag,id,file in [('script','wmOrgInvites045','src/organization-invitations.js'),('style','wmOrgInvites045Style','src/organization-invitations.css')]:
 pattern=rf'<{tag} id="{id}">.*?</{tag}>'
 assert len(re.findall(pattern,s,re.S))==1
 s=re.sub(pattern,lambda _:f'<{tag} id="{id}">\n'+(root/file).read_text()+f'\n</{tag}>',s,flags=re.S)
p.write_text(s)
