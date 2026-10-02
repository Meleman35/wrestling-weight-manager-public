"""Prepare the held care-notification change. No hosted calls or account operations.
No release version is assigned until coordinated deployment is reviewed.
"""
from pathlib import Path
import re,sys,subprocess
root=Path(__file__).resolve().parents[1]
check='--check' in sys.argv
EXPECTED='73d4ab1a9cf488dc3a0112e1895813cab8698e46335e7f64a9a94d28f1597246'
def replace(s,old,new):
 assert s.count(old)==1,'Unexpected source near '+old[:100]
 return s.replace(old,new,1)
def put(path,text):
 p=root/path
 if check:assert p.exists() and p.read_text()==text,'Generated source differs: '+path
 else:p.write_text(text)

sql=(root/'supabase/athlete-health.sql').read_text()
sql=sql[sql.index('create function private.athlete_health_request('):sql.index('create function public.athlete_health_request(')]
sql=replace(sql,'create function private.athlete_health_request(', 'create or replace function private.athlete_health_request(')
sql=replace(sql,'role_label text;','role_label text;notice_update uuid;visibility_value text;existing_update private.health_updates%rowtype;')
sql=replace(sql,"return jsonb_build_object('assigned_trainer',assigned", "return jsonb_build_object('care_notifications','in_app_v1','assigned_trainer',assigned")
start=sql.index(" elsif p_action='new_case' then")
end=sql.index(" elsif p_action='case' then",start)
sql=sql[:start]+""" elsif p_action='new_case' then
  if not private.health_submit(t,a,u) then raise exception 'A connected parent must approve athlete health updates, or submit the concern themselves';end if;
  kind:=p_data->>'category';body:=trim(coalesce(p_data->>'body',''));test_date:=(p_data->>'noticed_on')::date;request_id:=(p_data->>'request_id')::uuid;
  visibility_value:=coalesce(p_data->>'visibility','care_team');
  if visibility_value not in ('care_team','participation') or (visibility_value='participation' and not trainer) then raise exception 'Only the trainer can share an update with coaches';end if;
  if request_id is null or kind is null or kind not in ('injury','skin','concussion','other') or length(body) not between 1 and 4000 or test_date is null or test_date>current_date then raise exception 'Enter the concern, date and brief details';end if;
  -- Serialize identical new-case requests; response loss must not create a second case.
  perform pg_advisory_xact_lock(hashtext('health-case:'||u::text||':'||request_id::text));
  select * into c from private.health_cases where opened_by=u and client_request_id=request_id;
  if c.id is not null then
   select * into existing_update from private.health_updates h where h.case_id=c.id and h.author_id=u and h.client_request_id=request_id;
   if c.team_id<>t or c.athlete_id<>a or c.category<>kind or c.noticed_on<>test_date
    or existing_update.id is null or existing_update.body<>body or existing_update.visibility<>visibility_value then
    raise exception 'This request was already used with different content. Reopen the record before sending another update';end if;
   notice_update:=existing_update.id;
  else
   insert into private.health_cases(team_id,athlete_id,category,noticed_on,opened_by,updated_by,client_request_id) values(t,a,kind,test_date,u,u,request_id) returning * into c;
   insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id)
    values(c.id,u,private.communication_person_name(t,u),visibility_value,body,request_id) returning id into notice_update;
   perform private.health_event(t,a,c.id,'concern_reported',jsonb_build_object('visibility',visibility_value));
  end if;
  return jsonb_build_object('case_id',c.id,'notifications_created',(select count(*) from public.communication_notifications where health_update_id=notice_update));
"""+sql[end:]
start=sql.index(" elsif p_action='update' then")
end=sql.index(" elsif p_action='participation' then",start)
sql=sql[:start]+""" elsif p_action='update' then
  if c.id is null or not private.health_submit(t,a,u) then raise exception 'Health-update permission required';end if;
  body:=trim(coalesce(p_data->>'body',''));request_id:=(p_data->>'request_id')::uuid;
  if request_id is null or length(body) not between 1 and 4000 then raise exception 'Enter a brief update';end if;
  kind:=coalesce(p_data->>'visibility','care_team');
  if kind not in ('care_team','participation') or (kind='participation' and not trainer) then raise exception 'Only the trainer can share an update with coaches';end if;
  select * into existing_update from private.health_updates h where h.author_id=u and h.client_request_id=request_id;
  if existing_update.id is not null then
   if existing_update.case_id<>c.id or existing_update.body<>body or existing_update.visibility<>kind then
    raise exception 'This request was already used with different content. Reopen the record before sending another update';end if;
   notice_update:=existing_update.id;
  else
   insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id)
    values(c.id,u,private.communication_person_name(t,u),kind,body,request_id) returning id into notice_update;
   update private.health_cases set updated_at=now() where id=c.id;
   perform private.health_event(t,a,c.id,'care_update',jsonb_build_object('visibility',kind));
  end if;
  return jsonb_build_object('saved',true,'notifications_created',(select count(*) from public.communication_notifications where health_update_id=notice_update));
"""+sql[end:]
# Completed file uploads get one generic private update. Never expose file paths,
# names, provider details or media in a notification, and never resend on retry.
sql=replace(sql,"  update private.health_files set completed_at=coalesce(completed_at,now()) where id=f.id;", """  if f.completed_at is null then
   insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id)
    values(c.id,u,private.communication_person_name(t,u),'care_team','A private care attachment was added.',gen_random_uuid());
  end if;
  update private.health_files set completed_at=coalesce(completed_at,now()) where id=f.id;""")
