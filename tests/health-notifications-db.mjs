// Local PGlite fixtures only. Never connects to hosted Supabase.
import {db,ids,sessions,as,admin,rpc,denied,today,config} from './health-notification-fixture.mjs';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import assert from 'node:assert/strict';
const checks=[],pass=s=>{checks.push(s);console.log('PASS',s)};
await admin();
await db.exec(`create table private.scoped_deletion_jobs(personal boolean,sealed_at timestamptz,subject_hash text,state text);
 create or replace function private.scoped_deletion_access_ok() returns boolean language sql as $$select not exists(select 1 from private.scoped_deletion_jobs where personal and sealed_at is not null and subject_hash=encode(sha256(convert_to(auth.uid()::text,'UTF8')),'hex'))$$;
 -- No weigh-in alerts in this fixture; the existing weight-specific suites remain separate.
 create function private.weigh_in_recipients(uuid) returns table(user_id uuid) language sql as $$select null::uuid where false$$;
 alter table public.communication_notifications enable row level security;
 grant select,insert,update,delete on public.communication_notifications to authenticated;
 create policy communication_notifications_self on public.communication_notifications for select to authenticated using(user_id=auth.uid());
 create function public.get_notification_badge_count() returns integer language sql stable as $$select count(*)::integer from public.communication_notifications where user_id=auth.uid() and read_at is null$$;
 create function public.mark_communication_notifications_read(p_notification_ids uuid[]) returns integer language plpgsql security definer set search_path='' as $$declare n int;begin update public.communication_notifications set read_at=coalesce(read_at,now()) where user_id=auth.uid() and id=any(p_notification_ids) and read_at is null;get diagnostics n=row_count;return n;end$$;
 grant execute on function public.get_notification_badge_count(),public.mark_communication_notifications_read(uuid[]) to authenticated;`);
