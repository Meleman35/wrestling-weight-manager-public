-- Athlete Health is a record/communication system; no automated medical decisions.
-- Private tables have no client table grants. All access passes current-session
-- checks and team/family authorization through the bounded RPC below.
create table private.health_team_settings (
 team_id uuid primary key references public.teams(id) on delete restrict,
 school_year_start date not null, baseline_required boolean not null default true,
 updated_by uuid references auth.users(id) on delete restrict, updated_at timestamptz not null default now()
);
create table private.health_trainers (
 membership_id uuid primary key references public.team_memberships(id) on delete cascade,
 accepted_at timestamptz not null default now(), acknowledgement text not null check(acknowledgement='trainer-v1')
);
create table private.health_baselines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 athlete_id uuid not null references public.athletes(id) on delete restrict, school_year_start date not null,
 provider text not null default 'Sway' check(length(provider) between 1 and 80), completed_on date not null,
 verified_by uuid not null references auth.users(id) on delete restrict, verified_team_id uuid not null references public.teams(id) on delete restrict,
 verified_at timestamptz not null default now(), revoked_at timestamptz,
 unique(organization_id,athlete_id,school_year_start),
 check(completed_on>=school_year_start and completed_on<school_year_start+interval '1 year')
);
create table private.health_family_permissions (
 team_id uuid not null references public.teams(id) on delete restrict, athlete_id uuid not null references public.athletes(id) on delete restrict,
 guardian_id uuid not null references auth.users(id) on delete restrict,
 allow_updates boolean not null default false, allow_photos boolean not null default false,
 updated_at timestamptz not null default now(), primary key(team_id,athlete_id), check(not allow_photos or allow_updates)
);
create table private.health_cases (
 id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id) on delete restrict,
 athlete_id uuid not null references public.athletes(id) on delete restrict,
 category text not null check(category in ('injury','skin','concussion','other')),
 noticed_on date not null, status text not null default 'awaiting_trainer' check(status in ('awaiting_trainer','not_cleared','modified','no_contact','cleared')),
 participation_note text not null default '' check(length(participation_note)<=2000),
 review_on date, return_on date, provider_name text check(length(provider_name)<=120),
 clearance_file_id uuid, opened_by uuid not null references auth.users(id) on delete restrict,
 updated_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), revision integer not null default 1,
 client_request_id uuid not null, unique(opened_by,client_request_id)
);
create index health_cases_team_athlete on private.health_cases(team_id,athlete_id,updated_at desc);
create table private.health_updates (
 id uuid primary key default gen_random_uuid(), case_id uuid not null references private.health_cases(id) on delete restrict,
 author_id uuid not null references auth.users(id) on delete restrict, author_label text not null,
 visibility text not null check(visibility in ('care_team','participation')),
 body text not null check(length(body) between 1 and 4000), created_at timestamptz not null default now(),
 client_request_id uuid not null, unique(author_id,client_request_id)
);
create index health_updates_case on private.health_updates(case_id,created_at);
create table private.health_files (
 id uuid primary key default gen_random_uuid(), case_id uuid not null references private.health_cases(id) on delete restrict,
 uploader_id uuid not null references auth.users(id) on delete restrict,
 storage_path text not null unique, file_kind text not null check(file_kind in ('concern_photo','provider_release')),
 mime_type text not null check(mime_type in ('image/jpeg','application/pdf')), size_bytes bigint not null check(size_bytes between 1 and 8388608),
 created_at timestamptz not null default now(), completed_at timestamptz,
 check(file_kind<>'concern_photo' or mime_type='image/jpeg')
);
create index health_files_case on private.health_files(case_id);
alter table private.health_cases add constraint health_cases_clearance_file foreign key(clearance_file_id) references private.health_files(id) on delete restrict;
create table private.health_events (
 id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id) on delete restrict,
 athlete_id uuid references public.athletes(id) on delete restrict, case_id uuid references private.health_cases(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict, action text not null,
 details jsonb not null default '{}', created_at timestamptz not null default now()
);
create index health_events_case on private.health_events(case_id,created_at);

