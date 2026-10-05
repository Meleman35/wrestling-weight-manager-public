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
