"""Reproducible 0.20.116 release preparation. No hosted calls or real identities.
This script prepares source; successful execution does not establish deployment.
"""
from pathlib import Path
import re,sys,subprocess
root=Path(__file__).resolve().parents[1]
check='--check' in sys.argv

def put(path,text):
 p=root/path
 if check:assert p.read_text()==text,'Release source differs: '+path
 else:p.write_text(text)
def change(text,old,new):
 if new in text:return text
 assert text.count(old)==1,'Unexpected source: '+old[:90]
 return text.replace(old,new,1)

# The structural hash does not include stored function bodies. Require the exact
# already-reviewed health router too, rather than overwriting a concurrent fix.
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

# Exercise the production deletion planner with the NEW notification FK.
# A notification recipient does not own the underlying shared clinical record.
p='tests/health-notifications-db.mjs';s=(root/p).read_text()
extra="""// RELEASE-PRESERVATION: run only in the isolated synthetic database.
await admin();
const {planDeletion}=await import('../scripts/scoped-deletion-plan.mjs');
const {relation}=await import('./helpers/scoped-deletion-db.mjs');
const quote=x=>{if(!/^[a-z_][a-z0-9_]*$/.test(x))throw Error('Invalid fixture identifier');return '"'+x+'"'};
const reader={
 async select(table,predicates,limit){const values=[];const where=predicates.map(p=>'('+Object.entries(p).map(([k,v])=>{values.push(v);return quote(k)+' is not distinct from $'+values.length}).join(' and ')+')').join(' or ');values.push(limit);return(await db.query('select * from '+relation(table)+' where '+where+' limit $'+values.length,values)).rows},
 async identityMentions(table,columns,id,limit){return(await db.query('select * from '+relation(table)+' where '+columns.map(c=>quote(c)+'::text like $1').join(' or ')+' limit $2',['%'+id+'%',limit])).rows}
};
const preserved=JSON.stringify((await db.query('select id,case_id,author_id,visibility,body from private.health_updates order by id')).rows);
const otherNotices=JSON.stringify((await db.query('select id,user_id,health_update_id from public.communication_notifications where user_id<>$1 order by id',[ids.orgAdmin])).rows);
const recipientPlan=await planDeletion({scope:{actorId:ids.orgAdmin,kind:'personal',teamIds:[],organizationIds:[]},catalog:after.catalog,reader});
assert(recipientPlan.records.some(r=>r.table==='public.communication_notifications'&&r.action==='delete'));
assert(!recipientPlan.records.some(r=>r.table.startsWith('private.health_')));
assert(!recipientPlan.records.some(r=>r.table==='auth.users'&&r.key.id!==ids.orgAdmin));
assert(recipientPlan.records.filter(r=>r.table==='public.communication_notifications').every(r=>r.row.user_id===ids.orgAdmin));
await assert.rejects(()=>planDeletion({scope:{actorId:ids.trainer,kind:'personal',teamIds:[],organizationIds:[]},catalog:after.catalog,reader}),e=>e.code==='unreviewed_dependency'&&e.details.table.startsWith('private.health_'));
assert.equal(JSON.stringify((await db.query('select id,case_id,author_id,visibility,body from private.health_updates order by id')).rows),preserved);
assert.equal(JSON.stringify((await db.query('select id,user_id,health_update_id from public.communication_notifications where user_id<>$1 order by id',[ids.orgAdmin])).rows),otherNotices);
pass('Actual deletion planner removes recipient-owned notices only; shared care records and other recipients survive; clinical author deletion still requires review');
"""
if '// RELEASE-PRESERVATION:' not in s:
 s=change(s,"await admin();await db.exec('alter table private.health_cases add column future_unreviewed_field text');",extra+"await admin();await db.exec('alter table private.health_cases add column future_unreviewed_field text');")
put(p,s)

# Update both public and embedded disclosures; preserve every other paragraph.
p='privacy.html';s=(root/p).read_text()
text='<p>New care updates, participation decisions and completed private attachments create generic in-app notices for other currently authorized recipients. Notices contain no clinical note, diagnosis, photo or athlete name; opening one checks your current access and goes to the specific concern/update. The trainer chooses a private family/care update or an explicitly coach-shared participation update. Earlier private notes and attachments are not made public by a later shared update. Reading a notice is not a care decision. This release does not send health-specific lock-screen alert pushes, email or SMS. Existing device badge synchronization may include eligible unread care notices; a badge is not proof an alert was delivered. Urgent concerns require direct contact.</p>'
if text not in s:s=change(s,'<h2>Services that handle information</h2>',text+'\n<h2>Services that handle information</h2>')
put(p,s)
p='support.html';s=(root/p).read_text()
text='<h2>Care updates and notifications</h2>\n<p>Open <strong>Toolbox → Athlete Health</strong>, or the assigned trainer’s <strong>Trainer Dashboard</strong>. Trainers choose <strong>Send to Parents / Guardians</strong> for a private update or <strong>Send to Parents &amp; Coaches</strong> for a shared participation update. Other permitted senders use <strong>Send to Team Trainer</strong>. Family and trainer authorization still controls visibility; general conversation reviewers do not gain clinical access.</p>\n<p>Use <strong>Notifications</strong> in the header, Board Room or Athlete Health. Unread titles are marked in bold red and also labeled Unread. Open a care notice to go directly to its concern and highlighted update. Notices are created for new activity only; previously saved notes are not resent. A saved update with no other authorized recipients is not a delivery failure. Do not repeatedly create a concern while waiting for an alert. Health notices are in-app only in this release, not email, text or lock-screen alert delivery. Urgent concerns require direct contact.</p>'
if text not in s:s=change(s,'<h2>Connection and saved work</h2>',text+'\n<h2>Connection and saved work</h2>')
put(p,s)
p='docs/athlete-health.md';s=(root/p).read_text().replace('**Forms & Health → Athlete Health**','**Toolbox → Athlete Health**')
s=change(s,'This release has no health-specific push or email alerts; urgent issues require direct contact.', 'New authorized care activity creates generic in-app notifications that open the exact concern/update. Trainers choose Send to Parents / Guardians or Send to Parents & Coaches; earlier private notes stay private. The sender is excluded and current access is rechecked before showing a notice or its destination. This release has no health-specific lock-screen alert push, email or SMS delivery; urgent issues require direct contact. Native badge synchronization is not alert delivery.')
put(p,s)
# Old release generators must tolerate the newer paired web version, not downgrade it.
for p in ['scripts/prepare-linked-creator-release.py','scripts/prepare-launch-information.py']:
 s=(root/p).read_text().replace("('0.20.113','0.20.114','0.20.115')","('0.20.113','0.20.114','0.20.115','0.20.116')")
 put(p,s)
# Regenerate only through the original owned source generators.
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
put('index.html',s)
put('sw.js',(root/'sw.js').read_text().replace('0.20.115','0.20.116'))
print('PASS 0.20.116 release sources, public/in-app disclosures and preservation test are consistent; deployment not inferred')
