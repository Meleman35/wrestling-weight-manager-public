-- Enrolled scoped erasure. Install only with its verified worker and access guards.
-- This configuration begins disabled; installation does not queue or erase an account.
begin;
create table private.scoped_deletion_config(
 id boolean primary key default true check(id), enabled boolean not null default false,
 catalog jsonb, policy_version text not null default 'scoped-deletion-v1', catalog_hash text,
 max_rows integer not null default 25000 check(max_rows between 1 and 100000)
);
insert into private.scoped_deletion_config(id) values(true);
create table private.scoped_deletion_jobs(
 id uuid primary key default gen_random_uuid(), actor_id uuid, subject_hash text not null, request_id uuid not null,
 kind text not null check(kind in ('personal','team','organization','all')),
 personal boolean not null, team_ids uuid[] not null, organization_ids uuid[] not null,
 receipt_hash text not null check(receipt_hash~'^[a-f0-9]{64}$'),
 policy_version text not null, catalog_hash text not null,
 state text not null default 'planning' check(state in ('planning','sealed','revoking','media','records','auth','verifying','completed','blocked')),
 lease_token uuid, lease_until timestamptz, retry_after timestamptz, attempts integer not null default 0,
 error_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 sealed_at timestamptz, completed_at timestamptz, unique(actor_id,request_id)
);
create table private.scoped_deletion_rows(
 job_id uuid not null references private.scoped_deletion_jobs(id) on delete cascade,
 table_name text not null, row_key jsonb not null, action text not null check(action in ('delete','null','auth')),
 null_columns text[] not null default '{}', source_hash text not null, applied boolean not null default false,
 primary key(job_id,table_name,row_key)
);
create table private.scoped_deletion_filters(
 job_id uuid not null references private.scoped_deletion_jobs(id) on delete cascade,
 table_name text not null, predicate jsonb not null, mention_columns text[] not null default '{}',
 primary key(job_id,table_name,predicate)
);
create table private.scoped_deletion_objects(
 job_id uuid not null references private.scoped_deletion_jobs(id) on delete cascade,
 object_id uuid not null, bucket text not null, object_key text not null, version text,
 removed_at timestamptz, primary key(job_id,object_id), unique(job_id,bucket,object_key)
);
do $$ declare t text; begin
 foreach t in array array['scoped_deletion_config','scoped_deletion_jobs','scoped_deletion_rows','scoped_deletion_filters','scoped_deletion_objects'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on private.%I to service_role',t);
 end loop;
end $$;

create function private.scoped_deletion_check_authority(p_actor uuid,p_personal boolean,p_teams uuid[],p_orgs uuid[])
returns void language plpgsql security definer set search_path='' as $$
declare handoff_team record; handoff_org record;
begin
 -- Called only by the current-caller intake or a leased service transaction.
 -- Lock both membership sets before checking every target and surviving workspace.
 lock table public.team_memberships,public.organization_memberships in share row exclusive mode;
 lock table private.team_logins in share mode;
 perform id from public.teams where id=any(p_teams) or organization_id=any(p_orgs) order by id for share;
 perform id from public.organizations where id=any(p_orgs) order by id for share;
 if not exists(select 1 from auth.users u where u.id=p_actor and u.email_confirmed_at is not null
   and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
   or exists(select 1 from private.team_logins where user_id=p_actor) then
  raise sqlstate '42501' using message='DELETION_SIGN_IN_REQUIRED';
 end if;
 if (select count(*) from public.teams where id=any(p_teams))<>cardinality(p_teams)
   or (select count(*) from public.organizations where id=any(p_orgs))<>cardinality(p_orgs) then
  raise sqlstate '42501' using message='DELETION_TARGET_CHANGED';
 end if;
 if exists(select 1 from public.organizations o where o.id=any(p_orgs) and not exists(
  select 1 from public.organization_memberships m where m.organization_id=o.id and m.user_id=p_actor and m.role='organization_admin')) then
  raise sqlstate '42501' using message='DELETION_NOT_ADMINISTRATOR';
 end if;
 if exists(select 1 from public.teams t where t.id=any(p_teams) and not exists(
  select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=p_actor and m.active
   and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false))))
  and not exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=p_actor and m.role='organization_admin')) then
  raise sqlstate '42501' using message='DELETION_NOT_ADMINISTRATOR';
 end if;
 if exists(select 1 from public.teams where organization_id=any(p_orgs) and not(id=any(p_teams))) then
  raise sqlstate 'P0001' using message='DELETION_LINKED_TEAMS_NOT_SELECTED';
 end if;
 if not p_personal then return; end if;
 -- A confirmed accepted role must remain. Invitations and managed logins never count.
 perform u.id from auth.users u where exists(select 1 from public.organization_memberships m where m.user_id=u.id
   and exists(select 1 from public.organization_memberships a where a.user_id=p_actor and a.organization_id=m.organization_id))
  or exists(select 1 from public.team_memberships m where m.user_id=u.id and exists(
   select 1 from public.team_memberships a where a.user_id=p_actor and a.team_id=m.team_id)) order by u.id for share;
 for handoff_org in select organization_id from public.organization_memberships where user_id=p_actor and role='organization_admin' and not(organization_id=any(p_orgs)) loop
  if not exists(select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id
   where m.organization_id=handoff_org.organization_id and m.user_id<>p_actor and m.role='organization_admin'
    and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
    and not exists(select 1 from private.team_logins l where l.user_id=u.id)) then
   raise sqlstate 'P0001' using message='DELETION_ORGANIZATION_HANDOFF_REQUIRED';
  end if;
 end loop;
 for handoff_team in select distinct t.id,t.organization_id from public.teams t where not(t.id=any(p_teams)) and (
  exists(select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=p_actor and m.active
    and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false))))
  or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id and m.user_id=p_actor and m.role='organization_admin')) loop
  if not exists(select 1 from auth.users u where u.id<>p_actor and u.email_confirmed_at is not null and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now()) and not exists(select 1 from private.team_logins l where l.user_id=u.id)
   and (exists(select 1 from public.team_memberships m where m.team_id=handoff_team.id and m.user_id=u.id and m.active
     and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false))))
    or exists(select 1 from public.organization_memberships m where m.organization_id=handoff_team.organization_id and m.user_id=u.id and m.role='organization_admin'))) then
   raise sqlstate 'P0001' using message='DELETION_TEAM_HANDOFF_REQUIRED';
  end if;
 end loop;