// LEGACY-INBOX-FIXTURE: actual router body, synthetic team/weight helpers.
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
const before=(await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h;
const migration=(await readFile('supabase/health-notifications.sql','utf8')).replaceAll('73d4ab1a9cf488dc3a0112e1895813cab8698e46335e7f64a9a94d28f1597246',before);
await db.exec(migration);
const after=(await db.query('select catalog,catalog_hash,private.scoped_deletion_schema_hash() current from private.scoped_deletion_config')).rows[0];
assert.equal(after.current,after.catalog_hash);assert.notEqual(after.current,before);
assert((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(after.current));
pass('Full structural catalog and exact athlete-merge fingerprint updated together');
for(const k of ['reviewer','orgAdmin','secondTrainer']){
 ids[k]=uuid();sessions[ids[k]]=uuid();
 await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[ids[k],k+'@example.test']);
 await db.query('insert into public.profiles(id,display_name) values($1,$2)',[ids[k],'Synthetic '+k]);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sessions[ids[k]],ids[k]]);
}
await db.query("insert into public.team_memberships(team_id,user_id,role,permissions) values($1,$2,'manager','{\"staff_role\":\"team_mom\"}'),($1,$3,'manager','{\"staff_role\":\"team_trainer\"}')",[ids.team,ids.reviewer,ids.secondTrainer]);
await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$2,'organization_admin')",[ids.org,ids.orgAdmin]);
const notices=async u=>(await db.query('select id,title,body,health_update_id,read_at,athlete_id from public.communication_notifications where user_id=$1 order by created_at,id',[u])).rows;
const count=async()=>(await db.query('select public.get_notification_badge_count() n')).rows[0].n;
const open=async id=>(await db.query('select public.health_notification_open($1) r',[id])).rows[0].r;
await as(ids.trainer);await rpc('accept_trainer',{acknowledgement:'trainer-v1'});
assert.equal((await rpc('dashboard')).care_notifications,'in_app_v1');
const request={athlete_id:ids.athlete,category:'other',noticed_on:today,body:'PRIVATE-FIXTURE-ONLY',request_id:uuid()};
const saved=await rpc('new_case',request);assert.equal(saved.notifications_created,1);
assert.deepEqual(await rpc('new_case',request),saved);
await assert.rejects(()=>rpc('new_case',{...request,body:'Changed payload'}),/different content/);
await assert.rejects(()=>rpc('new_case',{...request,visibility:'participation'}),/different content/);
for(const u of [ids.coach,ids.orgAdmin,ids.reviewer,ids.teen,ids.secondTrainer,ids.other,ids.trainer]){
 await as(u);assert.equal((await notices(u)).length,0);
}
await as(ids.parent);const [first]=await notices(ids.parent);assert(first);assert.equal(first.athlete_id,null);
assert(!JSON.stringify(first).includes(request.body));assert.equal(await count(),1);
assert.equal((await open(first.id)).case_id,saved.case_id);
assert.equal((await db.query('select * from public.get_communication_notifications($1,$2)',[ids.team,30])).rows[0].id,first.id);
assert.equal((await rpc('case',{case_id:saved.case_id})).updates[0].body,request.body);
await db.query('select public.mark_communication_notifications_read($1)',[[first.id]]);assert.equal(await count(),0);
assert.equal((await rpc('case',{case_id:saved.case_id})).case.status,'awaiting_trainer');
pass('Private trainer note notifies only current authorized family, not coaches, reviewer, unaccepted trainer or sender; marking read is not a care decision');
await as(ids.coach);await denied(()=>open(first.id));await assert.rejects(()=>db.query('select private.health_notification_visible($1,$2)',[first.health_update_id,ids.parent]),/permission denied/);
await as(ids.parent);await assert.rejects(()=>rpc('new_case',{...request,request_id:uuid(),visibility:'participation'}),/Only the trainer/);
await assert.rejects(()=>rpc('update',{case_id:saved.case_id,body:'forged shared',request_id:uuid(),visibility:'participation'}),/Only the trainer/);
pass('Forged recipient IDs and nontrainer shared-sending requests are rejected');
await as(ids.secondTrainer);await rpc('accept_trainer',{acknowledgement:'trainer-v1'});
await as(ids.parent);await rpc('family_permission',{athlete_id:ids.athlete,allow_updates:true,allow_photos:false});
await as(ids.trainer);const privateUpdate={case_id:saved.case_id,body:'PRIVATE-SECOND',request_id:uuid(),visibility:'care_team'};
assert.equal((await rpc('update',privateUpdate)).notifications_created,3);assert.equal((await rpc('update',privateUpdate)).notifications_created,3);
await assert.rejects(()=>rpc('update',{...privateUpdate,visibility:'participation'}),/different content/);
await as(ids.teen);assert.equal((await notices(ids.teen)).length,1);const teenPrivate=(await notices(ids.teen))[0];
await as(ids.parent);await rpc('family_permission',{athlete_id:ids.athlete,allow_updates:false,allow_photos:false});
await as(ids.teen);assert.equal((await notices(ids.teen)).length,0);assert.equal(await count(),0);await denied(()=>open(teenPrivate.id));
assert.equal((await db.query('select * from public.get_communication_notifications($1,$2)',[ids.team,30])).rows.length,0);
pass('Legacy SECURITY DEFINER inbox cannot reveal notices after clinical permission is withdrawn');
pass('Private notices follow actual athlete permission; withdrawal hides existing notices and denies their links');
await as(ids.trainer);
const shared={athlete_id:ids.athlete,category:'other',noticed_on:today,body:'PARTICIPATION-FIXTURE-ONLY',request_id:uuid(),visibility:'participation'};
const sharedCase=await rpc('new_case',shared);assert.equal(sharedCase.notifications_created,5);
for(const u of [ids.coach,ids.parent,ids.teen,ids.orgAdmin,ids.secondTrainer]){
 await as(u);const rows=await notices(u);assert(rows.some(n=>n.title==='New participation update'));
 const n=rows.find(n=>n.title==='New participation update');assert.equal((await open(n.id)).case_id,sharedCase.case_id);
 assert.equal((await rpc('case',{case_id:sharedCase.case_id})).updates[0].body,shared.body);
}
await as(ids.reviewer);assert.equal((await notices(ids.reviewer)).length,0);
await as(ids.coach);assert.equal((await rpc('case',{case_id:saved.case_id})).updates.length,0);
pass('Explicit shared update notifies current eligible viewers once, including organization staff; older private notes remain hidden and Team Mom gains no health access');
await as(ids.trainer);await rpc('participation',{case_id:sharedCase.case_id,revision:1,status:'modified',participation_note:'Synthetic instructions only'});
await as(ids.coach);assert.equal((await notices(ids.coach)).length,2);
await as(ids.trainer);const slot=await rpc('reserve_file',{case_id:saved.case_id,file_kind:'concern_photo',mime_type:'image/jpeg',size_bytes:4});
await db.query('insert into storage.objects(bucket_id,name,owner_id,metadata) values($1,$2,$3,$4)',['athlete-health',slot.path,ids.trainer,{size:4,mimetype:'image/jpeg'}]);
await rpc('complete_file',{case_id:saved.case_id,file_id:slot.id});await rpc('complete_file',{case_id:saved.case_id,file_id:slot.id});
await as(ids.parent);assert.equal((await rpc('case',{case_id:saved.case_id})).updates.filter(n=>n.body==='A private care attachment was added.').length,1);
await as(ids.coach);assert.equal((await notices(ids.coach)).length,2);
pass('Participation decisions create shared notices; completing a private upload creates one private notice, not a duplicate on retry');
await admin();await db.query('update public.team_memberships set active=false where team_id=$1 and user_id=$2',[ids.team,ids.parent]);
await as(ids.parent);assert.equal((await notices(ids.parent)).length,0);await denied(()=>open(first.id));
await admin();assert.equal((await db.query('select public.notification_badge_count_for_delivery($1) n',[ids.parent])).rows[0].n,0);
await db.query('update public.team_memberships set active=true where team_id=$1 and user_id=$2',[ids.team,ids.parent]);
await as(ids.parent);const parentNotice=(await notices(ids.parent))[0];
await admin();await db.query('update auth.users set banned_until=now()+interval \'1 day\' where id=$1',[ids.parent]);
await as(ids.parent);await denied(()=>open(parentNotice.id));assert.equal(await count(),0);
await admin();await db.query('update auth.users set banned_until=null where id=$1',[ids.parent]);
await db.query('delete from auth.sessions where id=$1',[sessions[ids.parent]]);await as(ids.parent);await denied(()=>open(parentNotice.id));
await as(ids.trainer);await admin();await db.query("insert into private.scoped_deletion_jobs values(true,now(),encode(sha256(convert_to($1::text,'UTF8')),'hex'),'accepted')",[ids.secondTrainer]);
const beforeSecond=(await notices(ids.secondTrainer)).length;await as(ids.trainer);
await rpc('update',{case_id:saved.case_id,body:'After account freeze',request_id:uuid()});
await admin();assert.equal((await notices(ids.secondTrainer)).length,beforeSecond);
pass('Membership removal, bans, expired sessions and deletion freezes are enforced; native badge count excludes revoked care access');
await db.exec("create policy fixture_insert_permissive on public.communication_notifications for insert to authenticated with check(true);create policy fixture_update_permissive on public.communication_notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());");
await as(ids.coach);const coachNotice=(await notices(ids.coach))[0];
await assert.rejects(()=>db.query("insert into public.communication_notifications(team_id,user_id,category,title,body,health_update_id) values($1,$2,'system','forged','forged',$3)",[ids.team,ids.coach,coachNotice.health_update_id]),/row-level security/);
assert.equal((await db.query('update public.communication_notifications set health_update_id=null where id=$1 returning id',[coachNotice.id])).rows.length,0);
await assert.rejects(()=>db.query('select * from private.health_updates'),/permission denied/);
await admin();await db.exec('set role anon');await assert.rejects(()=>open(first.id),/permission denied/);
pass('Restrictive notification guards survive unrelated broad write policies; private tables and anonymous resolution stay denied');
// RELEASE-PRESERVATION: isolated synthetic database, real deletion planner.
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
await admin();await db.exec('alter table private.health_cases add column future_unreviewed_field text');
assert.notEqual((await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h,after.catalog_hash);
await as(ids.coach);await assert.rejects(()=>db.query('select public.athlete_merge_request($1,$2)',['preview',{team_id:ids.team,duplicate_id:ids.athlete,keep_id:ids.athlete2}]),/compatibility/);
pass('New unreviewed schema drift still stops athlete merging');
await writeFile('validation/health-notifications-db.json',JSON.stringify({checks,syntheticOnly:true,hostedDeployment:false,externalDelivery:false},null,2));
await db.close();
