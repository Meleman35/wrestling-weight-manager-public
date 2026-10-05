-- Provision only a restricted identity. No billing tables, customer data or
-- entitlement activation. The credential is generated inside PostgreSQL and
-- stored encrypted in the existing Vault; it is never returned by this script.
begin;
do $identity$
declare credential text;
begin
 if exists(select 1 from pg_roles where rolname in ('wm_billing_runtime','wm_billing_service'))
  or exists(select 1 from vault.secrets where name='wm-billing-database-url') then
  raise exception 'WM_BILLING_IDENTITY_ALREADY_EXISTS';
 end if;
 begin
  create role wm_billing_runtime nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  credential:=encode(extensions.gen_random_bytes(32),'hex');
  perform set_config('password_encryption','scram-sha-256',true);
  execute format('create role wm_billing_service login noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 8 password %L',credential);
  grant wm_billing_runtime to wm_billing_service with inherit false,set true;
  grant connect on database postgres to wm_billing_service;
  alter role wm_billing_service set statement_timeout='10s';
  alter role wm_billing_service set lock_timeout='5s';
  alter role wm_billing_service set idle_in_transaction_session_timeout='15s';
  alter role wm_billing_service set search_path=pg_catalog;
  perform vault.create_secret(
   'postgresql://wm_billing_service.vfocpoyexnjsjpxhhyqr:'||credential||'@aws-0-us-west-2.pooler.supabase.com:5432/postgres',
   'wm-billing-database-url',
   'Private billing connection. Copy only into Edge Function Secret BILLING_DATABASE_URL. Do not share in chat or source.');
 exception when others then
  -- Do not return a dynamic CREATE ROLE statement or provider error containing
  -- the generated credential. This subtransaction rolls back every change.
  raise exception 'WM_BILLING_IDENTITY_SETUP_FAILED';
 end;
end $identity$;
commit;