end $$;
revoke all on function private.scoped_deletion_check_authority(uuid,boolean,uuid[],uuid[]) from public,anon,authenticated;

create function private.scoped_deletion_begin(p_kind text,p_team_ids uuid[],p_organization_ids uuid[],p_confirmation text,p_request_id uuid,p_receipt_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); b jsonb; c private.scoped_deletion_config%rowtype; j private.scoped_deletion_jobs%rowtype;
 ts uuid[]; os uuid[]; personal boolean;
begin
 b:=private.account_deletion_phone_preflight();
 if b->>'enabled' is distinct from 'true' then raise sqlstate '42501' using message='DELETION_SIGN_IN_REQUIRED';end if;
 if p_kind is null or p_kind not in ('personal','team','organization','all') or p_confirmation is distinct from 'delete'
  or p_request_id is null or p_receipt_hash is null or p_receipt_hash !~ '^[a-f0-9]{64}$'
  or p_team_ids is null or p_organization_ids is null or cardinality(p_team_ids)>100 or cardinality(p_organization_ids)>100
  or array_position(p_team_ids,null) is not null or array_position(p_organization_ids,null) is not null then
  raise sqlstate '22023' using message='DELETION_INVALID_CONFIRMATION';
 end if;
 select coalesce(array_agg(x order by x),'{}') into ts from (select distinct unnest(p_team_ids) x) s;
 select coalesce(array_agg(x order by x),'{}') into os from (select distinct unnest(p_organization_ids) x) s;
 if cardinality(ts)<>cardinality(p_team_ids) or cardinality(os)<>cardinality(p_organization_ids)
  or (p_kind='personal' and (cardinality(ts)>0 or cardinality(os)>0))
  or (p_kind='team' and (cardinality(ts)<>1 or cardinality(os)>0))
  or (p_kind='organization' and (cardinality(os)<>1 or cardinality(ts)>0))
  or (p_kind='all' and cardinality(ts)+cardinality(os)=0) then
  raise sqlstate '22023' using message='DELETION_INVALID_TARGETS';
 end if;
 personal:=p_kind in ('personal','all');
 perform pg_advisory_xact_lock(hashtextextended(a::text,91347));
 select * into j from private.scoped_deletion_jobs where actor_id=a and request_id=p_request_id;
 if found then
  if j.kind<>p_kind or j.team_ids<>ts or j.organization_ids<>os or j.receipt_hash<>p_receipt_hash then
   raise sqlstate '22023' using message='DELETION_REQUEST_MISMATCH';
  end if;
  return jsonb_build_object('id',j.id,'state',j.state,'request_id',j.request_id);
 end if;
 select * into c from private.scoped_deletion_config where id;
 if not c.enabled or c.catalog_hash is null then raise sqlstate '55000' using message='DELETION_NOT_ENABLED';end if;
 if exists(select 1 from private.scoped_deletion_jobs where actor_id=a and (state not in ('completed','blocked') or (state='blocked' and sealed_at is not null))) then
  raise sqlstate 'P0001' using message='DELETION_ALREADY_IN_PROGRESS';
 end if;
 perform private.scoped_deletion_check_authority(a,personal,ts,os);
 if private.account_deletion_phone_preflight()->>'enabled' is distinct from 'true' then raise sqlstate '42501' using message='DELETION_SIGN_IN_REQUIRED';end if;
 insert into private.scoped_deletion_jobs(actor_id,subject_hash,request_id,kind,personal,team_ids,organization_ids,receipt_hash,policy_version,catalog_hash)
 values(a,encode(sha256(convert_to(a::text,'UTF8')),'hex'),p_request_id,p_kind,personal,ts,os,p_receipt_hash,c.policy_version,c.catalog_hash) returning * into j;
 return jsonb_build_object('id',j.id,'state',j.state,'request_id',j.request_id);
