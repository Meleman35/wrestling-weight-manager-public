-- Short-lived, service-only fixtures for real hosted Auth/Storage acceptance.
-- This does not enable deletion for an ordinary enrolled account.
begin;
create table private.scoped_deletion_acceptance_runs(
 id uuid primary key default gen_random_uuid(), token_hash text not null, expires_at timestamptz not null,
 state text not null default 'new', job_id uuid, actor_id uuid, retained_id uuid, child_id uuid,
 team_id uuid not null default gen_random_uuid(), other_team_id uuid not null default gen_random_uuid(),
 organization_id uuid not null default gen_random_uuid(), other_organization_id uuid not null default gen_random_uuid(),
 athlete_id uuid not null default gen_random_uuid(), profile_id uuid not null default gen_random_uuid(),
 wrestling_id uuid not null default gen_random_uuid(), thread_id uuid not null default gen_random_uuid(), message_id uuid not null default gen_random_uuid(),
 result jsonb, created_at timestamptz not null default now()
);
alter table private.scoped_deletion_acceptance_runs enable row level security;
revoke all on private.scoped_deletion_acceptance_runs from public,anon,authenticated;
create function private.scoped_deletion_acceptance_actor(p_actor uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.scoped_deletion_acceptance_runs r join auth.users u on u.id=r.actor_id
  where r.actor_id=p_actor and r.expires_at>now() and r.state='running' and u.raw_app_meta_data->>'scoped_deletion_acceptance'=r.id::text);
$$;
revoke all on function private.scoped_deletion_acceptance_actor(uuid) from public,anon,authenticated;

-- Patch exactly the reviewed disabled gate; all other current-caller, session,
-- enrollment, scope and authority checks remain in the original intake function.
do $$declare definition text;old_gate text:='if not c.enabled or c.catalog_hash is null then';begin
 definition:=pg_get_functiondef('private.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text)'::regprocedure);
 if position(old_gate in definition)=0 then raise exception 'Reviewed intake gate has changed';end if;
 definition:=replace(definition,old_gate,'if (not c.enabled and not private.scoped_deletion_acceptance_actor(a)) or c.catalog_hash is null then');
 execute definition;
end $$;

