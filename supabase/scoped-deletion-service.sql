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
 if p_op='due' then
  if p_input->>'scheduler_hash' is null or p_input->>'scheduler_hash' is distinct from (select scheduler_hash from private.scoped_deletion_config where id) then raise sqlstate '42501' using message='DELETION_SCHEDULER_ONLY';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'receiptHash',receipt_hash)),'[]') into actual from (
   select id,receipt_hash from private.scoped_deletion_jobs where state not in ('completed','blocked') and (lease_until is null or lease_until<=now()) and (retry_after is null or retry_after<=now()) order by created_at limit 3
  ) q;return actual;
 end if;
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
