-- Current production function definitions inspected read-only October 5 UTC.
-- Structure only; no customer records or credentials. Used by migration acceptance.
-- private.athlete_merge_request(text,jsonb)
CREATE OR REPLACE FUNCTION private.athlete_merge_request(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid=auth.uid();t uuid=(p_data->>'team_id')::uuid;s uuid=(p_data->>'duplicate_id')::uuid;k uuid=(p_data->>'keep_id')::uuid;
 a public.athletes%rowtype;b public.athletes%rowtype;r record;plan jsonb;rows jsonb;aj jsonb;bj jsonb;merged jsonb;cols text;sp uuid;kp uuid;receipt jsonb;contact_resolution text=p_data->>'contact_resolution';
begin
 if u is null or not exists(select 1 from auth.users where id=u and deleted_at is null and email_confirmed_at is not null and (banned_until is null or banned_until<=now())) or exists(select 1 from private.team_logins where user_id=u) or not coalesce(public.is_team_admin(t),false) or coalesce((p_data->>'view_as_parent')::boolean,false) then raise sqlstate '42501' using message='A personal team-administrator account is required';end if;
 if p_action='candidates' then
  select coalesce(jsonb_agg(jsonb_build_object('id',candidate.id,'name',candidate.first_name||' '||candidate.last_name,'created_at',candidate.created_at,'has_login',exists(select 1 from public.team_memberships m where m.athlete_id=candidate.id and m.role='athlete' and m.active)) order by candidate.last_name,candidate.first_name,candidate.created_at),'[]') into rows
  from public.athletes candidate where exists(select 1 from public.roster_memberships rm join public.seasons ss on ss.id=rm.season_id where rm.athlete_id=candidate.id and ss.team_id=t);return rows;
 end if;
 if contact_resolution is not null and contact_resolution<>'keep' then raise exception 'Choose the kept profile contact details or review the profiles again';end if;
 if p_action not in ('preview','merge') then raise exception 'Unknown merge action';end if;
 if s is null or k is null or s=k then raise exception 'Choose two different athletes';end if;
 -- A retry after connection loss returns the committed receipt, never merges twice.
 select metadata into receipt from public.audit_log where actor_user_id=u and action='merge_duplicate_athlete' and entity_id=k and metadata->>'duplicate_id'=s::text and metadata->>'team_id'=t::text order by id desc limit 1;
 if receipt is not null and p_action='merge' then return receipt;end if;
 if private.scoped_deletion_schema_hash()<>'c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8' then raise exception 'Athlete merge needs a schema compatibility review before it can continue';end if;
 if (select count(*) from public.athletes candidate where id in(s,k) and exists(select 1 from public.roster_memberships rm join public.seasons ss on ss.id=rm.season_id where rm.athlete_id=candidate.id and ss.team_id=t))<>2 then raise sqlstate '42501' using message='Both athletes must belong to the selected team';end if;
 if p_action='merge' then
  if p_data->>'confirmation' is distinct from 'merge' or p_data->>'version' is null then raise exception 'Type merge after reviewing both profiles';end if;
  perform pg_advisory_xact_lock(hashtext('athlete_merge'));
  perform id from public.athletes where id in(s,k) order by id for update;
  perform id from public.athlete_profiles where id in(select profile_id from public.athletes where id in(s,k)) order by id for update;
  perform id from private.wrestling_profiles where athlete_profile_id in(select profile_id from public.athletes where id in(s,k)) order by id for update;
  for r in select * from private.athlete_merge_refs() loop execute format('select 1 from %I.%I where %I in($1,$2) for update',r.ns,r.tbl,r.col) using s,k;end loop;
  for r in select * from private.athlete_merge_json_refs() loop execute format('lock table %I.%I in share row exclusive mode',r.ns,r.tbl);end loop;
 end if;
 plan:=private.athlete_merge_plan(s,k,contact_resolution);
 if p_action='preview' then return plan;end if;
 if jsonb_array_length(plan->'blockers')>0 then raise exception '%',plan->'blockers'->>0;end if;
 if plan->>'version' is distinct from p_data->>'version' then raise exception 'Records changed. Review the merge again before confirming';end if;
 select * into a from public.athletes where id=s;select * into b from public.athletes where id=k;
 -- Keep the chosen athlete name. Only absent, non-conflicting personal fields fill in.
 update public.athletes set email=case when contact_resolution='keep' and (plan->'contact_conflicts')?'email' then b.email else coalesce(nullif(b.email,''),a.email) end,phone=case when contact_resolution='keep' and (plan->'contact_conflicts')?'phone' then b.phone else coalesce(nullif(b.phone,''),a.phone) end,birth_date=coalesce(b.birth_date,a.birth_date),graduation_year=coalesce(b.graduation_year,a.graduation_year),photo_path=coalesce(b.photo_path,a.photo_path) where id=k;
 for r in select unnest(array['athlete_private_identity','athlete_private_contact','athlete_profile_details','athlete_medical_private']) as tbl loop
  execute format('select to_jsonb(x) from public.%I x where athlete_id=$1',r.tbl) into aj using k;
  execute format('select to_jsonb(x) from public.%I x where athlete_id=$1',r.tbl) into bj using s;
  if aj is not null and bj is not null then
   merged:=case when r.tbl='athlete_private_contact' then private.athlete_merge_contact_values(aj,bj,contact_resolution) else private.athlete_merge_values(aj,bj) end;if merged is null then raise exception 'Profile values changed. Review again';end if;
   select string_agg(format('%1$I = v.%1$I',attname),',') into cols from pg_attribute where attrelid=format('public.%I',r.tbl)::regclass and attnum>0 and not attisdropped and attname not in ('athlete_id','updated_at','updated_by');
   execute format('update public.%1$I x set %2$s from jsonb_populate_record(null::public.%1$I,$1) v where x.athlete_id=$2',r.tbl,cols) using merged,k;
   execute format('delete from public.%I where athlete_id=$1',r.tbl) using s;
  end if;
 end loop;
 -- A season keeps its selected primary roster settings; all event history moves below.
 delete from public.roster_memberships src using public.roster_memberships dst where src.athlete_id=s and dst.athlete_id=k and src.season_id=dst.season_id;
 for r in select * from private.athlete_merge_refs() loop execute format('update %I.%I set %I=$1 where %I=$2',r.ns,r.tbl,r.col,r.col) using k,s;end loop;
 for r in select * from private.athlete_merge_json_refs() loop execute format('update %1$I.%2$I set %3$I=private.athlete_merge_json(%3$I,$1,$2)%4$s where %3$I::text like $3 and %3$I is distinct from private.athlete_merge_json(%3$I,$1,$2)',r.ns,r.tbl,r.col,case when r.tbl in ('match_books','video_scored_matches') then ',revision=revision+1' else '' end) using s,k,'%'||s::text||'%';end loop;
 select id into sp from private.wrestling_profiles where athlete_profile_id=a.profile_id;select id into kp from private.wrestling_profiles where athlete_profile_id=b.profile_id;
 if a.profile_id<>b.profile_id then
  if sp is not null and kp is null then update private.wrestling_profiles set athlete_profile_id=b.profile_id where id=sp;
  elsif sp is not null then delete from private.wrestling_profiles where id=sp;end if;
 end if;
 delete from public.athletes where id=s;
 if a.profile_id<>b.profile_id then delete from public.athlete_profiles where id=a.profile_id and not exists(select 1 from public.athletes where profile_id=a.profile_id);end if;
 receipt:=jsonb_build_object('status','completed','team_id',t,'keep_id',k,'duplicate_id',s,'completed_at',now(),'contact_resolution',contact_resolution,'contact_conflicts',plan->'contact_conflicts','records',plan->'records');
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(u,'merge_duplicate_athlete','athlete',k,receipt);
 return receipt;
exception when unique_violation or check_violation or foreign_key_violation then raise exception 'These profiles have conflicting saved records. Nothing was merged. Review their records and try again';
end $function$
;

-- private.scoped_deletion_media_inventory(uuid,jsonb)
CREATE OR REPLACE FUNCTION private.scoped_deletion_media_inventory(p_job uuid, p_records jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;

-- private.scoped_deletion_read(text,jsonb,jsonb,integer)
CREATE OR REPLACE FUNCTION private.scoped_deletion_read(p_table text, p_predicates jsonb, p_mention jsonb, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;

-- private.scoped_deletion_schema_hash()
CREATE OR REPLACE FUNCTION private.scoped_deletion_schema_hash()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.scoped_deletion_seal_media(uuid,jsonb)
CREATE OR REPLACE FUNCTION private.scoped_deletion_seal_media(p_job uuid, p_objects jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;

-- private.scoped_deletion_service(text,uuid,uuid,jsonb)
CREATE OR REPLACE FUNCTION private.scoped_deletion_service(p_op text, p_job uuid, p_lease uuid, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;

