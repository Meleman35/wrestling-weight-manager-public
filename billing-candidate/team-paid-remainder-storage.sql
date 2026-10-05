-- Isolated candidate. Apply after billing-storage-candidate.sql and the inbox.
-- The deployment gate must enroll this schema and the deletion hook before use.
create table wm_billing.team_paid_remainders (
 binding_hash text primary key check(binding_hash ~ '^[a-f0-9]{64}$'),
 team_id uuid not null references public.teams(id) on delete cascade,
 environment text not null check(environment in ('Sandbox','Production')),
 plan text not null check(plan in ('team_pro_year','team_pro_month')),
 paid_through bigint not null check(paid_through between 0 and 9007199254740991),
 revoked_at bigint check(revoked_at between 0 and 9007199254740991),
 snapshot_signed_at bigint not null check(snapshot_signed_at between 0 and 9007199254740991)
);
create index billing_remainder_team on wm_billing.team_paid_remainders(team_id);
create index billing_remainder_expiry on wm_billing.team_paid_remainders(paid_through);
alter table wm_billing.team_paid_remainders enable row level security;
revoke all on wm_billing.team_paid_remainders from public,anon,authenticated;
grant select,update on wm_billing.team_paid_remainders to wm_billing_runtime;
create policy backend on wm_billing.team_paid_remainders to wm_billing_runtime using(true) with check(true);
create function wm_billing.remainder_update_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.binding_hash<>old.binding_hash or new.team_id<>old.team_id or new.environment<>old.environment or new.plan<>old.plan
  or new.paid_through>old.paid_through or new.snapshot_signed_at<old.snapshot_signed_at
  or (old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at) then raise exception 'BILLING_REMAINDER_IMMUTABLE';end if;
 return new;
end $$;
create trigger billing_remainder_update before update on wm_billing.team_paid_remainders
 for each row execute function wm_billing.remainder_update_guard();

-- A private, pseudonymous refund lookup, not an anonymous record. The random
-- app-account token prevents guessing from Apple's numeric transaction ID alone.
-- Neither raw identifier nor a purchaser/athlete ID is retained in the grant.
create function wm_billing.remainder_binding(p_environment text,p_original text,p_token uuid)
returns text language sql immutable strict set search_path='' as $$
 select encode(sha256(convert_to('wm-remainder-v1|'||p_environment||'|'||p_original||'|'||p_token::text,'UTF8')),'hex')
$$;

-- Mirrors the inspected public.is_team_admin permissions, with live identity
-- and deletion checks. This helper is backend-only and never trusts JWT metadata.
create function wm_billing.remaining_team_admin(p_team uuid,p_excluded uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.teams t where t.id=p_team
  and not exists(select 1 from private.scoped_deletion_jobs j where j.state not in ('cancelled','completed')
   and (t.id=any(j.team_ids) or t.organization_id=any(j.organization_ids)))
  and exists(select 1 from auth.users u where u.id is distinct from p_excluded
   and u.confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now()) and private.board_personal(u.id)
   and not private.board_minor(u.id)
   and not exists(select 1 from private.scoped_deletion_jobs j
    where (j.actor_id=u.id and j.state not in ('cancelled','completed')) or
     (j.personal and j.sealed_at is not null and j.subject_hash=encode(sha256(convert_to(u.id::text,'UTF8')),'hex')))
   and (exists(select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=u.id and m.active
    and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false))))
    or exists(select 1 from public.organization_memberships o where o.organization_id=t.organization_id
     and o.user_id=u.id and o.role='organization_admin'))))
$$;

