-- DRAFT: intake only. Do not enable before the erasure/confirmation runbook is operational.
-- This migration neither disables nor deletes any account, membership or athlete record.
create table public.account_deletion_settings (
  id integer primary key check (id = 1),
  enabled boolean not null default false,
  completion_days integer not null default 30 check (completion_days between 1 and 30)
);
insert into public.account_deletion_settings(id) values (1);
alter table public.account_deletion_settings enable row level security;
revoke all on public.account_deletion_settings from public, anon, authenticated;
grant select on public.account_deletion_settings to authenticated;
grant all on public.account_deletion_settings to service_role;
create policy account_deletion_settings_read on public.account_deletion_settings
  for select to authenticated using (true);

create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  status text not null default 'requested' check (status in ('requested', 'processing', 'completed')),
  requested_at timestamptz not null default now(),
  deadline_at timestamptz not null,
  completed_at timestamptz,
  check ((status = 'completed') = (completed_at is not null))
);
create function private.account_deletion_deadline() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  select new.requested_at + make_interval(days => completion_days)
    into new.deadline_at from public.account_deletion_settings where id = 1;
  return new;
end;
$$;
revoke all on function private.account_deletion_deadline() from public, anon, authenticated;
create trigger account_deletion_deadline before insert on public.account_deletion_requests
  for each row execute function private.account_deletion_deadline();
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from public, anon, authenticated;
grant select on public.account_deletion_requests to authenticated;
grant insert (user_id) on public.account_deletion_requests to authenticated;
grant all on public.account_deletion_requests to service_role;
create policy account_deletion_own_read on public.account_deletion_requests
  for select to authenticated using ((select auth.uid()) = user_id);
create policy account_deletion_own_request on public.account_deletion_requests
  for insert to authenticated with check (
    (select auth.uid()) = user_id and exists (
      select 1 from public.account_deletion_settings where id = 1 and enabled
    )
  );

create function public.account_deletion_request(p_action text default 'status', p_confirmation text default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  u uuid := auth.uid();
  config public.account_deletion_settings%rowtype;
  receipt public.account_deletion_requests%rowtype;
begin
  if u is null then raise exception 'Sign in to your account first.' using errcode = '42501'; end if;
  if p_action not in ('status', 'request') or p_action is null then
    raise exception 'Unsupported account deletion action.' using errcode = '22023';
  end if;
  select * into config from public.account_deletion_settings where id = 1;
  if not found then raise exception 'Account deletion configuration is unavailable.'; end if;
  if p_action = 'request' then
    if p_confirmation is distinct from 'DELETE' then
      raise exception 'Confirm that you want to delete your account.' using errcode = '22023';
    end if;
    -- Return a previous durable receipt even if intake was subsequently paused.
    select * into receipt from public.account_deletion_requests where user_id = u;
    if not found then
      if not config.enabled then raise exception 'Account deletion requests are not enabled yet.' using errcode = '55000'; end if;
      insert into public.account_deletion_requests(user_id) values (u) on conflict (user_id) do nothing;
    end if;
  end if;
  select * into receipt from public.account_deletion_requests where user_id = u;
  return jsonb_build_object(
    'enabled', config.enabled,
    'completion_days', config.completion_days,
    'request', case when receipt.id is null then null else jsonb_build_object(
      'id', receipt.id, 'status', receipt.status,
      'requested_at', receipt.requested_at, 'deadline_at', receipt.deadline_at, 'completed_at', receipt.completed_at
    ) end
  );
end;
$$;
revoke all on function public.account_deletion_request(text, text) from public, anon;
grant execute on function public.account_deletion_request(text, text) to authenticated;
comment on table public.account_deletion_requests is
  'Deletion intake only. No automatic erasure. Enable only after tested fulfillment, legal retention decisions and completion notices are operational.';
