"""Apply 0.20.41 integration points once, then embed the owned source modules."""
from pathlib import Path
import re,json,subprocess,difflib,hashlib
root=Path(__file__).resolve().parents[1]
p=root/'index.html';s=p.read_text()
reminder='Can’t find your confirmation email, invitation, or team code? Check your Junk or Spam folder. If the email is there, mark it as Not Junk and return here to continue.'
def replace(old,new):
 global s
 assert s.count(old)==1,(old[:100],s.count(old))
 s=s.replace(old,new,1)
if 'id="communications041Style"' not in s:
 replace('<!-- Wrestling Manager v0.20.40: Goal accomplishments, replacements, Locker Room goals and parent-approved profile sharing. -->','<!-- Wrestling Manager v0.20.41: Cross-team notification badges, wrestling reactions and invite email reminders. -->')
 replace('Build v0.20.40','Build v0.20.41')
 replace('<span class="chev">⌄</span>','<span class="chev">⌄</span><i id="teamUnreadBadge" class="team-unread-badge hidden" aria-label="0 unread updates">0</i>')
 replace('<p class="team-switch-hint">Your role and permissions can be different on each team.</p>','<p id="teamNotificationHint" class="team-switch-hint">Your role and permissions can be different on each team.</p>')
 replace('<div id="teamChoiceList"','<button id="allTeamNotificationsBtn" type="button" class="wide secondary">All notifications</button>\n    <div id="teamChoiceList"')
 replace('<section id="messagesTab" class="tabview hidden">','<section id="messagesTab" class="tabview hidden">\n        <button id="otherTeamNotificationsBtn" type="button" class="wide hidden"></button>')
 replace('<p id="notificationSyncStatus"','<button id="notificationShowAllBtn" type="button" class="secondary hidden">Show all teams</button><p id="notificationSyncStatus"')
 replace('<button class="team-choice ${activeTeam?.id===t.id?', '<div class="team-choice-row"><button class="team-choice ${activeTeam?.id===t.id?')
 replace('</button>`).join(\'\'):\'<div class="empty-card">No teams available.</div>\';','</button><button type="button" class="team-notification-badge hidden" data-team-notifications="${esc(t.id)}" aria-label="Unread team updates">0</button></div>`).join(\'\'):\'<div class="empty-card">No teams available.</div>\';')
 replace("  show('createTeamBtn',canCreate);","  show('createTeamBtn',canCreate);window.WMNotificationSync?.render();")
 replace('  refreshTeamSwitcherConnections();','  refreshTeamSwitcherConnections();window.WMNotificationSync?.refresh();')
 replace("  $('communicationUnreadCount').textContent=unread>99?'99+':String(unread);","  if(window.WMNotificationSync)WMNotificationSync.render();else $('communicationUnreadCount').textContent=unread>99?'99+':String(unread);")
 replace('window.WMJoinSync?.changed(payload);});','});')
 replace("smsReplies=data||[];closeSheets();openSheet('textRepliesSheet');renderSmsReplies();","smsReplies=data||[];closeSheets();openSheet('textRepliesSheet');renderSmsReplies();return true;")
 replace('communicationSafetyFlags=data||[];renderCommunicationSafetyList();','communicationSafetyFlags=data||[];renderCommunicationSafetyList();return true;')
 replace("  const restoreScroll=()=>{","  window.WMReactions?.mount();\n  const restoreScroll=()=>{")
 replace('function closeSheets(){\n','function closeSheets(){\n  window.WMReactions?.reset();\n')
 replace('async function activateTeam(teamId,{persist=true}={}){','async function activateTeam(teamId,{persist=true}={}){\n  window.WMReactions?.reset();')
 replace("if(session?.user?.id!==nextSession?.user?.id){finishTileEditing(false);","if(session?.user?.id!==nextSession?.user?.id){window.WMNotificationSync?.reset();window.WMReactions?.reset();finishTileEditing(false);")
 replace('const SUPABASE_URL =',"const INVITE_EMAIL_REMINDER = "+json.dumps(reminder,ensure_ascii=False)+";\nconst SUPABASE_URL =")
 replace('<p class="fine">Already have an account? Sign in below.</p>','<p class="fine">Already have an account? Sign in below.</p><p class="invite-email-reminder">'+reminder+'</p>')
 replace('<p id="signUpStatus"','<p class="invite-email-reminder">'+reminder+'</p><p id="signUpStatus"')
 replace('<h2>Join a Team</h2>','<h2>Join a Team</h2><p class="invite-email-reminder">'+reminder+'</p>')
 replace('Check your spam folder too. A team request may still need coach approval after you sign in.','Check your Junk or Spam folder for the confirmation email, invitation, or team code. A team request may still need coach approval after you sign in.')
 replace('Check your email to confirm your account, then sign in to finish team setup.','Check your inbox and Junk or Spam folder to confirm your account, then sign in to finish team setup.')
 replace('Use the newest link. You can request another in one minute.','Check your Junk or Spam folder too. Use the newest link. You can request another in one minute.')
 replace("  if(!activeTeam)throw new Error('No active team selected.');", "  if(!activeTeam)throw new Error('No active team selected.');\n  if(String(messageType).endsWith('_invite')){textBody=(textBody||'')+'\\n\\n'+INVITE_EMAIL_REMINDER;htmlBody=(htmlBody||'')+'<p style=\"font-family:Arial,sans-serif;padding:12px;color:#66470a;background:#fff8df\">'+esc(INVITE_EMAIL_REMINDER)+'</p>';}" )
 s=s.replace('Invite email sent to ${email}.','Invite email submitted to ${email}. Ask them to check their inbox and Junk or Spam folder.')
 s=s.replace('Ask them to check their inbox and spam folder.','Ask them to check their inbox and Junk or Spam folder.')
 # Reminder travels with shared invitations; copying remains a clean URL.
 for old,new in [
  ('Join ${activeTeam.name} in Wrestling Manager: ${url}`','Join ${activeTeam.name} in Wrestling Manager: ${url}\\n\\n${INVITE_EMAIL_REMINDER}`'),
  ('Fill out your Wrestling Manager team registration here: ${url}`','Fill out your Wrestling Manager team registration here: ${url}\\n\\n${INVITE_EMAIL_REMINDER}`'),
  ("'Wrestling Manager team registration',url","'Wrestling Manager team registration. '+INVITE_EMAIL_REMINDER,url"),
  ('Join ${activeTeam.name} as your athlete profile: ${url}`','Join ${activeTeam.name} as your athlete profile: ${url}\\n\\n${INVITE_EMAIL_REMINDER}`'),
  ("'Private athlete invitation',url","'Private athlete invitation. '+INVITE_EMAIL_REMINDER,url"),
  ("Connect to ${accessAthleteRecord?.first_name||'your athlete'} in Wrestling Manager: ${url}`","Connect to ${accessAthleteRecord?.first_name||'your athlete'} in Wrestling Manager: ${url}\\n\\n${INVITE_EMAIL_REMINDER}`"),
  ("'Connect to your athlete',url","'Connect to your athlete. '+INVITE_EMAIL_REMINDER,url"),
  ("systemShare(invitation.teamName+' staff invitation',invitation.role,invitation.url)","systemShare(invitation.teamName+' staff invitation',invitation.role+'. '+INVITE_EMAIL_REMINDER,invitation.url)")]:
  replace(old,new)
 replace('Athletes or parents scan the same QR, fill out the information, and wait for coach approval.</div>','Athletes or parents scan the same QR, fill out the information, and wait for coach approval.</div><p class="invite-email-reminder">${esc(INVITE_EMAIL_REMINDER)}</p>')
 replace('Invitation created. They must sign in with the invited email.</p>','Invitation created. They must sign in with the invited email. Ask them to check Junk or Spam for their invitation and confirmation email.</p>')
 replace('</head>','<style id="communications041Style"></style>\n</head>')
 replace('</body>','<dialog id="messageReactionDialog" aria-labelledby="reactionTitle"><div class="reaction-heading"><h3 id="reactionTitle">React to message</h3><button type="button" data-reaction-close aria-label="Close reactions">×</button></div><p class="fine">Wrestling &amp; team reactions</p><div id="reactionChoices"></div><p id="reactionStatus" role="status" aria-live="polite"></p><button id="removeMessageReaction" type="button" class="secondary" hidden>Remove my reaction</button></dialog>\n<script id="wm-reactions-041"></script>\n</body>')
for tag,id,path in [('script','wm-notification-sync-032','src/notification-inbox.js'),('script','wm-reactions-041','src/message-reactions.js'),('style','communications041Style','src/communications-041.css')]:
 pattern=re.compile(r'(<'+tag+r' id="'+id+r'">).*?(</'+tag+'>)',re.S)
 content=(root/path).read_text();s,n=pattern.subn(lambda m:m[1]+'\n'+content+'\n'+m[2],s);assert n==1
p.write_text(s)