create function private.scoped_deletion_acceptance(p_action text,p_run uuid,p_hash text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.scoped_deletion_acceptance_runs%rowtype;a uuid;b uuid;c uuid;v_result jsonb;u record;
begin
 if current_setting('role',true)<>'service_role' then raise sqlstate '42501' using message='SERVICE_ONLY';end if;
 select * into r from private.scoped_deletion_acceptance_runs where id=p_run and token_hash=p_hash and expires_at>now() for update;
 if not found then raise sqlstate '42501' using message='ACCEPTANCE_NOT_AUTHORIZED';end if;
 if p_action='authorize' then
  if r.state<>'new' then raise exception 'ACCEPTANCE_ALREADY_STARTED';end if;
  update private.scoped_deletion_acceptance_runs set state='running' where id=r.id;return jsonb_build_object('id',r.id);
 elsif p_action='seed' then
  if r.state<>'running' or r.actor_id is not null then raise exception 'ACCEPTANCE_ALREADY_SEEDED';end if;
  a:=(p_data->>'actor')::uuid;b:=(p_data->>'retained')::uuid;c:=(p_data->>'child')::uuid;
  if a=b or a=c or b=c or (select count(*) from auth.users where id=any(array[a,b,c]) and raw_app_meta_data->>'scoped_deletion_acceptance'=r.id::text and email like '%@tests.example.invalid' and email_confirmed_at is not null)<>3 then raise exception 'ACCEPTANCE_IDENTITIES_INVALID';end if;
  update private.scoped_deletion_acceptance_runs set actor_id=a,retained_id=b,child_id=c where id=r.id;
  insert into public.profiles(id,display_name) values(a,'Synthetic departing adult'),(b,'Synthetic retained adult'),(c,'Synthetic retained athlete') on conflict(id) do nothing;
  insert into public.organizations(id,name) values(r.organization_id,'Synthetic deletion acceptance'),(r.other_organization_id,'Synthetic preserved acceptance');
  insert into public.teams(id,organization_id,name) values(r.team_id,r.organization_id,'Synthetic selected team'),(r.other_team_id,r.other_organization_id,'Synthetic preserved team');
  insert into public.organization_memberships(organization_id,user_id,role) values(r.organization_id,a,'organization_admin'),(r.other_organization_id,b,'organization_admin');
  insert into public.athlete_profiles(id) values(r.profile_id);
  insert into public.athletes(id,organization_id,profile_id,first_name,last_name) values(r.athlete_id,r.organization_id,r.profile_id,'Synthetic','Retained athlete');
  insert into public.team_memberships(team_id,user_id,role) values(r.team_id,a,'head_coach'),(r.team_id,b,'assistant_coach'),(r.other_team_id,a,'assistant_coach'),(r.other_team_id,b,'head_coach');
  insert into public.team_memberships(team_id,user_id,role,athlete_id) values(r.team_id,c,'athlete',r.athlete_id),(r.other_team_id,c,'athlete',r.athlete_id);
  insert into private.wrestling_profiles(id,user_id,name) values(r.wrestling_id,a,'Synthetic departing adult');
  insert into private.wrestling_profiles(athlete_profile_id,name) values(r.profile_id,'Synthetic retained athlete');
  insert into public.communication_threads(id,team_id,kind,created_by) values(r.thread_id,r.team_id,'group',a);
  insert into public.communication_messages(id,thread_id,team_id,sender_user_id,body) values(r.message_id,r.thread_id,r.team_id,a,'Synthetic deletion acceptance message.');
  update public.profiles set photo_path=a::text||'/'||r.id||'.jpg' where id=a;
  update public.profiles set photo_path=b::text||'/'||r.id||'.jpg' where id=b;
  update private.wrestling_profiles set photo_path=r.wrestling_id::text||'/'||r.id||'.jpg' where id=r.wrestling_id;
  insert into public.communication_attachments(message_id,thread_id,team_id,uploader_user_id,storage_path,mime_type,size_bytes)
   values(r.message_id,r.thread_id,r.team_id,a,r.team_id::text||'/'||r.id||'.jpg','image/jpeg',4);
  insert into private.account_deletion_phone_testers(user_id,expires_at) values(a,least(r.expires_at,now()+interval '2 hours'));
  return jsonb_build_object('team',r.team_id,'organization',r.organization_id,'files',jsonb_build_array(
   jsonb_build_object('bucket','profile-photos','path',a::text||'/'||r.id||'.jpg','remove',true),
   jsonb_build_object('bucket','wrestling-profile-photos','path',r.wrestling_id::text||'/'||r.id||'.jpg','remove',true),
   jsonb_build_object('bucket','communication-media','path',r.team_id::text||'/'||r.id||'.jpg','remove',true),
   jsonb_build_object('bucket','profile-photos','path',b::text||'/'||r.id||'.jpg','remove',false)));
 elsif p_action='job' then
  if not exists(select 1 from private.scoped_deletion_jobs where id=(p_data->>'id')::uuid and actor_id=r.actor_id) then raise exception 'ACCEPTANCE_JOB_MISMATCH';end if;
  update private.scoped_deletion_acceptance_runs set job_id=(p_data->>'id')::uuid where id=r.id;return '{}';
 elsif p_action='verify' then
  v_result:=jsonb_build_object(
   'actor_absent',not exists(select 1 from auth.users where id=r.actor_id),
   'actor_profile_absent',not exists(select 1 from public.profiles where id=r.actor_id),
   'message_absent',not exists(select 1 from public.communication_messages where id=r.message_id),
   'snapshot_absent',not exists(select 1 from public.communication_message_audit where message_id=r.message_id),
   'selected_team_absent',not exists(select 1 from public.teams where id=r.team_id),
   'selected_org_absent',not exists(select 1 from public.organizations where id=r.organization_id),
   'other_accounts_preserved',(select count(*) from auth.users where id=any(array[r.retained_id,r.child_id]))=2,
   'other_profiles_preserved',(select count(*) from public.profiles where id=any(array[r.retained_id,r.child_id]))=2,
   'athlete_preserved',exists(select 1 from public.athletes where id=r.athlete_id and profile_id=r.profile_id and organization_id is null),
   'other_memberships_preserved',(select count(*) from public.team_memberships where team_id=r.other_team_id and user_id=any(array[r.retained_id,r.child_id]))=2,
   'other_team_preserved',exists(select 1 from public.teams where id=r.other_team_id and organization_id=r.other_organization_id));
  if exists(select 1 from jsonb_each(v_result) x where x.value<>'true'::jsonb) then raise exception 'HOSTED_PRESERVATION_FAILED';end if;
  update private.scoped_deletion_acceptance_runs set result=v_result||p_data,state='verified' where id=r.id;
  return v_result;
 elsif p_action='failed' then
  update private.scoped_deletion_acceptance_runs set result=jsonb_build_object('error',left(coalesce(p_data->>'code','unknown'),100)) where id=r.id;return '{}';
 end if;
 raise exception 'ACCEPTANCE_INVALID_ACTION';
end $$;
create function public.scoped_deletion_acceptance(p_action text,p_run uuid,p_hash text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.scoped_deletion_acceptance(p_action,p_run,p_hash,p_data)$$;
revoke all on function private.scoped_deletion_acceptance(text,uuid,text,jsonb),public.scoped_deletion_acceptance(text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.scoped_deletion_acceptance(text,uuid,text,jsonb),public.scoped_deletion_acceptance(text,uuid,text,jsonb) to service_role;
create or replace function private.scoped_deletion_media_inventory(p_job uuid,p_records jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j private.scoped_deletion_jobs%rowtype;r jsonb;data jsonb;m record;obj record;col record;ref jsonb;
 path text;email text;result jsonb:='[]';ids uuid[]:='{}';retained uuid[]:='{}';n integer;
begin
 select * into strict j from private.scoped_deletion_jobs where id=p_job;
 for r in select x from jsonb_array_elements(p_records) x where x->>'action'='delete' loop
  data:=private.scoped_deletion_read(r->>'table',jsonb_build_array(r->'key'),null,2)->0;
  for col in select a.attname from pg_attribute a where a.attrelid=to_regclass(r->>'table') and a.attnum>0 and not a.attisdropped
   and a.atttypid='text'::regtype and (a.attname like '%path%' or a.attname like '%url%') loop
   path:=data->>col.attname;
   if path is null or path='' then continue;end if;
   select * into m from private.scoped_deletion_media_columns where table_name=r->>'table' and column_name=col.attname;
   if not found then raise exception 'DELETION_UNREVIEWED_FILE_REFERENCE';end if;
   n:=0;
   for obj in select id,bucket_id,name,version from storage.objects where bucket_id=any(m.buckets) and name=path loop
    n:=n+1;
    if not(obj.id=any(ids)) then
     ids:=array_append(ids,obj.id);
     result:=result||jsonb_build_array(jsonb_build_object('id',obj.id,'bucket',obj.bucket_id,'path',obj.name,'version',obj.version));
    end if;
   end loop;
   -- Missing files are already absent; ambiguous equal paths in multiple buckets
   -- need a reviewed source before any copy can be removed.
   if n>1 then raise exception 'DELETION_AMBIGUOUS_FILE_REFERENCE';end if;
  end loop;
 end loop;
 if j.personal and exists(select 1 from storage.objects where (owner_id=j.actor_id::text or owner=j.actor_id) and not(id=any(ids))) then
  raise exception 'DELETION_UNREVIEWED_UPLOADED_FILE';
 end if;
 if j.personal then
  select u.email into email from auth.users u where u.id=j.actor_id;
  if email is null or email='' then raise exception 'DELETION_IDENTITY_CHANGED';end if;
  for col in select n.nspname schema,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%' loop
   for ref in execute format('select to_jsonb(r) from %I.%I r where position(lower($1) in lower(to_jsonb(r)::text))>0',col.schema,col.name) using email loop
    if not exists(select 1 from jsonb_array_elements(p_records) x where x->>'table'=col.schema||'.'||col.name and x->>'action'='delete'
      and x->'key'=private.scoped_deletion_row_key(col.schema||'.'||col.name,ref)) then raise exception 'DELETION_UNREVIEWED_IDENTITY_COPY';end if;
   end loop;
  end loop;
 end if;
 -- A file that any retained row references is shared, even when its uploader is
 -- the departing user. Check JSON snapshots and copied paths as well as FKs.
 for obj in select * from jsonb_to_recordset(result) as x(id uuid,bucket text,path text,version text) loop
  for col in select n.nspname schema,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%' loop
   for ref in execute format('select to_jsonb(r) from %I.%I r where position($1 in to_jsonb(r)::text)>0',col.schema,col.name) using obj.path loop
    if not exists(select 1 from jsonb_array_elements(p_records) x where x->>'table'=col.schema||'.'||col.name and x->>'action'='delete'
      and x->'key'=private.scoped_deletion_row_key(col.schema||'.'||col.name,ref)) then
     if j.personal and (
       exists(select 1 from storage.objects where id=obj.id and (owner=j.actor_id or owner_id=j.actor_id::text))
       or exists(select 1 from public.profiles where id=j.actor_id and photo_path=obj.path)
       or exists(select 1 from private.wrestling_profiles where user_id=j.actor_id and photo_path=obj.path)
       or exists(select 1 from public.communication_attachments where uploader_user_id=j.actor_id and storage_path=obj.path)
     ) then raise exception 'DELETION_SHARED_FILE_REFERENCE';end if;
     -- A teammate's portable photo copied into a team staff row is still their
     -- personal file. Removing the team row does not authorize removing that file.
     retained:=array_append(retained,obj.id);
    end if;
   end loop;
  end loop;
 end loop;
 select coalesce(jsonb_agg(x order by x->>'id'),'[]') into result from jsonb_array_elements(result) x where not((x->>'id')::uuid=any(retained));
 return result;
end $$;

notify pgrst,'reload schema';
commit;
