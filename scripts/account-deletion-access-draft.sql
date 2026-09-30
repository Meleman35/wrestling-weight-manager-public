-- UNWIRED PROTOTYPE: isolated regression databases only. This is NOT a migration.
-- Requires the two existing deletion draft migrations. No production hook, policy,
-- feature switch, Auth row or job is changed by this file. See docs/account-deletion-access.md.
-- The gateway MUST verify JWT signature/issuer/audience before installing request claims.

-- A deliberate fixture marker prevents accidental application by a migration runner.
-- This marker is an operational safeguard, not an authorization boundary.
do $$ begin
  if current_setting('wm.deletion_access_fixture',true) is distinct from 'isolated-test' then
    raise exception 'Unwired prototype: isolated regression database only.' using errcode='55000';
  end if;
end $$;

create function private.account_deletion_access_allowed()
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare claims jsonb; subject uuid; claim_subject uuid; sid uuid;
begin
  -- This helper is intentionally argument-free: it answers only for the current caller.
  -- SECURITY DEFINER is needed to read service-only job state and private Auth rows.
  -- It does not return identity, job, session or other-account data and performs no writes.
  begin
    claims := auth.jwt();
    subject := auth.uid();
    claim_subject := (claims->>'sub')::uuid;
    sid := (claims->>'session_id')::uuid;
  exception when invalid_text_representation then return false;
  end;
  if subject is null or claim_subject is distinct from subject or sid is null
      or claims->>'role' is distinct from 'authenticated' then return false; end if;
  if jsonb_typeof(claims->'exp') is distinct from 'number'
      or (claims->>'exp') !~ '^[0-9]{1,12}$' then return false; end if;
  if (claims->>'exp')::numeric <= extract(epoch from statement_timestamp()) then return false; end if;

  -- phase 0 is unapproved review, not a revocation decision. Once review advances,
  -- denial survives retry, blocked jobs, lease loss and a paused fulfillment switch.
  -- Completion removes the job's subject linkage; the missing Auth/session checks
  -- below continue rejecting old tokens. No additional identity tombstone is created.
  if exists(select 1 from private.account_deletion_jobs j
      where j.subject_id=subject and j.phase>=1) then return false; end if;
  return exists(select 1 from auth.users u join auth.sessions s on s.user_id=u.id
    where u.id=subject and s.id=sid and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=statement_timestamp())
      and (s.not_after is null or s.not_after>statement_timestamp()));
end $$;
revoke all on function private.account_deletion_access_allowed() from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.account_deletion_access_allowed() to authenticated;

create function private.require_account_deletion_access()
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if private.account_deletion_access_allowed() is not true then
    raise exception 'Account access is unavailable.' using errcode='42501';
  end if;
end $$;
revoke all on function private.require_account_deletion_access() from public,anon,authenticated;
grant execute on function private.require_account_deletion_access() to authenticated;

create function public.account_deletion_pre_request()
returns void language plpgsql security invoker set search_path = '' as $$
begin
  -- Compose with, never overwrite, the existing team-device/recorder request guard.
  perform public.enforce_team_login_request();
  if current_user='authenticated' or auth.uid() is not null then
    perform private.require_account_deletion_access();
  end if;
  -- Anonymous/service callers retain their existing endpoint authorization.
  -- This is NOT evidence that their token-based or privileged endpoints are reviewed.
end $$;
revoke all on function public.account_deletion_pre_request() from public,anon,authenticated;
grant execute on function public.account_deletion_pre_request() to anon,authenticated,service_role;

comment on function private.account_deletion_access_allowed() is
  'Unwired deletion prototype: current verified caller only, read-only private Auth/job check. Does not establish global revocation.';
-- Deliberately no ALTER ROLE, pre-request configuration, CREATE POLICY, Auth mutation,
-- worker invocation, broad function replacement, activation flag or deployment command.
