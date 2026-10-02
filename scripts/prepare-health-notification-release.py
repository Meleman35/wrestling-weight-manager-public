"""Prepare 0.20.116 reproducibly; no hosted calls, real identities or deployment."""
from pathlib import Path
import re,sys,subprocess
root=Path(__file__).resolve().parents[1];check='--check' in sys.argv

def put(path,text):
 p=root/path
 if check:assert p.read_text()==text,'Release source differs: '+path
 else:p.write_text(text)
def change(text,old,new):
 if new in text:return text
 assert text.count(old)==1,'Unexpected source: '+old[:90]
 return text.replace(old,new,1)

p='scripts/prepare-health-notifications.py';s=(root/p).read_text()
s=change(s,"do $$begin\n if private.scoped_deletion_schema_hash()", """lock table public.communication_notifications,private.health_updates in share row exclusive mode;
do $$begin
 if not exists(select 1 from pg_proc where oid='private.athlete_health_request(text,jsonb)'::regprocedure
  and encode(sha256(convert_to(prosrc,'UTF8')),'hex')='1ebc7e3c0121f8ed763fa017b8ef8bd50dee5ea1c264e19c32b8b3bdfe180a8c')
 then raise exception 'Care router changed; review the function before deployment';end if;
 if not exists(select 1 from pg_class where oid='public.communication_notifications'::regclass and relrowsecurity)
 then raise exception 'Notification RLS is required';end if;
 if private.scoped_deletion_schema_hash()""")
put(p,s)
# An older SECURITY DEFINER inbox bypasses table RLS. Preserve its existing
# team and weight checks, but require the identical care predicate there too.
legacy="""
-- LEGACY-CARE-NOTICE-GUARD: current access also applies to the old inbox RPC.
do $guard$declare source text;begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.get_communication_notifications(uuid,integer)')
  and encode(sha256(convert_to(prosrc,'UTF8')),'hex')='6317d5b9f00335bd944e4a9b5e1e57be6853c1ad18b6bede63f2b9de5d9e8d52')
 then raise exception 'Legacy notification router changed; review before deployment';end if;
 source:=pg_get_functiondef('public.get_communication_notifications(uuid,integer)'::regprocedure);
 if position(' order by n.created_at desc' in source)=0 then raise exception 'Unexpected legacy inbox ordering';end if;
 execute replace(source,' order by n.created_at desc',
  ' and (n.health_update_id is null or private.health_notification_readable(n.health_update_id)) order by n.created_at desc');
end $guard$;
"""
p='supabase/health-notifications-core.sql';s=(root/p).read_text()
if '-- LEGACY-CARE-NOTICE-GUARD:' not in s:s+=legacy
put(p,s)