-- Runs within the leased deletion transaction, before Auth can be erased.
-- Failure rolls the entire record-deletion transaction back. No runtime/client
-- role can invoke it or insert arbitrary preserved grants.
create function wm_billing.finalize_deletion(p_job uuid,p_lease uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j private.scoped_deletion_jobs%rowtype; notice record; current_ms bigint:=floor(extract(epoch from clock_timestamp())*1000);
begin
 select * into j from private.scoped_deletion_jobs where id=p_job and state='records'
  and sealed_at is not null and lease_token=p_lease and lease_until>clock_timestamp() for update;
 if not found or current_setting('role',true) is distinct from 'service_role' then raise exception 'BILLING_DELETION_LEASE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended(j.actor_id::text,91347));
 if j.personal then
  insert into wm_billing.team_paid_remainders(binding_hash,team_id,environment,plan,paid_through,revoked_at,snapshot_signed_at)
   select wm_billing.remainder_binding(s.environment,s.original_id,s.token),s.team_id,s.environment,s.snapshot->>'plan',
    case when s.snapshot->>'status'='4' then (s.snapshot->>'graceExpiresAt')::bigint else (s.snapshot->>'expiresAt')::bigint end,
    null,(s.snapshot->>'snapshotSignedAt')::bigint
   from wm_billing.subscriptions s where s.user_id=j.actor_id and s.scope='team'
    and s.snapshot->>'revokedAt' is null and s.snapshot->>'status' in ('1','4')
    and (s.snapshot->>'snapshotSignedAt')::bigint<=current_ms+60000
    and case when s.snapshot->>'status'='4' then (s.snapshot->>'graceExpiresAt')::bigint else (s.snapshot->>'expiresAt')::bigint end>current_ms
    and wm_billing.remaining_team_admin(s.team_id,j.actor_id)
   on conflict(binding_hash) do nothing;
  -- A refund may already be acknowledged in the inbox when deletion starts.
  -- Apply those verified canonical observations before erasing the inbox, so
  -- deletion cannot lose an accepted refund while its worker is frozen.
  for notice in select n.evidence e,n.environment,n.original_id,n.token,r.binding_hash from wm_billing.notification_inbox n
   join wm_billing.intents i on i.token=n.token and i.user_id=j.actor_id
   join wm_billing.team_paid_remainders r on r.binding_hash=wm_billing.remainder_binding(n.environment,n.original_id,n.token)
   order by (n.evidence->>'snapshotSignedAt')::bigint,n.notification_id loop
   if not coalesce(notice.e->>'bundleID'='com.damonmele.wrestlingmanager'
    and notice.e->>'environment'=notice.environment and notice.e->>'originalTransactionID'=notice.original_id
    and (notice.e->>'appAccountToken')::uuid=notice.token
    and notice.e->>'productID' in ('com.damonmele.wrestlingmanager.teampro.annual','com.damonmele.wrestlingmanager.teampro.monthly')
    and notice.e->>'status' in ('1','2','3','4','5')
    and notice.e->>'snapshotSignedAt' ~ '^[0-9]{1,16}$' and (notice.e->>'snapshotSignedAt')::bigint<=current_ms+60000
    and notice.e->>'expiresAt' ~ '^[0-9]{1,16}$' and (notice.e->>'expiresAt')::bigint<=9007199254740991
    and (notice.e->>'status'<>'4' or (notice.e->>'graceExpiresAt' ~ '^[0-9]{1,16}$' and (notice.e->>'graceExpiresAt')::bigint<=9007199254740991))
    and (notice.e->>'revokedAt' is null or (notice.e->>'revokedAt' ~ '^[0-9]{1,16}$' and (notice.e->>'revokedAt')::bigint<=9007199254740991)),false) then
    raise exception 'BILLING_REMAINDER_EVIDENCE_INVALID';
   end if;
   update wm_billing.team_paid_remainders r set
    paid_through=least(r.paid_through,case when notice.e->>'status'='4' then (notice.e->>'graceExpiresAt')::bigint
     when notice.e->>'status' in ('2','3') then least(current_ms,(notice.e->>'expiresAt')::bigint)
     else (notice.e->>'expiresAt')::bigint end),
    revoked_at=coalesce(r.revoked_at,(notice.e->>'revokedAt')::bigint,case when notice.e->>'status'='5' then current_ms end),
    snapshot_signed_at=(notice.e->>'snapshotSignedAt')::bigint
    where r.binding_hash=notice.binding_hash and (notice.e->>'snapshotSignedAt')::bigint>=r.snapshot_signed_at;
  end loop;
 end if;
 -- Include unpaid intents and pre-delivery notifications, not only purchases.
 delete from wm_billing.notification_inbox n using wm_billing.intents i
  where n.token=i.token and ((j.personal and i.user_id=j.actor_id) or i.team_id=any(j.team_ids));
 delete from wm_billing.notification_inbox n using wm_billing.subscriptions s
  where n.environment=s.environment and n.original_id=s.original_id
   and ((j.personal and s.user_id=j.actor_id) or s.team_id=any(j.team_ids));
 delete from wm_billing.deliveries d using wm_billing.subscriptions s
  where d.environment=s.environment and d.original_id=s.original_id
   and ((j.personal and s.user_id=j.actor_id) or s.team_id=any(j.team_ids));
 delete from wm_billing.subscriptions s where (j.personal and s.user_id=j.actor_id) or s.team_id=any(j.team_ids);
 delete from wm_billing.intents i where (j.personal and i.user_id=j.actor_id) or i.team_id=any(j.team_ids);
 delete from wm_billing.team_bindings b where (j.personal and b.user_id=j.actor_id) or b.team_id=any(j.team_ids);
 delete from wm_billing.family_coverage c where j.personal and c.user_id=j.actor_id;
 delete from wm_billing.team_paid_remainders r where r.team_id=any(j.team_ids);
end $$;

-- Candidate hook: the existing worker changes records -> auth only after all
-- scoped record operations succeed. This hook joins that same transaction.
create function wm_billing.deletion_transition() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.state='records' and new.state='auth' then
  perform wm_billing.finalize_deletion(old.id,old.lease_token);
 end if;
 return new;
end $$;
create trigger billing_deletion_transition before update of state on private.scoped_deletion_jobs
 for each row execute function wm_billing.deletion_transition();

-- Expiry access is denied even if the scheduler is delayed. Bounded cleanup
-- removes private lookup records; team deletion is also covered by the FK.
create function wm_billing.purge_paid_remainders() returns integer
language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
 with expired as (select binding_hash from wm_billing.team_paid_remainders
  where paid_through<=floor(extract(epoch from clock_timestamp())*1000)
  order by paid_through for update skip locked limit 1000)
 delete from wm_billing.team_paid_remainders r using expired e where r.binding_hash=e.binding_hash;
 get diagnostics removed=row_count;return removed;
end $$;
revoke all on function wm_billing.remainder_binding(text,text,uuid),wm_billing.remaining_team_admin(uuid,uuid),
 wm_billing.finalize_deletion(uuid,uuid),wm_billing.deletion_transition(),wm_billing.purge_paid_remainders() from public,anon,authenticated;
revoke all on function wm_billing.remainder_update_guard() from public,anon,authenticated;
grant execute on function wm_billing.remainder_binding(text,text,uuid),wm_billing.remaining_team_admin(uuid,uuid),
 wm_billing.purge_paid_remainders() to wm_billing_runtime;
