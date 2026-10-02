-- HELD: in-app health notices and role-aware composer. Not push/email/SMS.
-- A coordinated web release and fresh source/advisor review are required.
begin;
do $$begin
 if private.scoped_deletion_schema_hash()<>'73d4ab1a9cf488dc3a0112e1895813cab8698e46335e7f64a9a94d28f1597246'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Care notifications require a fresh schema compatibility review';end if;
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('completed','cancelled'))
 then raise exception 'Review existing deletion jobs before this migration';end if;
end $$;
-- Source component only; deploy via the guarded generated health-notifications.sql.
-- This adds IN-APP notices, not email/SMS or alert-push delivery. No backfill.
alter table public.communication_notifications add column health_update_id uuid
 references private.health_updates(id) on delete cascade;
create unique index communication_notifications_health_recipient
 on public.communication_notifications(health_update_id,user_id) where health_update_id is not null;
alter table public.communication_notifications add constraint health_notification_shape check(
 health_update_id is null or (category='system' and thread_id is null and message_id is null
 and weigh_in_id is null and athlete_id is null and join_request_id is null and profile_request_id is null));

-- Explicit-user equivalent of the existing case/update read rules. Background
-- recipient selection must not depend on the sender's auth.uid() or session.
create function private.health_notification_visible(p_update uuid,p_user uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(select 1 from auth.users u where u.id=p_user
  and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and not exists(select 1 from private.team_logins where user_id=p_user)
 and not exists(select 1 from private.scoped_deletion_jobs j where j.personal and j.sealed_at is not null
  and j.subject_hash=encode(sha256(convert_to(p_user::text,'UTF8')),'hex'))
 and exists(
  select 1 from private.health_updates h join private.health_cases c on c.id=h.case_id
  join public.teams t on t.id=c.team_id
  cross join lateral(select
   private.health_trainer(c.team_id,p_user) or private.health_clinical_family(c.team_id,c.athlete_id,p_user) clinical,
   private.health_family(c.team_id,c.athlete_id,p_user) family,
   exists(select 1 from public.team_memberships m where m.team_id=c.team_id and m.user_id=p_user and m.active
    and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->'team_admin'='true'::jsonb)))
   or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id
    and m.user_id=p_user and m.role='organization_admin') staff) access
  where h.id=p_update and private.health_team_athlete(c.team_id,c.athlete_id)
   and (access.clinical or access.family or access.staff)
   and (h.visibility='participation' or access.clinical or h.author_id=p_user)
 );
$$;
revoke all on function private.health_notification_visible(uuid,uuid) from public,anon,authenticated;