end $$;
revoke all on function private.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text) from public,anon,authenticated;
grant execute on function private.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text) to authenticated;
create function public.scoped_deletion_begin(p_kind text,p_team_ids uuid[],p_organization_ids uuid[],p_confirmation text,p_request_id uuid,p_receipt_hash text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.scoped_deletion_begin(p_kind,p_team_ids,p_organization_ids,p_confirmation,p_request_id,p_receipt_hash);
$$;
revoke all on function public.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text) from public,anon,authenticated;
grant execute on function public.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text) to authenticated;
-- BEGIN GENERATED SCOPED SERVICE
-- Included by the migration assembly; this file is not a standalone deployment.
create unique index scoped_deletion_exclusive_row on private.scoped_deletion_rows(table_name,row_key);
create unique index scoped_deletion_exclusive_object on private.scoped_deletion_objects(bucket,object_key);
create index scoped_deletion_filter_table on private.scoped_deletion_filters(table_name);

create function private.scoped_deletion_schema_hash() returns text
language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(coalesce(string_agg(x,'|' order by x),''),'UTF8')),'hex') from (
  select n.nspname||'.'||c.relname||'.'||a.attname||':'||a.atttypid||':'||a.atttypmod||':'||a.attnotnull||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),'') x
  from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
  where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%'
  union all select n.nspname||'.'||c.relname||':'||pg_get_constraintdef(k.oid)
   from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','private') and c.relname not like 'scoped_deletion_%'
  union all select pg_get_triggerdef(t.oid)||':'||pg_get_functiondef(t.tgfoid)
   from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where not t.tgisinternal and n.nspname in ('public','private') and t.tgname<>'scoped_deletion_freeze'
 ) s;