core=(root/'supabase/health-notifications-core.sql').read_text()
compat=(root/'supabase/creator-offers-compatibility.sql').read_text().replace('27d274de0c35fb69ae2ed5ff35a959b9b001de1ef865fad1a804b5ba8b39f57e',EXPECTED)
guard="""-- HELD: in-app health notices and role-aware composer. Not push/email/SMS.
-- A coordinated web release and fresh source/advisor review are required.
begin;
do $$begin
 if private.scoped_deletion_schema_hash()<>'EXPECTED_HASH'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Care notifications require a fresh schema compatibility review';end if;
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('completed','cancelled'))
 then raise exception 'Review existing deletion jobs before this migration';end if;
end $$;
""".replace('EXPECTED_HASH',EXPECTED)
put('supabase/health-notifications.sql',guard+core+'\n'+sql+'\n'+compat+'\ncommit;\n')

s=(root/'src/athlete-health.js').read_text()
marker='/* Care notification composer and recipient-scoped navigation v1. */\n'
if marker not in s:
 # Retain the original first marker for the existing trainer generator.
 s=replace(s,'/* Trainer Dashboard filters v1. */\n','/* Trainer Dashboard filters v1. */\n'+marker)
 s=replace(s,'<div id="healthStatus"', '<button type="button" id="healthNotificationsBtn" class="secondary" data-wm-notification-entry>Notifications</button><div id="healthStatus"')
 s=replace(s," $h('healthClose').onclick=()=>closeSheets();", " $h('healthClose').onclick=()=>closeSheets();\n $h('healthNotificationsBtn').onclick=()=>window.WMNotificationSync?.open();")
 s=replace(s,"try{await work(g);if(active(g))note('Saved.');}","try{const result=await work(g);if(active(g))note(typeof result==='string'?result:'Saved.');}")
 s=replace(s," const person=id=>", """ function deliveryResult(out){
  if(!Number.isInteger(out?.notifications_created))return 'Saved. In-app care notifications are not available on this server yet.';
  return out.notifications_created ? `Saved. In-app notifications created for ${out.notifications_created} other authorized account${out.notifications_created===1?'':'s'}.` : 'Saved. No other currently authorized recipients were found.';
 }
 function audienceField(id){return `<label for="${id}">Send to / visibility</label><select id="${id}"><option value="care_team">Parents / guardians · private care update</option><option value="participation">Parents / guardians and coaches · participation update</option></select><p class="fine">Accepted trainers and authorized athlete/family accounts retain access. Only share participation information with coaches; previous private notes and attachments stay private.</p>`}
 function audienceButton(selectId,buttonId){const select=$h(selectId),button=$h(buttonId);if(!button)return;
  const update=()=>{button.textContent=select?.value==='participation'?'Send to Parents & Coaches':'Send to Parents / Guardians'};
  if(select)select.onchange=update;update();
 }
 const person=id=>""")
 s=replace(s,"try{await load(g)}catch(e){if(active(g))note(e.message,true)}", """try{
   await load(g);if(!active(g))return false;
   if(options?.notificationId){
    const {data:target,error}=await client.rpc('health_notification_open',{p_notification_id:options.notificationId});
    if(!active(g))return false;if(error)throw Error(error.message);
    if(!target||target.team_id!==activeTeam.id)throw Error('This care update belongs to a different team. Reopen it from Notifications.');
    const detail=await caseView(target.case_id,g);if(!active(g))return false;
    if(!detail?.updates?.some(n=>n.id===target.update_id))throw Error('This update is no longer visible. Refresh your notifications.');
    const item=[...sheet.querySelectorAll('[data-health-update]')].find(el=>el.dataset.healthUpdate===target.update_id);
    if(item){item.classList.add('health-update-current');item.setAttribute('tabindex','-1');item.focus();item.scrollIntoView({block:'nearest'});}
   }
   return active(g);
  }catch(e){if(active(g)){release();$h('healthBody').replaceChildren();note(e.message,true);}return false;}""")
 s=replace(s,'<button type="button" id="healthNewCase">Report a Concern</button>', '<button type="button" id="healthNewCase">${state.trainer?\'New Care Update\':\'Report a Concern\'}</button>')
 # The existing outer expression is a quoted string, so replace it with a template.
 s=replace(s,"a.can_submit?'<button type=\"button\" id=\"healthNewCase\">${state.trainer?'New Care Update':'Report a Concern'}</button>':'<p>","a.can_submit?`<button type=\"button\" id=\"healthNewCase\">${state.trainer?'New Care Update':'Report a Concern'}</button>`:'<p>")
 s=replace(s,'<h3>Report a concern · ${escape(a.name)}</h3>', '<h3>${state.trainer?\'New care update\':\'Report a concern\'} · ${escape(a.name)}</h3>')
 s=replace(s,'<label for="healthConcern">What should the trainer know?</label>', '${state.trainer&&state.care_notifications===\'in_app_v1\'?audienceField(\'healthNewVisibility\'):\'\'}<label for="healthConcern">${state.trainer?\'Update for the selected recipients\':\'What should the trainer know?\'}</label>')
 s=replace(s,'<button type="button" id="healthCreate" class="wide">Send to Team Trainer</button>', '<button type="button" id="healthCreate" class="wide">${state.trainer?\'Send to Parents / Guardians\':\'Send to Team Trainer\'}</button>')
 s=replace(s,"  bindBack();$h('healthCreate').onclick=", "  bindBack();if(state.trainer)audienceButton('healthNewVisibility','healthCreate');$h('healthCreate').onclick=")
 s=replace(s,"body:$h('healthConcern').value,request_id:requestId", "body:$h('healthConcern').value,visibility:$h('healthNewVisibility')?.value||'care_team',request_id:requestId")
 s=replace(s,'await caseView(out.case_id,g)});','await caseView(out.case_id,g);return deliveryResult(out)});')
 s=replace(s,'<article class="health-update"><b>', '<article class="health-update" data-health-update="${escape(n.id||\'\')}"><b>')
 s=replace(s,"out.trainer?'<label for=\"healthUpdateVisibility\">Who can see this update?</label><select id=\"healthUpdateVisibility\"><option value=\"care_team\">Private · trainer and connected family</option><option value=\"participation\">Shared · coaches and connected family</option></select>':''", "out.trainer?audienceField('healthUpdateVisibility'):''")
 s=replace(s,'placeholder="Question or update for the trainer and family"','placeholder="${out.trainer?\'Update for the selected recipients\':\'Question or update for the trainer and family\'}"')
 s=replace(s,'<button id="healthSendUpdate" type="button">Send Update</button>', '<button id="healthSendUpdate" type="button">${out.trainer?\'Send to Parents / Guardians\':\'Send to Team Trainer\'}</button>')
 s=replace(s,"if(out.can_submit){let requestId=crypto.randomUUID();$h('healthSendUpdate')", "if(out.can_submit){if(out.trainer)audienceButton('healthUpdateVisibility','healthSendUpdate');let requestId=crypto.randomUUID();$h('healthSendUpdate')")
 s=replace(s,"async k=>{await call('update',", "async k=>{const result=await call('update',")
 s=replace(s,"request_id:requestId},k);await caseView(id,k)})}", "request_id:requestId},k);await caseView(id,k);return deliveryResult(result)})}")
 s=replace(s,"sheet.querySelectorAll('[data-health-file]').forEach(b=>b.onclick=()=>viewFile(id,b.dataset.healthFile).catch(e=>note(e.message,true)));", "sheet.querySelectorAll('[data-health-file]').forEach(b=>b.onclick=()=>viewFile(id,b.dataset.healthFile).catch(e=>note(e.message,true)));\n  return out;")