create function private.health_notification_readable(p_update uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select private.health_actor() is not null and private.health_notification_visible(p_update,auth.uid());
$$;
revoke all on function private.health_notification_readable(uuid) from public,anon,authenticated;
grant execute on function private.health_notification_readable(uuid) to authenticated;
create policy health_notification_current_access on public.communication_notifications as restrictive
 for select to authenticated using(health_update_id is null or private.health_notification_readable(health_update_id));
-- Future unrelated permissive policies must not enable client-authored notices.
create policy health_notification_no_client_insert on public.communication_notifications as restrictive
 for insert to authenticated with check(health_update_id is null);
create policy health_notification_no_client_update on public.communication_notifications as restrictive
 for update to authenticated using(health_update_id is null) with check(health_update_id is null);

create function private.enqueue_health_update_notifications() returns trigger
 language plpgsql security definer set search_path='' as $$
declare c private.health_cases%rowtype; target uuid;
begin
 select * into c from private.health_cases where id=new.case_id;
 if c.id is null then raise exception 'Care notification source is unavailable';end if;
 for target in
  select m.user_id from public.team_memberships m where m.team_id=c.team_id and m.active
  union select m.user_id from public.organization_memberships m join public.teams t on t.organization_id=m.organization_id
   where t.id=c.team_id and m.role='organization_admin'
 loop
  if target<>new.author_id and private.health_notification_visible(new.id,target) then
   insert into public.communication_notifications(team_id,user_id,category,title,body,health_update_id)
    values(c.team_id,target,'system',case when new.visibility='participation' then 'New participation update' else 'New care update' end,
     'An update is available to your account. Open it to view the concern securely.',new.id)
    on conflict(health_update_id,user_id) where health_update_id is not null do nothing;
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.enqueue_health_update_notifications() from public,anon,authenticated;
create trigger health_update_notification after insert on private.health_updates
 for each row execute function private.enqueue_health_update_notifications();

-- Notification identity is an opaque per-recipient ID. Resolve after sign-in;
-- never accept a caller's recipient identity or trust a raw case ID from a push.
create function private.health_notification_open(p_notification_id uuid) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare u uuid=private.health_actor();n public.communication_notifications%rowtype;c private.health_cases%rowtype;
begin
 if u is null then raise sqlstate '42501' using message='Sign in and unlock to view this care update';end if;
 select * into n from public.communication_notifications where id=p_notification_id and user_id=u and health_update_id is not null;
 if n.id is null or not private.health_notification_visible(n.health_update_id,u) then
  raise sqlstate '42501' using message='This care update is no longer available to this account';end if;
 select c1.* into c from private.health_cases c1 join private.health_updates h on h.case_id=c1.id
  where h.id=n.health_update_id and c1.team_id=n.team_id;
 if c.id is null then raise sqlstate '42501' using message='This care update is no longer available';end if;
 return jsonb_build_object('team_id',c.team_id,'case_id',c.id,'update_id',n.health_update_id);
end $$;
create function public.health_notification_open(p_notification_id uuid) returns jsonb
 language sql security invoker set search_path='' as $$select private.health_notification_open(p_notification_id)$$;
revoke all on function private.health_notification_open(uuid),public.health_notification_open(uuid) from public,anon,authenticated;
grant execute on function private.health_notification_open(uuid),public.health_notification_open(uuid) to authenticated;

-- Keep delivery badge counts consistent with the inbox after access is removed.
-- The ordinary get_notification_badge_count() remains SECURITY INVOKER and uses RLS.
create or replace function public.notification_badge_count_for_delivery(p_user_id uuid) returns integer
 language sql stable security definer set search_path='' as $$
 select count(*)::integer from public.communication_notifications n where n.user_id=p_user_id and n.read_at is null
 and (n.weigh_in_id is null or exists(select 1 from private.weigh_in_recipients(n.weigh_in_id) r where r.user_id=p_user_id))
 and (n.health_update_id is null or private.health_notification_visible(n.health_update_id,p_user_id));
$$;
revoke all on function public.notification_badge_count_for_delivery(uuid) from public,anon,authenticated;
grant execute on function public.notification_badge_count_for_delivery(uuid) to service_role;

create or replace function private.athlete_health_request(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid=private.health_actor();t uuid; a uuid;org uuid;c private.health_cases%rowtype;f private.health_files%rowtype;
 settings private.health_team_settings%rowtype;trainer boolean;assigned boolean;coach boolean;guardian boolean;
 year_start date;test_date date;result jsonb;items jsonb;request_id uuid;body text;new_status text;kind text;file_id uuid;role_label text;notice_update uuid;visibility_value text;existing_update private.health_updates%rowtype;
begin
 if u is null then raise sqlstate '42501' using message='Sign in to a personal account to open Athlete Health';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'Invalid health request';end if;
 t:=(p_data->>'team_id')::uuid;
 select organization_id into org from public.teams where id=t;
 if org is null then raise exception 'Choose a current team';end if;
 assigned:=private.health_trainer(t,u,false);trainer:=private.health_trainer(t,u);coach:=public.is_team_staff(t);
 if not assigned and not coach and not exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=u and m.active and m.role in ('athlete','parent_guardian')) then raise sqlstate '42501' using message='No Athlete Health access on this team';end if;
 select * into settings from private.health_team_settings where team_id=t;
 year_start:=coalesce(settings.school_year_start,make_date(extract(year from current_date)::integer-case when extract(month from current_date)<7 then 1 else 0 end,7,1));
 while year_start+interval '1 year'<=current_date loop year_start:=(year_start+interval '1 year')::date;end loop;
 if p_action='accept_trainer' then
  if not assigned or p_data->>'acknowledgement' is distinct from 'trainer-v1' then raise exception 'Review and accept the trainer responsibility';end if;
  insert into private.health_trainers(membership_id,acknowledgement) select m.id,'trainer-v1' from public.team_memberships m where m.team_id=t and m.user_id=u and m.active and m.role='manager' and m.permissions->>'staff_role'='team_trainer' on conflict do nothing;
  perform private.health_event(t,null,null,'trainer_accepted');return jsonb_build_object('accepted',true);
 elsif p_action='settings' then
  if not public.is_team_admin(t) then raise exception 'Team administrator access required';end if;
  test_date:=(p_data->>'school_year_start')::date;
  if test_date is null or test_date<current_date-interval '18 months' or test_date>current_date+interval '6 months' then raise exception 'Choose the current school-year start date';end if;
  if jsonb_typeof(p_data->'baseline_required') is distinct from 'boolean' then raise exception 'Choose whether the school requires a baseline';end if;
  insert into private.health_team_settings(team_id,school_year_start,baseline_required,updated_by) values(t,test_date,(p_data->>'baseline_required')::boolean,u)
  on conflict(team_id) do update set school_year_start=excluded.school_year_start,baseline_required=excluded.baseline_required,updated_by=u,updated_at=now();
  perform private.health_event(t,null,null,'settings_changed',p_data-'team_id');return jsonb_build_object('saved',true);
 elsif p_action='dashboard' then
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'name',x.first_name||' '||x.last_name,
   'baseline',case when b.id is not null and b.revoked_at is null then jsonb_build_object('completed_on',b.completed_on,'provider',b.provider,'verified_at',b.verified_at,'verified_by',private.communication_person_name(t,b.verified_by)) else null end,
   'cases',coalesce((select jsonb_agg(jsonb_build_object('id',hc.id,'category',hc.category,'status',hc.status,'participation_note',hc.participation_note,'review_on',hc.review_on,'return_on',hc.return_on,'updated_at',hc.updated_at) order by hc.updated_at desc) from private.health_cases hc where hc.team_id=t and hc.athlete_id=x.id),'[]'),
   'clinical',trainer or private.health_clinical_family(t,x.id,u),
   'family_permission',case when private.health_guardian(t,x.id,u) then (select jsonb_build_object('allow_updates',hp.allow_updates,'allow_photos',hp.allow_photos) from private.health_family_permissions hp where hp.team_id=t and hp.athlete_id=x.id) else null end,
   'guardian',private.health_guardian(t,x.id,u),'can_submit',private.health_submit(t,x.id,u),'can_upload',private.health_submit(t,x.id,u,true)) order by x.last_name,x.first_name),'[]') into items
  from public.athletes x left join private.health_baselines b on b.organization_id=org and b.athlete_id=x.id and b.school_year_start=year_start
  where private.health_team_athlete(t,x.id) and (trainer or coach or private.health_family(t,x.id,u));
  return jsonb_build_object('care_notifications','in_app_v1','assigned_trainer',assigned,'trainer',trainer,'coach',coach,'admin',public.is_team_admin(t),'school_year_start',year_start,'baseline_required',coalesce(settings.baseline_required,true),'athletes',items,
   'trainers',coalesce((select jsonb_agg(jsonb_build_object('name',private.communication_person_name(t,m.user_id),'accepted',exists(select 1 from private.health_trainers h where h.membership_id=m.id))) from public.team_memberships m where m.team_id=t and m.role='manager' and m.active and m.permissions->>'staff_role'='team_trainer'),'[]'));
 end if;
 if p_data ? 'case_id' then
  select * into c from private.health_cases where id=(p_data->>'case_id')::uuid and team_id=t for update;
  if c.id is null or not private.health_case_access(c.id,false) then raise sqlstate '42501' using message='This health record is unavailable';end if;
  a:=c.athlete_id;
 else a:=(p_data->>'athlete_id')::uuid;end if;
 if a is null or not private.health_team_athlete(t,a) or not (trainer or coach or private.health_family(t,a,u)) then raise sqlstate '42501' using message='This athlete is unavailable';end if;
 guardian:=private.health_guardian(t,a,u);
 if p_action='baseline' then
  if not trainer or p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'The assigned trainer must verify completion in Sway or the named provider';end if;
  test_date:=(p_data->>'completed_on')::date;body:=trim(coalesce(p_data->>'provider','Sway'));
  if test_date is null or test_date>current_date or test_date<year_start or test_date>=year_start+interval '1 year' or length(body) not between 1 and 80 then raise exception 'Enter a completed test date within this school year';end if;
  insert into private.health_baselines(organization_id,athlete_id,school_year_start,provider,completed_on,verified_by,verified_team_id) values(org,a,year_start,body,test_date,u,t)
  on conflict(organization_id,athlete_id,school_year_start) do update set provider=excluded.provider,completed_on=excluded.completed_on,verified_by=u,verified_team_id=t,verified_at=now(),revoked_at=null;
  perform private.health_event(t,a,null,'baseline_verified',jsonb_build_object('completed_on',test_date,'provider',body,'school_year_start',year_start));return jsonb_build_object('saved',true);
 elsif p_action='revoke_baseline' then
  if not trainer then raise exception 'Trainer access required';end if;
  update private.health_baselines set revoked_at=now() where organization_id=org and athlete_id=a and school_year_start=year_start;
  perform private.health_event(t,a,null,'baseline_verification_removed');return jsonb_build_object('saved',true);
 elsif p_action='family_permission' then
  if not guardian or jsonb_typeof(p_data->'allow_updates') is distinct from 'boolean' or jsonb_typeof(p_data->'allow_photos') is distinct from 'boolean' then raise exception 'A connected parent or guardian must choose health-sharing permission';end if;
  insert into private.health_family_permissions(team_id,athlete_id,guardian_id,allow_updates,allow_photos) values(t,a,u,(p_data->>'allow_updates')::boolean,(p_data->>'allow_photos')::boolean)
  on conflict(team_id,athlete_id) do update set guardian_id=u,allow_updates=excluded.allow_updates,allow_photos=excluded.allow_photos,updated_at=now();
  perform private.health_event(t,a,null,'family_permission_changed',p_data-'team_id'-'athlete_id');return jsonb_build_object('saved',true);
 elsif p_action='new_case' then
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
 elsif p_action='case' then
  if c.id is null then raise exception 'Choose a record';end if;
  perform private.health_event(t,a,c.id,'record_viewed');
  return jsonb_build_object('case',to_jsonb(c)-'client_request_id','athlete_name',(select first_name||' '||last_name from public.athletes where id=a),'trainer',trainer,'guardian',guardian,
   'can_submit',private.health_submit(t,a,u),'can_upload',private.health_submit(t,a,u,true),
   'family_permission',case when guardian then (select to_jsonb(p)-'guardian_id' from private.health_family_permissions p where p.team_id=t and p.athlete_id=a) else null end,
   'updates',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'author',n.author_label,'visibility',n.visibility,'body',n.body,'created_at',n.created_at) order by n.created_at) from private.health_updates n where n.case_id=c.id and (n.visibility='participation' or private.health_case_access(c.id,true) or n.author_id=u)),'[]'),
   'files',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'kind',h.file_kind,'mime',h.mime_type,'created_at',h.created_at) order by h.created_at) from private.health_files h where h.case_id=c.id and h.completed_at is not null and (private.health_case_access(c.id,true) or h.uploader_id=u)),'[]'));
 elsif p_action='update' then
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
 elsif p_action='participation' then
  if c.id is null or not trainer then raise exception 'Only the accepted team trainer can record participation decisions';end if;
  if (p_data->>'revision')::integer is distinct from c.revision then raise exception 'This record changed. Reload before saving a decision';end if;
  new_status:=p_data->>'status';body:=trim(coalesce(p_data->>'participation_note',''));
  if new_status is null or new_status not in ('not_cleared','modified','no_contact','cleared') or length(body)>2000 then raise exception 'Choose a participation status';end if;
  if new_status in ('modified','no_contact','not_cleared') and length(body)=0 then raise exception 'Give coaches the participation restrictions';end if;
  test_date:=(p_data->>'return_on')::date;role_label:=trim(coalesce(p_data->>'provider_name',''));file_id:=(p_data->>'clearance_file_id')::uuid;
  if file_id is not null and not exists(select 1 from private.health_files h where h.id=file_id and h.case_id=c.id and h.completed_at is not null and h.file_kind='provider_release') then raise exception 'Choose a completed provider-release upload for this record';end if;
  if new_status='cleared' and (test_date is null or length(role_label) not between 1 and 120 or p_data->'confirmed' is distinct from 'true'::jsonb or (c.category='concussion' and file_id is null)) then raise exception 'Confirm authorized clearance, name the provider and give the return date. Concussion clearance also requires the written release';end if;
  update private.health_cases set status=new_status,participation_note=body,review_on=(p_data->>'review_on')::date,return_on=case when new_status='cleared' then test_date else null end,
   provider_name=nullif(role_label,''),clearance_file_id=file_id,updated_by=u,updated_at=now(),revision=revision+1 where id=c.id;
  insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id) values(c.id,u,private.communication_person_name(t,u),'participation',new_status||case when body<>'' then ': '||body else '' end,gen_random_uuid());
  perform private.health_event(t,a,c.id,'participation_changed',jsonb_build_object('previous_status',c.status,'status',new_status,'return_on',test_date,'provider',role_label,'revision',c.revision+1,'clearance_file_id',file_id));
  return jsonb_build_object('saved',true);
 elsif p_action='reserve_file' then
  if c.id is null or not private.health_submit(t,a,u,true) then raise exception 'Photo/document sharing is not enabled for this account';end if;
  kind:=p_data->>'file_kind';body:=p_data->>'mime_type';
  if kind is null or kind not in ('concern_photo','provider_release') or body is null or body not in ('image/jpeg','application/pdf') or (kind='concern_photo' and body<>'image/jpeg') or coalesce((p_data->>'size_bytes')::bigint,0) not between 1 and 8388608 then raise exception 'Choose a JPEG photo or PDF release up to 8 MB';end if;
  if (select count(*) from private.health_files h where h.uploader_id=u and h.created_at>now()-interval '1 hour')>=30 then raise exception 'Upload limit reached. Please try again later';end if;
  file_id:=gen_random_uuid();
  insert into private.health_files(id,case_id,uploader_id,storage_path,file_kind,mime_type,size_bytes) values(file_id,c.id,u,t::text||'/'||a::text||'/'||c.id::text||'/'||file_id::text||case when body='image/jpeg' then '.jpg' else '.pdf' end,kind,body,(p_data->>'size_bytes')::bigint) returning * into f;
  return jsonb_build_object('id',f.id,'path',f.storage_path,'bucket','athlete-health');
 elsif p_action='complete_file' then
  select * into f from private.health_files where id=(p_data->>'file_id')::uuid and case_id=c.id for update;
  if f.id is null or f.uploader_id<>u or not private.health_submit(t,a,u,true) then raise exception 'This upload is unavailable';end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='athlete-health' and o.name=f.storage_path and o.owner_id=u::text and (o.metadata->>'size')::bigint=f.size_bytes and o.metadata->>'mimetype'=f.mime_type) then raise exception 'Upload is not confirmed. Keep this record open and retry';end if;
  if f.completed_at is null then
   insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id)
    values(c.id,u,private.communication_person_name(t,u),'care_team','A private care attachment was added.',gen_random_uuid());
  end if;
  update private.health_files set completed_at=coalesce(completed_at,now()) where id=f.id;
  perform private.health_event(t,a,c.id,'file_uploaded',jsonb_build_object('file_id',f.id,'kind',f.file_kind));return jsonb_build_object('saved',true);
 elsif p_action='file' then
  select * into f from private.health_files where id=(p_data->>'file_id')::uuid and case_id=c.id;
  if f.id is null or not private.health_file_access(f.storage_path,false) then raise sqlstate '42501' using message='This private file is unavailable';end if;
  perform private.health_event(t,a,c.id,'file_viewed',jsonb_build_object('file_id',f.id));return jsonb_build_object('path',f.storage_path,'bucket','athlete-health','mime',f.mime_type);
 end if;
 raise exception 'Unknown Athlete Health action';
