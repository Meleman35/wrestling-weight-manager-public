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
