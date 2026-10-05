-- Server-only notification readiness, scheduler authentication and operational
-- cleanup. No user purchase route is activated. No new customer-data tables.
begin;
do $$begin
 if private.scoped_deletion_schema_hash()<>'22b2b942416753db8212d4f2bb4550da01713e687376eb2becaa8f6dfb22f350'
  or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
  or encode(sha256(convert_to(pg_get_functiondef('wm_billing.prepare_deletion(uuid,uuid)'::regprocedure),'UTF8')),'hex')<>'fc85e265bb8a7d3469536f6aa17b86354d2c23fe1629851392e67110976cc291'
 then raise exception 'BILLING_NOTIFICATION_REVIEW_REQUIRED';end if;
end $$;

create function wm_billing.notification_deployment_ready() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.scoped_deletion_config where id and enabled
  and catalog_hash='22b2b942416753db8212d4f2bb4550da01713e687376eb2becaa8f6dfb22f350'
  and catalog_hash=private.scoped_deletion_schema_hash())
 and exists(select 1 from private.scoped_deletion_acceptance_runs where state='cleaned'
  and result @> '{"fixtures_cleaned":true,"provider_auth":true,"provider_files":true,"old_jwt_rejected":true,"billing_actor_absent":true,"billing_inbox_absent":true,"billing_deliveries_absent":true,"billing_other_preserved":true}')
 and (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='wm_billing' and c.relkind='r' and c.relrowsecurity)=7
 and (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='wm_billing' and t.tgname='scoped_deletion_freeze' and not t.tgisinternal)=7
 and encode(sha256(convert_to(pg_get_functiondef('wm_billing.prepare_deletion(uuid,uuid)'::regprocedure),'UTF8')),'hex')='fc85e265bb8a7d3469536f6aa17b86354d2c23fe1629851392e67110976cc291'
$$;

create function wm_billing.authorize_notification_worker(p_token text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare expected text;
begin
 if p_token is null or p_token!~'^[a-f0-9]{64}$' then return false;end if;
 select encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex') into expected
  from vault.decrypted_secrets where name='wm-billing-notification-worker';
 return coalesce(expected=encode(sha256(convert_to(p_token,'UTF8')),'hex'),false);
end $$;

-- Operational inbox entries are not the subscription ledger. Keep completed
-- entries 30 days from receipt; remove equally old unbound entries only when no
-- intent or subscription can own them. Never discard a bound pending update.
create function wm_billing.purge_notification_operations() returns jsonb
language plpgsql security definer set search_path='' as $$
declare inbox_removed integer; remainders_removed integer;
begin
 -- Deletion has priority. Its freeze triggers remain a race-condition backstop.
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('completed','cancelled')) then
  return '{"deferred":true,"inbox":0,"remainders":0}';end if;
 with expired as (
  select n.environment,n.notification_id from wm_billing.notification_inbox n
   where n.received_at<now()-interval '30 days'
    and (n.state='completed' or (n.state='pending'
     and not exists(select 1 from wm_billing.intents i where i.token=n.token)
     and not exists(select 1 from wm_billing.subscriptions s where s.token=n.token or (s.environment=n.environment and s.original_id=n.original_id))))
   order by n.received_at,n.notification_id for update skip locked limit 1000)
 delete from wm_billing.notification_inbox n using expired e where n.environment=e.environment and n.notification_id=e.notification_id;
 get diagnostics inbox_removed=row_count;
 remainders_removed:=wm_billing.purge_paid_remainders();
 return jsonb_build_object('deferred',false,'inbox',inbox_removed,'remainders',remainders_removed);
end $$;
revoke all on function wm_billing.notification_deployment_ready(),wm_billing.authorize_notification_worker(text),wm_billing.purge_notification_operations() from public,anon,authenticated;
grant execute on function wm_billing.notification_deployment_ready(),wm_billing.authorize_notification_worker(text),wm_billing.purge_notification_operations() to wm_billing_runtime;

create function private.billing_notification_tick(p_probe boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare token text; env text; request_id bigint; requests jsonb:='[]'; cleaned jsonb;
begin
 if not wm_billing.notification_deployment_ready() then return '{"ready":false}';end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='wm-billing-notification-worker';
 if token is null or token!~'^[a-f0-9]{64}$' then return '{"ready":false}';end if;
 cleaned:=wm_billing.purge_notification_operations();
 foreach env in array array['Production','Sandbox'] loop
  if p_probe or exists(select 1 from wm_billing.notification_inbox where environment=env
   and ((state='pending' and next_attempt_at<=clock_timestamp()) or (state='processing' and lease_until<=clock_timestamp()))) then
   request_id:=net.http_post(
    url:='https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-apple-notifications/'||lower(env)||'/reconcile',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||token),
    body:='{}',timeout_milliseconds:=45000);
   requests:=requests||jsonb_build_array(jsonb_build_object('environment',env,'request_id',request_id));
  end if;
 end loop;
 return jsonb_build_object('ready',true,'requests',requests,'cleanup',cleaned);
end $$;
revoke all on function private.billing_notification_tick(boolean) from public,anon,authenticated,service_role,wm_billing_runtime;
do $$declare job bigint;begin
 if not exists(select 1 from vault.secrets where name='wm-billing-notification-worker') then
  perform vault.create_secret(replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),
   'wm-billing-notification-worker','Private billing notification scheduler; never exposed to app clients');
 end if;
 if exists(select 1 from cron.job where jobname='wm-billing-notifications') then raise exception 'BILLING_SCHEDULER_ALREADY_EXISTS';end if;
 job:=cron.schedule('wm-billing-notifications','* * * * *','select private.billing_notification_tick()');
 -- Enable only after the deployed endpoint passes authenticated idle probes.
 perform cron.alter_job(job,active:=false);
end $$;
commit;