p='tests/health-notifications-db.mjs';s=(root/p).read_text()
fixture="""// LEGACY-INBOX-FIXTURE: actual router body, synthetic team/weight helpers.
await db.exec(`
 create function private.communication_user_belongs_to_team(t uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.team_memberships where team_id=t and user_id=u and active) or exists(select 1 from public.organization_memberships m join public.teams t1 on t1.organization_id=m.organization_id where t1.id=t and m.user_id=u and m.role='organization_admin')$$;
 create function public.can_read_weigh_in_alert(uuid) returns boolean language sql stable as $$select false$$;
 CREATE OR REPLACE FUNCTION public.get_communication_notifications(p_team_id uuid, p_limit integer DEFAULT 30)
 RETURNS SETOF public.communication_notifications LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
declare v_user uuid:=(select auth.uid());
begin
  if v_user is null or not private.communication_user_belongs_to_team(p_team_id,v_user) then raise exception 'Team access required'; end if;
  return query select * from public.communication_notifications n where n.team_id=p_team_id and n.user_id=v_user and (n.weigh_in_id is null or public.can_read_weigh_in_alert(n.weigh_in_id)) order by n.created_at desc limit least(greatest(coalesce(p_limit,30),1),100);
end;
$function$;
 revoke all on function public.get_communication_notifications(uuid,integer) from public,anon;
 grant execute on function public.get_communication_notifications(uuid,integer) to authenticated;
`);
"""
if '// LEGACY-INBOX-FIXTURE:' not in s:s=change(s,"const before=(await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h;",fixture+"const before=(await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h;")
s=change(s,"await as(ids.teen);assert.equal((await notices(ids.teen)).length,0);assert.equal(await count(),0);await denied(()=>open(teenPrivate.id));", """await as(ids.teen);assert.equal((await notices(ids.teen)).length,0);assert.equal(await count(),0);await denied(()=>open(teenPrivate.id));
assert.equal((await db.query('select * from public.get_communication_notifications($1,$2)',[ids.team,30])).rows.length,0);
pass('Legacy SECURITY DEFINER inbox cannot reveal notices after clinical permission is withdrawn');""")
s=change(s,"assert.equal((await open(first.id)).case_id,saved.case_id);", """assert.equal((await open(first.id)).case_id,saved.case_id);
assert.equal((await db.query('select * from public.get_communication_notifications($1,$2)',[ids.team,30])).rows[0].id,first.id);""")
extra="""// RELEASE-PRESERVATION: isolated synthetic database, real deletion planner.
await admin();
// The earlier orgAdmin opened a case and therefore owns a protected care-read
// audit entry. Create a separate recipient who has NEVER read a clinical record.
const recipientOnly=uuid();
await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'recipient-only@example.test',now())",[recipientOnly]);
await db.query("insert into public.profiles(id,display_name) values($1,'Synthetic notification recipient')",[recipientOnly]);
await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$2,'organization_admin')",[ids.org,recipientOnly]);
await as(ids.trainer);await rpc('update',{case_id:sharedCase.case_id,body:'RECIPIENT-ONLY-TEST',request_id:uuid(),visibility:'participation'});
await admin();
const {planDeletion}=await import('../scripts/scoped-deletion-plan.mjs');
const {relation}=await import('./helpers/scoped-deletion-db.mjs');
const quote=x=>{if(!/^[a-z_][a-z0-9_]*$/.test(x))throw Error('Invalid fixture identifier');return '"'+x+'"'};
const reader={
 async select(table,predicates,limit){const values=[];const where=predicates.map(p=>'('+Object.entries(p).map(([k,v])=>{values.push(v);return quote(k)+' is not distinct from $'+values.length}).join(' and ')+')').join(' or ');values.push(limit);return(await db.query('select * from '+relation(table)+' where '+where+' limit $'+values.length,values)).rows},
 async identityMentions(table,columns,id,limit){return(await db.query('select * from '+relation(table)+' where '+columns.map(c=>quote(c)+'::text like $1').join(' or ')+' limit $2',['%'+id+'%',limit])).rows}
};
const preserved=JSON.stringify((await db.query('select id,case_id,author_id,visibility,body from private.health_updates order by id')).rows);
const otherNotices=JSON.stringify((await db.query('select id,user_id,health_update_id from public.communication_notifications where user_id<>$1 order by id',[recipientOnly])).rows);
const recipientPlan=await planDeletion({scope:{actorId:recipientOnly,kind:'personal',teamIds:[],organizationIds:[]},catalog:after.catalog,reader});
assert(recipientPlan.records.some(r=>r.table==='public.communication_notifications'&&r.action==='delete'));
assert(!recipientPlan.records.some(r=>r.table.startsWith('private.health_')));
assert(!recipientPlan.records.some(r=>r.table==='auth.users'&&r.key.id!==recipientOnly));
assert(recipientPlan.records.filter(r=>r.table==='public.communication_notifications').every(r=>r.row.user_id===recipientOnly));
for(const actorId of [ids.trainer,ids.orgAdmin]){
 await assert.rejects(()=>planDeletion({scope:{actorId,kind:'personal',teamIds:[],organizationIds:[]},catalog:after.catalog,reader}),e=>e.code==='unreviewed_dependency'&&e.details.table.startsWith('private.health_'));
}
assert.equal(JSON.stringify((await db.query('select id,case_id,author_id,visibility,body from private.health_updates order by id')).rows),preserved);
assert.equal(JSON.stringify((await db.query('select id,user_id,health_update_id from public.communication_notifications where user_id<>$1 order by id',[recipientOnly])).rows),otherNotices);
pass('Actual deletion planner removes notification-only recipient data without shared care or other recipients; clinical authors AND readers still require review');
"""
if '// RELEASE-PRESERVATION:' not in s:s=change(s,"await admin();await db.exec('alter table private.health_cases add column future_unreviewed_field text');",extra+"await admin();await db.exec('alter table private.health_cases add column future_unreviewed_field text');")
put(p,s)