end;
$$;

-- Register the full reviewed catalog and keep both drift guards exact.
do $$declare snapshot jsonb; expected_hash text; source text;begin
 select jsonb_build_object(
  'tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'columns',
   (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull) order by a.attnum)
    from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) order by n.nspname,c.relname),'[]')
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%'),
  'constraints',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',k.conname,'type',k.contype,
   'columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.conkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=c.oid and a.attnum=z.num),
   'ref_schema',rn.nspname,'ref_table',rc.relname,
   'ref_columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.confkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=rc.oid and a.attnum=z.num),
   'delete_action',k.confdeltype) order by n.nspname,c.relname,k.conname),'[]')
   from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
   left join pg_class rc on rc.oid=k.confrelid left join pg_namespace rn on rn.oid=rc.relnamespace
   where n.nspname in ('public','private') and c.relname not like 'scoped_deletion_%')
 ) into snapshot;
 expected_hash:=private.scoped_deletion_schema_hash();
 update private.scoped_deletion_config set catalog=snapshot,catalog_hash=expected_hash where id;
 -- Refresh only the reviewed old fingerprint in the existing merge router.
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if position('73d4ab1a9cf488dc3a0112e1895813cab8698e46335e7f64a9a94d28f1597246' in source)=0 then raise exception 'Unexpected athlete merge version; review compatibility first';end if;
 execute replace(source,'73d4ab1a9cf488dc3a0112e1895813cab8698e46335e7f64a9a94d28f1597246',expected_hash);
end $$;

commit;