create function private.health_actor() returns uuid language sql stable security definer set search_path='' as $$
 select u.id from auth.users u where u.id=auth.uid() and u.deleted_at is null and u.email_confirmed_at is not null
 and (u.banned_until is null or u.banned_until<=now())
 and exists(select 1 from auth.sessions s where s.user_id=u.id and s.id::text=auth.jwt()->>'session_id' and (s.not_after is null or s.not_after>now()))
 and not exists(select 1 from private.team_logins l where l.user_id=u.id)
 and private.scoped_deletion_access_ok();
$$;
create function private.health_trainer(t uuid,u uuid,accepted boolean default true) returns boolean language sql stable security definer set search_path='' as $$
 select u is not null and exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=u and m.active
 and m.role='manager' and m.permissions->>'staff_role'='team_trainer'
 and (not accepted or exists(select 1 from private.health_trainers h where h.membership_id=m.id)))
 and not exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id left join public.athlete_private_identity i on i.athlete_id=a.id
 where m.user_id=u and m.role='athlete' and coalesce(i.birth_date,a.birth_date)>(current_date-interval '18 years')::date);
$$;
create function private.health_guardian(t uuid,a uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.athlete_guardians g join public.team_memberships m on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id
 where g.athlete_id=a and g.guardian_user_id=u and m.team_id=t and m.role='parent_guardian' and m.active);