$$;
create function private.scoped_deletion_matches(p_row jsonb,p_predicates jsonb,p_mention jsonb default null)
returns boolean language plpgsql immutable set search_path='' as $$
declare p jsonb; k text; v jsonb; yes boolean;
begin
 if p_mention is not null then
  for k in select jsonb_array_elements_text(p_mention->'columns') loop
   if (case when coalesce((p_mention->>'ignoreCase')::boolean,false) then position(lower(p_mention->>'actorId') in lower(coalesce((case when k='*' then p_row else p_row->k end)::text,''))) else position(p_mention->>'actorId' in coalesce((case when k='*' then p_row else p_row->k end)::text,'')) end)>0 then return true;end if;
  end loop;return false;
 end if;
 for p in select jsonb_array_elements(coalesce(p_predicates,'[]')) loop
  yes:=true;
  for k,v in select * from jsonb_each(p) loop
   if (p_row->>k) is distinct from (v#>>'{}') then yes:=false;exit;end if;
  end loop;
  if yes then return true;end if;
 end loop;return false;
end $$;
create function private.scoped_deletion_row_key(p_table text,p_row jsonb) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_object_agg(a.attname,p_row->>a.attname) from pg_constraint k
 join pg_attribute a on a.attrelid=k.conrelid and a.attnum=any(k.conkey)
 where k.contype='p' and k.conrelid=to_regclass(p_table);
$$;
create function private.scoped_deletion_read(p_table text,p_predicates jsonb,p_mention jsonb,p_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; s text; t text; col text;
begin
 s:=split_part(p_table,'.',1);t:=split_part(p_table,'.',2);
 if s not in ('public','private') or p_table!~'^[a-z_]+\.[a-z_][a-z0-9_]*$' or t like 'scoped_deletion_%'
  or p_limit not between 1 and 100001 or not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=s and c.relname=t and c.relkind='r') then
  raise exception 'DELETION_INVALID_READ';
 end if;
 if p_mention is not null then
  if p_mention->>'actorId'!~'^[a-f0-9-]{36}$' then raise exception 'DELETION_INVALID_READ';end if;
  for col in select jsonb_array_elements_text(p_mention->'columns') loop
   if not exists(select 1 from pg_attribute where attrelid=to_regclass(p_table) and attname=col and atttypid in ('json'::regtype,'jsonb'::regtype)) then raise exception 'DELETION_INVALID_READ';end if;
  end loop;
 elsif jsonb_typeof(p_predicates) is distinct from 'array' or jsonb_array_length(p_predicates)=0 then raise exception 'DELETION_INVALID_READ';
 end if;
 execute format('select coalesce(jsonb_agg(value || jsonb_build_object(''__deletion_key'',private.scoped_deletion_row_key($4,value),''__deletion_hash'',encode(sha256(convert_to(value::text,''UTF8'')),''hex''))),''[]'') from (select to_jsonb(r) value from %I.%I r where private.scoped_deletion_matches(to_jsonb(r),$1,$2) limit $3) q',s,t)
 into result using p_predicates,p_mention,p_limit,p_table;
 return result;
end $$;

create function private.scoped_deletion_freeze() returns trigger language plpgsql security definer set search_path='' as $$
declare f record; planned private.scoped_deletion_rows%rowtype; oldrow jsonb; newrow jsonb; worker text:=current_setting('wm.scoped_deletion_job',true);
begin
 if not exists(select 1 from private.scoped_deletion_jobs where sealed_at is not null and completed_at is null) then
  if tg_op='DELETE' then return old;else return new;end if;
 end if;
 if tg_op<>'INSERT' then oldrow:=to_jsonb(old);end if;
 if tg_op<>'DELETE' then newrow:=to_jsonb(new);end if;
 if worker is not null and worker<>'' and current_setting('role',true)='service_role'
  and exists(select 1 from private.scoped_deletion_jobs where id::text=worker and lease_token::text=current_setting('wm.scoped_deletion_lease',true) and lease_until>now()) then
  select * into planned from private.scoped_deletion_rows where job_id::text=worker and table_name=tg_table_schema||'.'||tg_table_name
   and row_key=private.scoped_deletion_row_key(tg_table_schema||'.'||tg_table_name,coalesce(oldrow,newrow));
  if not found or tg_op='INSERT' or (tg_op='DELETE' and planned.action<>'delete')
   or (tg_op='UPDATE' and planned.action='null' and (oldrow-(planned.null_columns||array['updated_at'])) is distinct from (newrow-(planned.null_columns||array['updated_at']))) then
   raise exception 'DELETION_UNPLANNED_WRITE';
  end if;
 end if;
 for f in select d.*,j.id from private.scoped_deletion_filters d join private.scoped_deletion_jobs j on j.id=d.job_id
  where d.table_name=tg_table_schema||'.'||tg_table_name and j.sealed_at is not null and j.completed_at is null loop
  -- This GUC is set only inside the leased service transaction. Ordinary callers
  -- cannot bypass the guard by copying it into an RPC request or JWT metadata.
  if worker=f.id::text and current_setting('role',true) in ('service_role','none')
   and current_setting('wm.scoped_deletion_lease',true)=(select lease_token::text from private.scoped_deletion_jobs where id=f.id and lease_until>now()) then continue;end if;
  if private.scoped_deletion_matches(oldrow,f.predicate->'predicates',f.predicate->'mention')
    or private.scoped_deletion_matches(newrow,f.predicate->'predicates',f.predicate->'mention') then
   raise sqlstate '55000' using message='DELETION_RECORDS_LOCKED';
  end if;
 end loop;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;

create function private.scoped_deletion_service(p_op text,p_job uuid,p_lease uuid,p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j private.scoped_deletion_jobs%rowtype;c private.scoped_deletion_config%rowtype;
 r jsonb; o jsonb; actual jsonb; expected jsonb; key jsonb; tab text; s text; t text; assignments text;
 deleted bigint; remaining bigint; progressed boolean; rowrecord record; hash text;
begin
 -- The public wrapper has EXECUTE only for service_role. Check the actual SQL
 -- role too: a forged JWT claim or user metadata alone is never sufficient.
 if current_setting('role',true)<>'service_role' then raise sqlstate '42501' using message='DELETION_SERVICE_ONLY';end if;
 if p_op='resolve' then
  select * into j from private.scoped_deletion_jobs where request_id=(p_input->>'request_id')::uuid and receipt_hash=p_input->>'receipt_hash';
  if not found then raise exception 'DELETION_RECEIPT_REQUIRED';end if;
  return jsonb_build_object('id',j.id,'state',j.state,'personal',j.personal,'subjectHash',j.subject_hash);
 end if;
 select * into j from private.scoped_deletion_jobs where id=p_job for update;
 if not found then raise exception 'DELETION_JOB_NOT_FOUND';end if;
 if p_op='claim' then
  if p_input->>'receipt_hash' is distinct from j.receipt_hash then raise sqlstate '42501' using message='DELETION_RECEIPT_REQUIRED';end if;
  if j.state in ('completed','blocked') or j.lease_until>now() or j.retry_after>now() then
   return jsonb_build_object('id',j.id,'state',j.state,'pending',j.state not in ('completed','blocked'),'code',j.error_code,'personal',j.personal,'subjectHash',j.subject_hash);
  end if;
  update private.scoped_deletion_jobs set lease_token=gen_random_uuid(),lease_until=now()+interval '2 minutes',attempts=attempts+1,updated_at=now()
   where id=j.id returning * into j;
  return jsonb_build_object('id',j.id,'state',j.state,'lease',j.lease_token);
 end if;
 if p_lease is null or j.lease_token is distinct from p_lease or j.lease_until<=now() then raise sqlstate '42501' using message='DELETION_LEASE_REQUIRED';end if;
 update private.scoped_deletion_jobs set lease_until=now()+interval '2 minutes',updated_at=now() where id=j.id;
 select * into c from private.scoped_deletion_config where id;
 if p_op='release' then
  update private.scoped_deletion_jobs set lease_token=null,lease_until=null where id=j.id;return '{}';
 elsif p_op='failed' then
  update private.scoped_deletion_jobs set state=case when (p_input->>'terminal')::boolean and sealed_at is null then 'blocked' else state end,
   error_code=case when p_input->>'code'~'^[a-z_]{1,70}$' then p_input->>'code' else 'retry_required' end,
   retry_after=now()+interval '20 seconds' where id=j.id;return '{}';
 elsif p_op='context' and j.state='planning' then
  if c.catalog_hash<>private.scoped_deletion_schema_hash() or c.catalog is null then raise exception 'DELETION_SCHEMA_CHANGED';end if;
  return jsonb_build_object('catalog',c.catalog,'catalogHash',c.catalog_hash,'maxRows',c.max_rows,
    'scope',jsonb_build_object('actorId',j.actor_id,'kind',j.kind,'teamIds',j.team_ids,'organizationIds',j.organization_ids));
 elsif p_op='read' and j.state='planning' then
  return private.scoped_deletion_read(p_input->>'table',p_input->'predicates',p_input->'mention',least(c.max_rows+1,(p_input->>'limit')::integer));
 elsif p_op='seal' and j.state='planning' then
  if p_input->>'version' is distinct from c.policy_version or p_input->>'catalog_hash' is distinct from c.catalog_hash
    or c.catalog_hash<>private.scoped_deletion_schema_hash() then raise exception 'DELETION_SCHEMA_CHANGED';end if;
  perform private.scoped_deletion_check_authority(j.actor_id,j.personal,j.team_ids,j.organization_ids);
  -- Lock observed tables in a deterministic order. This includes empty reads so
  -- newly inserted dependencies cannot fall between inventory and the freeze.
  for tab in select distinct x->>'table' from jsonb_array_elements(p_input->'observations') x order by 1 loop
   perform private.scoped_deletion_read(tab,'[{"id":"00000000-0000-0000-0000-000000000000"}]',null,1);
   execute format('lock table %I.%I in share row exclusive mode',split_part(tab,'.',1),split_part(tab,'.',2));
  end loop;
  for o in select jsonb_array_elements(p_input->'observations') loop
   actual:=private.scoped_deletion_read(o->>'table',o->'predicates',o->'mention',c.max_rows+1);
   select coalesce(jsonb_agg(jsonb_build_object('key',x->'__deletion_key','hash',x->>'__deletion_hash') order by (x->'__deletion_key')::text),'[]') into actual from jsonb_array_elements(actual) x;
   select coalesce(jsonb_agg(x order by (x->'key')::text),'[]') into expected from jsonb_array_elements(o->'rows') x;
   if actual<>expected then raise exception 'DELETION_INVENTORY_CHANGED';end if;
   insert into private.scoped_deletion_filters(job_id,table_name,predicate) values(j.id,o->>'table',o-'rows'-'table') on conflict do nothing;
  end loop;
  if jsonb_array_length(p_input->'records')>c.max_rows then raise exception 'DELETION_TOO_LARGE';end if;
  for r in select jsonb_array_elements(p_input->'records') loop
   tab:=r->>'table';key:=r->'key';
   if tab in ('public.athletes','public.athlete_profiles') and (r->>'action'<>'null' or tab<>'public.athletes' or r->'columns'<>'["organization_id"]'::jsonb)
     or tab='public.profiles' and (not j.personal or key->>'id'<>j.actor_id::text)
     or tab='auth.users' and (not j.personal or key->>'id'<>j.actor_id::text or r->>'action'<>'auth') then raise exception 'DELETION_PROTECTED_IDENTITY';end if;
   if tab<>'auth.users' then
    actual:=private.scoped_deletion_read(tab,jsonb_build_array(key),null,2);
    if jsonb_array_length(actual)<>1 or actual->0->>'__deletion_hash' is distinct from r->>'hash' then raise exception 'DELETION_INVENTORY_CHANGED';end if;
    if tab='private.wrestling_profiles' and (not j.personal or actual->0->>'user_id'<>j.actor_id::text or actual->0->>'athlete_profile_id' is not null) then raise exception 'DELETION_PROTECTED_IDENTITY';end if;
   end if;
   insert into private.scoped_deletion_rows(job_id,table_name,row_key,action,null_columns,source_hash)
    values(j.id,tab,key,r->>'action',array(select jsonb_array_elements_text(r->'columns')),r->>'hash');
  end loop;
  -- The provider-specific object manifest is validated and sealed separately.
  perform private.scoped_deletion_seal_media(j.id,p_input->'objects');
  update private.scoped_deletion_jobs set state='sealed',sealed_at=now() where id=j.id;
  return jsonb_build_object('id',j.id,'state','sealed');
 elsif p_op='revoke' and j.state in ('sealed','revoking') then
  update private.scoped_deletion_jobs set state='revoking' where id=j.id;
  if j.personal then delete from auth.sessions where user_id=j.actor_id;end if;
  return jsonb_build_object('personal',j.personal,'actorId',j.actor_id);
 elsif p_op='advance' then
  if j.state is distinct from p_input->>'from' or not ((j.state='revoking' and p_input->>'to'='media')
    or (j.state='media' and p_input->>'to'='records' and not exists(select 1 from private.scoped_deletion_objects where job_id=j.id and removed_at is null))
    or (j.state='auth' and p_input->>'to'='verifying')) then raise exception 'DELETION_INVALID_TRANSITION';end if;
  update private.scoped_deletion_jobs set state=p_input->>'to' where id=j.id;return '{}';
 elsif p_op='identity' and j.state='auth' then return jsonb_build_object('personal',j.personal,'actorId',j.actor_id);
 elsif p_op='erase_records' and j.state='records' then
  perform set_config('wm.scoped_deletion_job',j.id::text,true);perform set_config('wm.scoped_deletion_lease',p_lease::text,true);
  -- Null shared references first. Updates and deletes use exact sealed primary keys.
  for rowrecord in select * from private.scoped_deletion_rows where job_id=j.id and action='null' order by table_name,row_key::text loop
   select string_agg(format('%I=null',col),',') into assignments from unnest(rowrecord.null_columns) col;
   if assignments is null then raise exception 'DELETION_INVALID_NULL';end if;
   execute format('update %I.%I r set %s where private.scoped_deletion_matches(to_jsonb(r),$1)',split_part(rowrecord.table_name,'.',1),split_part(rowrecord.table_name,'.',2),assignments) using jsonb_build_array(rowrecord.row_key);
   update private.scoped_deletion_rows set applied=true where job_id=j.id and table_name=rowrecord.table_name and row_key=rowrecord.row_key;
  end loop;
  -- Nondeferrable RESTRICT FKs are handled by repeatedly deleting ready children.
  -- FK exceptions roll back each attempted statement, including its cascades.
  loop
   progressed:=false;
   for rowrecord in select * from private.scoped_deletion_rows where job_id=j.id and action='delete' and not applied
    order by case when table_name in ('private.wrestling_role_approvals','private.wrestling_role_review_log') then 0 else 1 end,table_name,row_key::text loop
    begin
     execute format('delete from %I.%I r where private.scoped_deletion_matches(to_jsonb(r),$1)',split_part(rowrecord.table_name,'.',1),split_part(rowrecord.table_name,'.',2)) using jsonb_build_array(rowrecord.row_key);
     update private.scoped_deletion_rows set applied=true where job_id=j.id and table_name=rowrecord.table_name and row_key=rowrecord.row_key;
     progressed:=true;
    exception when foreign_key_violation or restrict_violation then null;
    end;
   end loop;
   select count(*) into remaining from private.scoped_deletion_rows where job_id=j.id and action='delete' and not applied;
   exit when remaining=0;
   if not progressed then raise exception 'DELETION_DEPENDENCY_CHANGED';end if;
  end loop;
  update private.scoped_deletion_jobs set state='auth' where id=j.id;return '{}';
 elsif p_op='complete' and j.state='verifying' then
  if j.personal and exists(select 1 from auth.users where id=j.actor_id) then raise exception 'DELETION_IDENTITY_REMAINS';end if;
  for rowrecord in select * from private.scoped_deletion_rows where job_id=j.id and action<>'auth' loop
   actual:=private.scoped_deletion_read(rowrecord.table_name,jsonb_build_array(rowrecord.row_key),null,2);
   if rowrecord.action='delete' and actual<>'[]'::jsonb then raise exception 'DELETION_RECORD_REMAINS';end if;
   if rowrecord.action='null' then
    if jsonb_array_length(actual)<>1 then raise exception 'DELETION_PRESERVED_RECORD_MISSING';end if;
    for tab in select unnest(rowrecord.null_columns) loop
     if actual->0->>tab is not null then raise exception 'DELETION_REFERENCE_REMAINS';end if;
    end loop;
   end if;
  end loop;
  perform private.scoped_deletion_verify_media(j.id);
  -- Minimize completed receipts. They contain no user id, workspace ids or paths.
  delete from private.scoped_deletion_rows where job_id=j.id;
  delete from private.scoped_deletion_filters where job_id=j.id;
  delete from private.scoped_deletion_objects where job_id=j.id;
  update private.scoped_deletion_jobs set state='completed',completed_at=now(),actor_id=null,team_ids='{}',organization_ids='{}',error_code=null where id=j.id;
  return jsonb_build_object('id',j.id,'state','completed','personal',j.personal,'subjectHash',j.subject_hash);
 elsif p_op in ('media_inventory','objects','object_removed') then
  return private.scoped_deletion_media(p_op,j.id,p_input);
 end if;
 raise exception 'DELETION_INVALID_OPERATION';
end $$;
create function public.scoped_deletion_service(p_op text,p_job uuid,p_lease uuid,p_input jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$select private.scoped_deletion_service(p_op,p_job,p_lease,p_input)$$;

do $$declare r record;begin
 for r in select p.oid::regprocedure identity from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private') and p.proname like 'scoped_deletion_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',r.identity);
 end loop;
end $$;
grant execute on function public.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text),private.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text) to authenticated;
grant execute on function public.scoped_deletion_service(text,uuid,uuid,jsonb),private.scoped_deletion_service(text,uuid,uuid,jsonb) to service_role;

-- Reviewed file references. Uploader identity alone never authorizes file removal.
create table private.scoped_deletion_media_columns(table_name text not null,column_name text not null,buckets text[] not null,primary key(table_name,column_name));
create table private.scoped_deletion_object_tombstones(path_hash text primary key,created_at timestamptz not null default now());
alter table private.scoped_deletion_object_tombstones enable row level security;
revoke all on private.scoped_deletion_object_tombstones from public,anon,authenticated;
alter table private.scoped_deletion_media_columns enable row level security;
revoke all on private.scoped_deletion_media_columns from public,anon,authenticated;
insert into private.scoped_deletion_media_columns values
 ('public.profiles','photo_path',array['profile-photos','team-media','athlete-photos']),
 ('public.team_staff_profiles','photo_path',array['profile-photos','team-media','athlete-photos']),
 ('private.wrestling_profiles','photo_path',array['wrestling-profile-photos']),
 ('public.teams','banner_path',array['team-media']),
 ('public.communication_attachments','storage_path',array['communication-media']);

create function private.scoped_deletion_media_inventory(p_job uuid,p_records jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j private.scoped_deletion_jobs%rowtype;r jsonb;data jsonb;m record;obj record;col record;ref jsonb;
 path text;email text;result jsonb:='[]';ids uuid[]:='{}';n integer;
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
      and x->'key'=private.scoped_deletion_row_key(col.schema||'.'||col.name,ref)) then raise exception 'DELETION_SHARED_FILE_REFERENCE';end if;
   end loop;
  end loop;
 end loop;
 select coalesce(jsonb_agg(x order by x->>'id'),'[]') into result from jsonb_array_elements(result) x;
 return result;
end $$;
create function private.scoped_deletion_seal_media(p_job uuid,p_objects jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare records jsonb;actual jsonb;o jsonb;r record;
begin
 lock table storage.objects in share row exclusive mode;
 -- References can be introduced in any application table. Lock in stable order
 -- before the final cross-reference scan and install matching write freezes.
 for r in select n.nspname schema,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%' order by 1,2 loop
  execute format('lock table %I.%I in share row exclusive mode',r.schema,r.name);
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('table',table_name,'key',row_key,'action',action)),'[]') into records from private.scoped_deletion_rows where job_id=p_job;
 actual:=private.scoped_deletion_media_inventory(p_job,records);
 if actual is distinct from p_objects then raise exception 'DELETION_MEDIA_CHANGED';end if;
 for o in select jsonb_array_elements(actual) loop
  -- Keep a one-way path tombstone after the receipt is minimized. A delayed
  -- provider retry must never erase a replacement uploaded at the old address.
  insert into private.scoped_deletion_object_tombstones(path_hash)
   values(encode(sha256(convert_to(jsonb_build_array(o->>'bucket',o->>'path')::text,'UTF8')),'hex')) on conflict do nothing;
  insert into private.scoped_deletion_objects(job_id,object_id,bucket,object_key,version) values(p_job,(o->>'id')::uuid,o->>'bucket',o->>'path',o->>'version');
  insert into private.scoped_deletion_filters(job_id,table_name,predicate)
   select p_job,n.nspname||'.'||c.relname,jsonb_build_object('mention',jsonb_build_object('columns',jsonb_build_array('*'),'actorId',o->>'path'))
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%' on conflict do nothing;
 end loop;
 -- Copied email addresses are held to the same observed scope as UUID snapshots.
 insert into private.scoped_deletion_filters(job_id,table_name,predicate)
 select p_job,n.nspname||'.'||c.relname,jsonb_build_object('mention',jsonb_build_object('columns',jsonb_build_array('*'),'actorId',lower(u.email),'ignoreCase',true))
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join private.scoped_deletion_jobs j join auth.users u on u.id=j.actor_id
 where j.id=p_job and j.personal and n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%' on conflict do nothing;