put('src/athlete-health.js',s)

s=(root/'src/notification-inbox.js').read_text()
marker='/* Care notification routes v1. */\n'
if not s.startswith(marker):
 s=marker+s
 s=replace(s,"    if(window.WMJoinSync?.isNotification(row))", """    if(row.health_update_id){
      const opened=await window.WMAthleteHealth?.open({notificationId:row.id});
      if(opened&&current()===userId)await mark([row]);return;
    }
    if(window.WMJoinSync?.isNotification(row))""")
 s=replace(s,"    $n('communicationUnreadCount').textContent=display(count);", """    $n('communicationUnreadCount').textContent=display(count);
    for(const button of document.querySelectorAll('[data-wm-notification-entry]')){
      button.textContent=`Notifications${count?' · '+display(count):''}`;
      button.classList.toggle('wm-notification-unread',!!count);
      button.setAttribute('aria-label',`Notifications, ${count} unread updates`);
    }""")
 s=replace(s,"title.textContent=row.title||'Team update';", "title.textContent=(row.read_at?'':'Unread · ')+(row.title||'Team update');")
 s=replace(s,"  $n('refreshAllNotificationsBtn').onclick=()=>refresh();", """  for(const [host,id] of [[$n('profileBtn'),'roleNotificationsBtn'],[$n('opsHubSheet')?.querySelector('.sheet-head > button'),'organizationNotificationsBtn']]){
    if(!host)continue;const button=document.createElement('button');button.id=id;button.type='button';button.className='secondary';button.dataset.wmNotificationEntry='';button.textContent='Notifications';button.onclick=()=>openInbox();host.before(button);
  }
  $n('teamUnreadBadge').addEventListener('click',event=>{event.preventDefault();event.stopPropagation();void openInbox()});
  $n('refreshAllNotificationsBtn').onclick=()=>refresh();""")
put('src/notification-inbox.js',s)
# Keep the existing integration script's changes, not a replacement inbox.
if not check:subprocess.run([sys.executable,'scripts/build-communications-041.py'],cwd=root,check=True)
# Only own this small CSS addition; ordinary success messages are not red errors.
p='src/athlete-health.css';s=(root/p).read_text();extra='\n/* Care notification emphasis */\n.notification-card.unread b,.wm-notification-unread{color:#b42318!important;font-weight:800!important}.health-update-current{border-left:4px solid #b42318;background:#fff5f4;outline:2px solid #b42318;outline-offset:2px}#roleNotificationsBtn{min-height:44px;font-size:13px;padding:10px}#healthNotificationsBtn{min-height:44px;margin:4px 0 12px}#organizationNotificationsBtn{min-height:44px;font-size:13px}\n'
if extra not in s:s+=extra
put(p,s)
subprocess.run([sys.executable,'scripts/patch-athlete-health.py']+(['--check'] if check else []),cwd=root,check=True)
if check:
 html=(root/'index.html').read_text()
 assert (root/'src/notification-inbox.js').read_text() in html,'Notification embedding differs'
print('PASS Care composer, notification source and guarded migration are consistent')
