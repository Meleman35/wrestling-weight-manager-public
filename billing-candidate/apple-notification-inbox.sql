-- Private DRAFT only. Financial retention/deletion catalog must be integrated
-- before deployment. This inbox schedules reconciliation; it grants no access.
create table wm_billing.notification_inbox (
 environment text not null check(environment in ('Sandbox','Production')),
 notification_id uuid not null,
 original_id text not null check(original_id ~ '^[0-9]{1,40}$'),
 token uuid not null,
 evidence jsonb not null check(jsonb_typeof(evidence)='object'),
 received_at timestamptz not null default clock_timestamp(),
 state text not null default 'pending' check(state in ('pending','processing','completed')),
 lease_token uuid, lease_until timestamptz,
 next_attempt_at timestamptz not null default clock_timestamp(), attempts integer not null default 0,
 primary key(environment,notification_id)
);
create index billing_notification_pending on wm_billing.notification_inbox(received_at)
 where state='pending';
alter table wm_billing.notification_inbox enable row level security;
revoke all on wm_billing.notification_inbox from public,anon,authenticated;
grant select,insert,update on wm_billing.notification_inbox to wm_billing_runtime;
create policy backend on wm_billing.notification_inbox to wm_billing_runtime using(true) with check(true);

-- Return only current eligibility; the runtime never receives raw Auth rows.
create function wm_billing.notification_owner_available(p_user uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare owner_id uuid;
begin
 select u.id into owner_id from auth.users u where u.id=p_user
  and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp())
  and private.board_personal(u.id) and not exists(select 1 from private.scoped_deletion_jobs j
   where (j.actor_id=u.id and j.state not in ('cancelled','completed')) or
    (j.personal and j.sealed_at is not null and j.subject_hash=encode(sha256(convert_to(u.id::text,'UTF8')),'hex')))
  for share;
 return owner_id is not null;
end $$;
revoke all on function wm_billing.notification_owner_available(uuid) from public,anon,authenticated;
grant execute on function wm_billing.notification_owner_available(uuid) to wm_billing_runtime;