end $$;
create function private.scoped_deletion_verify_media(p_job uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.scoped_deletion_objects d left join storage.objects o on o.bucket_id=d.bucket and o.name=d.object_key
  where d.job_id=p_job and (d.removed_at is null or o.id is not null)) then raise exception 'DELETION_MEDIA_REMAINS';end if;
 if exists(select 1 from private.scoped_deletion_jobs j join storage.objects o on o.owner=j.actor_id or o.owner_id=j.actor_id::text
  where j.id=p_job and j.personal) then raise exception 'DELETION_MEDIA_REMAINS';end if;
end $$;
create function private.scoped_deletion_media(p_op text,p_job uuid,p_input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;s text;
begin
 select state into s from private.scoped_deletion_jobs where id=p_job;
 if p_op='media_inventory' and s='planning' then return private.scoped_deletion_media_inventory(p_job,p_input->'records');end if;
 if s<>'media' then raise exception 'DELETION_INVALID_MEDIA_STATE';end if;
 if p_op='objects' then
  if exists(select 1 from private.scoped_deletion_objects d join storage.objects o on o.bucket_id=d.bucket and o.name=d.object_key
    where d.job_id=p_job and (o.id<>d.object_id or o.version is distinct from d.version)) then raise exception 'DELETION_MEDIA_CHANGED';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',object_id,'bucket',bucket,'path',object_key) order by object_id),'[]') into result
   from private.scoped_deletion_objects where job_id=p_job and removed_at is null;return result;
 elsif p_op='object_removed' then
  if not exists(select 1 from private.scoped_deletion_objects where job_id=p_job and object_id=(p_input->>'id')::uuid) then raise exception 'DELETION_INVALID_OBJECT';end if;
  if exists(select 1 from private.scoped_deletion_objects d join storage.objects o on o.bucket_id=d.bucket and o.name=d.object_key
   where d.job_id=p_job and d.object_id=(p_input->>'id')::uuid) then raise exception 'DELETION_MEDIA_REMAINS';end if;
  update private.scoped_deletion_objects set removed_at=now() where job_id=p_job and object_id=(p_input->>'id')::uuid;return '{}';
 end if;raise exception 'DELETION_INVALID_MEDIA_OPERATION';
end $$;
create function private.scoped_deletion_storage_freeze() returns trigger language plpgsql security definer set search_path='' as $$
declare d record;
begin
 if tg_op<>'DELETE' and exists(select 1 from private.scoped_deletion_object_tombstones
  where path_hash=encode(sha256(convert_to(jsonb_build_array(new.bucket_id,new.name)::text,'UTF8')),'hex')) then
  raise exception 'DELETION_OBJECT_ADDRESS_RETIRED';
 end if;
 for d in select x.* from private.scoped_deletion_objects x join private.scoped_deletion_jobs j on j.id=x.job_id
  where j.completed_at is null and ((tg_op<>'INSERT' and x.bucket=old.bucket_id and x.object_key=old.name)
   or (tg_op<>'DELETE' and x.bucket=new.bucket_id and x.object_key=new.name)) loop
  -- Only the storage service may remove the exact sealed version; it may never
  -- replace it. A provider-owned transaction has no application JWT role.
  if tg_op<>'DELETE' or old.id<>d.object_id or old.version is distinct from d.version
   or (current_setting('role',true)<>'service_role' and session_user not in ('supabase_storage_admin','postgres')) then
   raise exception 'DELETION_OBJECT_LOCKED';
  end if;
 end loop;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;

-- The global athlete identity survives organization closure. A detached identity
-- keeps its stable primary key, profile, guardian links and other-team rosters.
alter table public.athletes alter column organization_id drop not null;
create index scoped_deletion_blocked_identity on private.scoped_deletion_jobs(subject_hash) where personal and sealed_at is not null;
create function private.scoped_deletion_access_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is null or not exists(
  select 1 from private.scoped_deletion_jobs j
  where j.subject_hash=encode(sha256(convert_to(auth.uid()::text,'UTF8')),'hex')
   and j.personal and j.sealed_at is not null
 );
$$;
revoke all on function private.scoped_deletion_access_ok() from public,anon;
grant execute on function private.scoped_deletion_access_ok() to authenticated,service_role;
create or replace function public.enforce_team_login_request() returns void
language plpgsql set search_path='' as $$
begin
 if auth.uid() is null then return;end if;
 if not private.scoped_deletion_access_ok() then raise sqlstate '42501' using message='ACCOUNT_ACCESS_REVOKED';end if;
 perform private.enforce_team_login_request();
end $$;
do $$declare r record;begin
 for r in select n.nspname schema,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%' order by 1,2 loop
  execute format('create trigger scoped_deletion_freeze before insert or update or delete on %I.%I for each row execute function private.scoped_deletion_freeze()',r.schema,r.name);
 end loop;
end $$;
create trigger scoped_deletion_object_freeze before insert or update or delete on storage.objects for each row execute function private.scoped_deletion_storage_freeze();
create policy scoped_deletion_storage_access on storage.objects as restrictive for all to authenticated
 using(private.scoped_deletion_access_ok()) with check(private.scoped_deletion_access_ok());
-- Keep the capability disabled until the matching provider and phone acceptance
-- checks pass. Applying this migration never queues an erasure or opts users in.
create function private.scoped_deletion_capabilities() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; ready boolean;
begin
 result:=private.account_deletion_scope_preflight();
 if result->>'enabled' is distinct from 'true' then return result;end if;
 select enabled and catalog is not null and catalog_hash=private.scoped_deletion_schema_hash() into ready from private.scoped_deletion_config where id;
 return result||jsonb_build_object('deletion_enabled',coalesce(ready,false),'actions',jsonb_build_object('administrator',true,'personal',ready,'team',ready,'organization',ready,'all',ready));
end $$;
create or replace function public.account_deletion_scope_preflight() returns jsonb
language sql stable security invoker set search_path='' as $$select private.scoped_deletion_capabilities()$$;

-- Revoke default PUBLIC execution on every helper created after the router.
do $$declare r record;begin
 for r in select p.oid::regprocedure identity from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private') and p.proname like 'scoped_deletion_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',r.identity);
 end loop;
end $$;
grant execute on function public.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text),private.scoped_deletion_begin(text,uuid[],uuid[],text,uuid,text) to authenticated;
grant execute on function private.scoped_deletion_access_ok() to authenticated,service_role;
grant execute on function private.scoped_deletion_capabilities() to authenticated;
revoke all on function public.account_deletion_scope_preflight() from public,anon;
grant execute on function public.account_deletion_scope_preflight() to authenticated;
grant execute on function public.scoped_deletion_service(text,uuid,uuid,jsonb),private.scoped_deletion_service(text,uuid,uuid,jsonb) to service_role;

commit;