$$;
create function private.health_self(t uuid,a uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.team_memberships m where m.team_id=t and m.athlete_id=a and m.user_id=u and m.role='athlete' and m.active);
$$;
create function private.health_family(t uuid,a uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.health_guardian(t,a,u) or private.health_self(t,a,u);
$$;
create function private.health_team_athlete(t uuid,a uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where s.team_id=t and s.active and r.athlete_id=a and r.active and r.roster_status not in ('inactive','removed','standby'))
 or exists(select 1 from public.team_memberships m where m.team_id=t and m.athlete_id=a and m.role='athlete' and m.active);
$$;
create function private.health_submit(t uuid,a uuid,u uuid,media boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select private.health_team_athlete(t,a) and (private.health_trainer(t,u) or public.is_team_staff(t) or private.health_guardian(t,a,u)
 or (private.health_self(t,a,u) and exists(select 1 from public.athletes x left join public.athlete_private_identity i on i.athlete_id=x.id where x.id=a and (
  coalesce(i.birth_date,x.birth_date)<=(current_date-interval '18 years')::date
  or (coalesce(i.birth_date,x.birth_date)<=(current_date-interval '13 years')::date and exists(select 1 from private.health_family_permissions p
   where p.team_id=t and p.athlete_id=a and p.allow_updates and (not media or p.allow_photos) and private.health_guardian(t,a,p.guardian_id)))))));
$$;
create function private.health_clinical_family(t uuid,a uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.health_guardian(t,a,u) or (private.health_self(t,a,u) and (
  exists(select 1 from public.athletes x left join public.athlete_private_identity i on i.athlete_id=x.id where x.id=a and coalesce(i.birth_date,x.birth_date)<=(current_date-interval '18 years')::date)
  or exists(select 1 from private.health_family_permissions p where p.team_id=t and p.athlete_id=a and p.allow_updates and private.health_guardian(t,a,p.guardian_id))));
$$;
create function private.health_case_access(c uuid,clinical boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select private.health_actor() is not null and exists(select 1 from private.health_cases x where x.id=c and private.health_team_athlete(x.team_id,x.athlete_id)
 and (private.health_trainer(x.team_id,auth.uid()) or private.health_clinical_family(x.team_id,x.athlete_id,auth.uid()) or (not clinical and (public.is_team_staff(x.team_id) or private.health_family(x.team_id,x.athlete_id,auth.uid())))));
$$;
create function private.health_file_access(path text,upload boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select private.health_actor() is not null and exists(select 1 from private.health_files f join private.health_cases c on c.id=f.case_id where f.storage_path=path
 and private.health_case_access(c.id,false) and case when upload then f.uploader_id=auth.uid() and f.completed_at is null and f.created_at>now()-interval '20 minutes'
 and private.health_submit(c.team_id,c.athlete_id,auth.uid(),true)
 else f.completed_at is not null and (private.health_case_access(c.id,true) or f.uploader_id=auth.uid()) end);
$$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('athlete-health','athlete-health',false,8388608,array['image/jpeg','application/pdf']);
create policy athlete_health_read on storage.objects for select to authenticated using(bucket_id='athlete-health' and private.health_file_access(name,false));
create policy athlete_health_upload on storage.objects for insert to authenticated with check(bucket_id='athlete-health' and private.health_file_access(name,true));
-- Defense in depth against unrelated permissive policies. Health files are immutable.
create policy athlete_health_read_guard on storage.objects as restrictive for select to authenticated using(bucket_id<>'athlete-health' or private.health_file_access(name,false));
create policy athlete_health_upload_guard on storage.objects as restrictive for insert to authenticated with check(bucket_id<>'athlete-health' or private.health_file_access(name,true));
create policy athlete_health_no_update on storage.objects as restrictive for update to authenticated using(bucket_id<>'athlete-health') with check(bucket_id<>'athlete-health');
create policy athlete_health_no_delete on storage.objects as restrictive for delete to authenticated using(bucket_id<>'athlete-health');

create function private.health_event(t uuid,a uuid,c uuid,action_name text,event_data jsonb default '{}') returns void language sql security definer set search_path='' as $$
 insert into private.health_events(team_id,athlete_id,case_id,actor_id,action,details) values(t,a,c,auth.uid(),action_name,event_data);
$$;

create function private.athlete_health_request(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid=private.health_actor();t uuid; a uuid;org uuid;c private.health_cases%rowtype;f private.health_files%rowtype;
 settings private.health_team_settings%rowtype;trainer boolean;assigned boolean;coach boolean;guardian boolean;
 year_start date;test_date date;result jsonb;items jsonb;request_id uuid;body text;new_status text;kind text;file_id uuid;role_label text;
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
  return jsonb_build_object('assigned_trainer',assigned,'trainer',trainer,'coach',coach,'admin',public.is_team_admin(t),'school_year_start',year_start,'baseline_required',coalesce(settings.baseline_required,true),'athletes',items,
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
  if request_id is null or kind is null or kind not in ('injury','skin','concussion','other') or length(body) not between 1 and 4000 or test_date is null or test_date>current_date then raise exception 'Enter the concern, date and brief details';end if;
  select * into c from private.health_cases where opened_by=u and client_request_id=request_id;
  if c.id is not null then
   if c.team_id<>t or c.athlete_id<>a then raise exception 'This request belongs to a different record';end if;
   return jsonb_build_object('case_id',c.id);
  end if;
  insert into private.health_cases(team_id,athlete_id,category,noticed_on,opened_by,updated_by,client_request_id) values(t,a,kind,test_date,u,u,request_id) returning * into c;
  insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id) values(c.id,u,private.communication_person_name(t,u),'care_team',body,request_id);
  perform private.health_event(t,a,c.id,'concern_reported');return jsonb_build_object('case_id',c.id);
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
  if exists(select 1 from private.health_updates n where n.author_id=u and n.client_request_id=request_id and n.case_id<>c.id) then raise exception 'This request belongs to a different record';end if;
  kind:=coalesce(p_data->>'visibility','care_team');
  if kind not in ('care_team','participation') or (kind='participation' and not trainer) then raise exception 'Only the trainer can share an update with coaches';end if;
  insert into private.health_updates(case_id,author_id,author_label,visibility,body,client_request_id) values(c.id,u,private.communication_person_name(t,u),kind,body,request_id) on conflict(author_id,client_request_id) do nothing;
  update private.health_cases set updated_at=now() where id=c.id;
  perform private.health_event(t,a,c.id,'care_update',jsonb_build_object('visibility',kind));return jsonb_build_object('saved',true);
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
create function public.athlete_health_request(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.athlete_health_request(p_action,p_data)$$;

do $$declare r record;begin
 for r in select c.oid::regclass relation from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r' and c.relname like 'health_%' loop
  execute format('alter table %s enable row level security',r.relation);
  execute format('revoke all on table %s from public,anon,authenticated',r.relation);
  execute format('create trigger scoped_deletion_freeze before insert or update or delete on %s for each row execute function private.scoped_deletion_freeze()',r.relation);
 end loop;
 for r in select p.oid::regprocedure identity from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and (p.proname like 'health_%' or p.proname='athlete_health_request') loop
  execute format('revoke all on function %s from public,anon,authenticated',r.identity);
 end loop;
end $$;
grant execute on function public.athlete_health_request(text,jsonb),private.athlete_health_request(text,jsonb),private.health_file_access(text,boolean) to authenticated;