p='privacy.html';s=(root/p).read_text()
text='<p>New care updates, participation decisions and completed private attachments create generic in-app notices for other currently authorized recipients. Notices contain no clinical note, diagnosis, photo or athlete name; opening one checks your current access and goes to the specific concern/update. The trainer chooses a private family/care update or an explicitly coach-shared participation update. Earlier private notes and attachments are not made public by a later shared update. Reading a notice is not a care decision. This release does not send health-specific lock-screen alert pushes, email or SMS. Existing device badge synchronization may include eligible unread care notices; a badge is not proof an alert was delivered. Urgent concerns require direct contact.</p>'
if text not in s:s=change(s,'<h2>Services that handle information</h2>',text+'\n<h2>Services that handle information</h2>')
put(p,s)
p='support.html';s=(root/p).read_text()
text='<h2>Care updates and notifications</h2>\n<p>Open <strong>Toolbox → Athlete Health</strong>, or the assigned trainer’s <strong>Trainer Dashboard</strong>. Trainers choose <strong>Send to Parents / Guardians</strong> for a private update or <strong>Send to Parents &amp; Coaches</strong> for a shared participation update. Other permitted senders use <strong>Send to Team Trainer</strong>. Family and trainer authorization still controls visibility; general conversation reviewers do not gain clinical access.</p>\n<p>Use <strong>Notifications</strong> in the header, Board Room or Athlete Health. Unread titles are marked in bold red and also labeled Unread. Open a care notice to go directly to its concern and highlighted update. Notices are created for new activity only; previously saved notes are not resent. A saved update with no other authorized recipients is not a delivery failure. Do not repeatedly create a concern while waiting for an alert. Health notices are in-app only in this release, not email, text or lock-screen alert delivery. Urgent concerns require direct contact.</p>'
if text in s:s=s.replace(text+'\n','',1)
s=change(s,'<footer class="wm-doc-footer">',text+'\n<footer class="wm-doc-footer">')
put(p,s)
p='docs/athlete-health.md';s=(root/p).read_text().replace('**Forms & Health → Athlete Health**','**Toolbox → Athlete Health**')
s=change(s,'This release has no health-specific push or email alerts; urgent issues require direct contact.', 'New authorized care activity creates generic in-app notifications that open the exact concern/update. Trainers choose Send to Parents / Guardians or Send to Parents & Coaches; earlier private notes stay private. The sender is excluded and current access is rechecked before showing a notice or its destination. This release has no health-specific lock-screen alert push, email or SMS delivery; urgent issues require direct contact. Native badge synchronization is not alert delivery.')
put(p,s)
for p in ['scripts/prepare-linked-creator-release.py','scripts/prepare-launch-information.py']:
 s=(root/p).read_text().replace("('0.20.113','0.20.114','0.20.115')","('0.20.113','0.20.114','0.20.115','0.20.116')")
 put(p,s)
for script in ['prepare-health-notifications.py','finish-health-notification-copy.py','prepare-health-notification-tests.py','prepare-health-notification-browser.py']:
 subprocess.run([sys.executable,str(root/'scripts'/script)]+(['--check'] if check else []),cwd=root,check=True)
s=(root/'index.html').read_text()
for kind in ['Support','Privacy']:
 page=(root/(kind.lower()+'.html')).read_text();body=re.search(r'</nav>([\s\S]*?)<footer class="wm-doc-footer">',page)
 assert body,'Missing disclosure body: '+kind
 pattern=r'(<template id="wm'+kind+r'Template">)[\s\S]*?(</template>)'
 assert len(re.findall(pattern,s))==1
 s=re.sub(pattern,lambda m:m[1]+body[1]+m[2],s)
s=s.replace('0.20.115','0.20.116').replace('Updated beta privacy and support guidance; native and billing access unchanged.','Trainer-directed care updates and in-app notification destinations.')
put('index.html',s);put('sw.js',(root/'sw.js').read_text().replace('0.20.115','0.20.116'))
print('PASS 0.20.116 source/disclosure and preservation preparation; deployment not inferred')
