begin;
alter table private.scoped_deletion_config add column worker_url text;
create function private.scoped_deletion_tick() returns void
language plpgsql security definer set search_path='' as $$
declare endpoint text; token text;
begin
 if not exists(select 1 from private.scoped_deletion_jobs where state not in ('completed','blocked')
  and (lease_until is null or lease_until<=now()) and (retry_after is null or retry_after<=now())) then return;end if;
 select worker_url into endpoint from private.scoped_deletion_config where id;
 if endpoint is null or endpoint!~'^https://[a-z0-9]+[.]supabase[.]co/functions/v1/scoped-deletion$' then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='scoped-deletion-scheduler';
 if token is null then return;end if;
 perform net.http_post(url:=endpoint,headers:='{"Content-Type":"application/json"}'::jsonb,
  body:=jsonb_build_object('action','schedule','receipt',token),timeout_milliseconds:=10000);
end $$;
revoke all on function private.scoped_deletion_tick() from public,anon,authenticated,service_role;
do $$declare token text;begin
 if not exists(select 1 from vault.secrets where name='scoped-deletion-scheduler') then
  token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
  perform vault.create_secret(token,'scoped-deletion-scheduler','Server-only scoped deletion retry worker');
 else select decrypted_secret into token from vault.decrypted_secrets where name='scoped-deletion-scheduler';end if;
 update private.scoped_deletion_config set scheduler_hash=encode(sha256(convert_to(token,'UTF8')),'hex') where id;
 if not exists(select 1 from cron.job where jobname='scoped-deletion-worker') then
  perform cron.schedule('scoped-deletion-worker','* * * * *','select private.scoped_deletion_tick()');
 end if;
end $$;
-- A deployment-specific worker URL is configured separately. New user requests
-- remain disabled; once accepted, existing jobs can finish with the browser closed.
commit;
