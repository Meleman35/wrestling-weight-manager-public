-- Generated from reviewed candidate sources by core-billing-migration.mjs.
-- This migration installs storage and lifecycle integration, not purchase activation.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
select pg_advisory_xact_lock(hashtext('athlete_merge'));
lock table private.scoped_deletion_config,private.scoped_deletion_jobs in exclusive mode;
do $$begin
 if to_regnamespace('wm_billing') is not null then raise exception 'CORE_BILLING_ALREADY_INSTALLED';end if;
 if private.scoped_deletion_schema_hash() is distinct from 'c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8'
  or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash() and policy_version='scoped-deletion-v1') then
  raise exception 'CORE_BILLING_SCHEMA_REVIEW_REQUIRED';end if;
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('cancelled','completed')) then
  raise exception 'CORE_BILLING_DELETION_IN_PROGRESS';end if;
 if not exists(select 1 from pg_roles where rolname='wm_billing_runtime' and not rolcanlogin and not rolsuper and not rolbypassrls and not rolcreaterole and not rolcreatedb) then
  raise exception 'CORE_BILLING_RESTRICTED_ROLE_REQUIRED';end if;
 if encode(sha256(convert_to(pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure),'UTF8')),'hex')<>'991e2028b296773026c1a090426585d7af554636572e6ff42d2aa66754af4835' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: private.athlete_merge_request(text,jsonb)';end if;
 if encode(sha256(convert_to(pg_get_functiondef('private.scoped_deletion_media_inventory(uuid,jsonb)'::regprocedure),'UTF8')),'hex')<>'97cf77eb84ce9c86f34f55be2d3915e24c071fd1794dfe806b502649ebe1168d' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: private.scoped_deletion_media_inventory(uuid,jsonb)';end if;
 if encode(sha256(convert_to(pg_get_functiondef('private.scoped_deletion_read(text,jsonb,jsonb,integer)'::regprocedure),'UTF8')),'hex')<>'eb6d2395060ba7c2fd314ea3947b93108ff8d4cc34a2276eb3b4f0ad8950444f' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: private.scoped_deletion_read(text,jsonb,jsonb,integer)';end if;
 if encode(sha256(convert_to(pg_get_functiondef('private.scoped_deletion_schema_hash()'::regprocedure),'UTF8')),'hex')<>'1f4e32621a38bd54fd2f475ecfab04fcdac701a24d3d261af9bf181639645d4a' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: private.scoped_deletion_schema_hash()';end if;
 if encode(sha256(convert_to(pg_get_functiondef('private.scoped_deletion_seal_media(uuid,jsonb)'::regprocedure),'UTF8')),'hex')<>'4d0bb56b946649e117277757b93260dca693704f015dfa21b67e2e08eca6c43c' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: private.scoped_deletion_seal_media(uuid,jsonb)';end if;
 if encode(sha256(convert_to(pg_get_functiondef('private.scoped_deletion_service(text,uuid,uuid,jsonb)'::regprocedure),'UTF8')),'hex')<>'36d5ef044514777cfa77ae1ceef0a666005129c0d249ee359891a86e1f8b644e' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: private.scoped_deletion_service(text,uuid,uuid,jsonb)';end if;
end $$;

-- Draft schema for isolated validation. NOT a deployed Supabase migration.
-- Deployment requires financial retention/deletion catalog integration first.
create schema wm_billing;
revoke all on schema wm_billing from public;
create table wm_billing.team_bindings (
 user_id uuid primary key, team_id uuid not null
);
create table wm_billing.intents (
 token uuid primary key, user_id uuid not null, product_id text not null,
 scope text not null check(scope in ('team','family')), team_id uuid, family_owner_id uuid,
 created_at bigint not null check(created_at>=0), cancelled boolean not null default false,
 bound_original_id text,
 check((scope='team' and team_id is not null and family_owner_id is null) or
       (scope='family' and team_id is null and family_owner_id=user_id)),
 check((scope='team' and product_id in ('com.damonmele.wrestlingmanager.teampro.annual','com.damonmele.wrestlingmanager.teampro.monthly')) or
       (scope='family' and product_id in ('com.damonmele.wrestlingmanager.familyvideo.annual','com.damonmele.wrestlingmanager.familyvideo.monthly')))
);
create table wm_billing.subscriptions (
 environment text not null check(environment in ('Sandbox','Production')),
 original_id text not null check(original_id ~ '^[0-9]{1,40}$'),
 token uuid not null unique references wm_billing.intents(token),
 user_id uuid not null, scope text not null check(scope in ('team','family')),
 team_id uuid, family_owner_id uuid, snapshot jsonb not null,
 primary key(environment,original_id),
 check((scope='team' and team_id is not null and family_owner_id is null) or
       (scope='family' and team_id is null and family_owner_id=user_id)),
 check(snapshot->>'environment'=environment and snapshot->>'originalTransactionID'=original_id and
       (snapshot->>'appAccountToken')::uuid=token and (snapshot->>'userID')::uuid=user_id),
 check((scope='team' and snapshot->>'plan' in ('team_pro_year','team_pro_month') and (snapshot->>'teamID')::uuid=team_id) or
       (scope='family' and snapshot->>'plan' in ('family_video_year','family_video_month') and snapshot->>'teamID' is null and (snapshot->>'familyOwnerID')::uuid=family_owner_id))
);
create table wm_billing.deliveries (
 environment text not null, transaction_id text not null check(transaction_id ~ '^[0-9]{1,40}$'),
 original_id text not null, first_seen timestamptz not null default now(),
 last_seen timestamptz not null default now(), primary key(environment,transaction_id),
 foreign key(environment,original_id) references wm_billing.subscriptions(environment,original_id)
);
create table wm_billing.family_coverage (
 user_id uuid not null, slot smallint not null check(slot between 1 and 2),
 athlete_profile_id uuid not null, primary key(user_id,slot),unique(user_id,athlete_profile_id)
);
-- Dedicated backend role only; no anon/authenticated billing-table policies.
-- Provision this NOLOGIN role separately and grant it to the private service DB
-- identity. Never expose its credentials to native or browser source.
alter table wm_billing.team_bindings enable row level security;
alter table wm_billing.intents enable row level security;
alter table wm_billing.subscriptions enable row level security;
alter table wm_billing.deliveries enable row level security;
alter table wm_billing.family_coverage enable row level security;
revoke all on all tables in schema wm_billing from public;
grant usage on schema wm_billing to wm_billing_runtime;
grant select,insert,update on all tables in schema wm_billing to wm_billing_runtime;
grant delete on wm_billing.team_bindings to wm_billing_runtime;
create policy backend on wm_billing.team_bindings to wm_billing_runtime using(true) with check(true);
create policy backend on wm_billing.intents to wm_billing_runtime using(true) with check(true);
create policy backend on wm_billing.subscriptions to wm_billing_runtime using(true) with check(true);
create policy backend on wm_billing.deliveries to wm_billing_runtime using(true) with check(true);
create policy backend on wm_billing.family_coverage to wm_billing_runtime using(true) with check(true);

-- Narrow privileged helper: the runtime receives actor status, never auth rows.
-- Identity must match transaction-local claims minted after token verification.
create function wm_billing.current_actor(p_user uuid,p_session uuid,p_expires bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u auth.users%rowtype; s auth.sessions%rowtype; actor jsonb;
begin
 if auth.uid() is distinct from p_user or p_user is null or
    p_expires<=extract(epoch from clock_timestamp())*1000 then return null; end if;
 select * into u from auth.users where id=p_user for share;
 select * into s from auth.sessions where id=p_session and user_id=p_user for share;
 if u.id is null or s.id is null or (s.not_after is not null and s.not_after<=clock_timestamp()) then return null;end if;
 actor=jsonb_build_object('userID',p_user,'liveSession',true,
  'confirmed',u.confirmed_at is not null and not coalesce(u.is_anonymous,false),
  'deleted',u.deleted_at is not null,'banned',u.banned_until>clock_timestamp(),
  'managedTeamLogin',not private.board_personal(p_user),
  'deletionFrozen',exists(select 1 from private.scoped_deletion_jobs where actor_id=p_user and state not in ('cancelled','completed')));
 return actor;
end $$;
create function wm_billing.can_purchase_team(p_user uuid,p_team uuid)
returns boolean language sql security definer set search_path='' as $$
 select auth.uid()=p_user and private.board_personal(p_user) and not private.board_minor(p_user)
  and private.scoped_deletion_access_ok() and public.is_team_admin(p_team)
  and exists(select 1 from public.teams t where t.id=p_team and not exists(
   select 1 from private.scoped_deletion_jobs j where j.state not in ('cancelled','completed')
    and (j.actor_id=p_user or t.id=any(j.team_ids) or t.organization_id=any(j.organization_ids))))
$$;
create function wm_billing.can_purchase_family(p_user uuid)
returns boolean language sql security definer set search_path='' as $$
 select auth.uid()=p_user and private.board_personal(p_user) and not private.board_minor(p_user) and exists(
 select 1 from public.athlete_guardians g join public.team_memberships m on m.user_id=g.guardian_user_id
 and m.athlete_id=g.athlete_id and m.role='parent_guardian' and m.active
 where g.guardian_user_id=p_user and g.invitation_status='accepted')
$$;
revoke all on all functions in schema wm_billing from public;
grant execute on all functions in schema wm_billing to wm_billing_runtime;


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
create function wm_billing.prepare_deletion(p_job uuid,p_lease uuid)
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
end $$;

-- The final transition remains a cleanup backstop. The complete worker must
-- prepare the paid grant BEFORE deleting any sealed billing records.
create function wm_billing.finalize_deletion(p_job uuid,p_lease uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j private.scoped_deletion_jobs%rowtype;
begin
 select * into j from private.scoped_deletion_jobs where id=p_job and state='records'
  and sealed_at is not null and lease_token=p_lease and lease_until>clock_timestamp() for update;
 if not found or current_setting('role',true) is distinct from 'service_role' then raise exception 'BILLING_DELETION_LEASE_REQUIRED';end if;
 perform wm_billing.prepare_deletion(p_job,p_lease);
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
 wm_billing.prepare_deletion(uuid,uuid),wm_billing.finalize_deletion(uuid,uuid),wm_billing.deletion_transition(),wm_billing.purge_paid_remainders() from public,anon,authenticated;
revoke all on function wm_billing.remainder_update_guard() from public,anon,authenticated;
grant execute on function wm_billing.remainder_binding(text,text,uuid),wm_billing.remaining_team_admin(uuid,uuid),
 wm_billing.purge_paid_remainders() to wm_billing_runtime;


-- Apply only after billing-storage-candidate.sql in an isolated test database.
-- Canonical app helpers were inspected read-only on October 3, 2026.
-- This does not replace the video pilot gates or authorize uploads/recording.
create function wm_billing.resolve_access(p_user uuid,p_team uuid,p_athlete uuid,p_event uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with permission as (
  select auth.uid()=p_user and private.board_personal(p_user)
   and private.scoped_deletion_access_ok()
   and exists(select 1 from public.teams where id=p_team)
   and (public.is_team_staff(p_team) or exists(
    select 1 from public.team_memberships m where m.team_id=p_team and m.user_id=p_user and m.active))
   and not exists(select 1 from private.scoped_deletion_jobs j where j.state not in ('cancelled','completed')
    and (j.actor_id=p_user or p_team=any(j.team_ids) or exists(
     select 1 from public.teams t where t.id=p_team and t.organization_id=any(j.organization_ids)))) as team_ok,
   coalesce(p_event is not null and private.video_can_record(p_team,p_athlete,p_event),false) as record_ok,
   coalesce(private.tournament_athlete_access(p_team,p_athlete),false) as athlete_ok
 ), target as (
  select a.profile_id from public.athletes a where a.id=p_athlete and a.profile_id is not null
   and exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id
    where r.athlete_id=a.id and r.active and s.active and s.team_id=p_team)
 ), coverage as (
  select s.snapshot,s.family_owner_id,
   (select jsonb_agg(c2.athlete_profile_id order by c2.slot) from wm_billing.family_coverage c2
    where c2.user_id=c.user_id) as profiles
  from wm_billing.family_coverage c join target t on t.profile_id=c.athlete_profile_id
  join wm_billing.subscriptions s on s.family_owner_id=c.user_id and s.user_id=c.user_id and s.scope='family'
  join auth.users u on u.id=c.user_id
  where u.confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now()) and private.board_personal(u.id)
   and not exists(select 1 from private.scoped_deletion_jobs j
    where (j.actor_id=u.id and j.state not in ('cancelled','completed'))
     or (j.personal and j.sealed_at is not null and
      j.subject_hash=encode(sha256(convert_to(u.id::text,'UTF8')),'hex')))
   -- Coverage follows the canonical profile, but this team's guardian link must
   -- still be accepted and active. A stale link on another roster is insufficient.
   and exists(select 1 from public.athlete_guardians g join public.team_memberships m
    on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id and m.team_id=p_team
     and m.role='parent_guardian' and m.active
    where g.athlete_id=p_athlete and g.guardian_user_id=c.user_id and g.invitation_status='accepted')
 )
 select case when not coalesce(team_ok,false) then jsonb_build_object('teamAuthorized',false)
 else jsonb_build_object('teamAuthorized',true,
  'athleteAuthorized',athlete_ok or record_ok,'recorderAuthorized',record_ok,
  'athleteProfileID',(select profile_id from target),
  'teamSubscriptions',coalesce((select jsonb_agg(s.snapshot) from wm_billing.subscriptions s
   join auth.users u on u.id=s.user_id where s.scope='team' and s.team_id=p_team
    and u.confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
    and (u.banned_until is null or u.banned_until<=now()) and private.board_personal(u.id)
    and not exists(select 1 from private.scoped_deletion_jobs j
     where (j.actor_id=u.id and j.state not in ('cancelled','completed')) or
      (j.personal and j.sealed_at is not null and
       j.subject_hash=encode(sha256(convert_to(u.id::text,'UTF8')),'hex')))),'[]'::jsonb),
  'remainingTeamAdmin',wm_billing.remaining_team_admin(p_team),
  'teamPaidRemainders',coalesce((select jsonb_agg(jsonb_build_object('teamID',r.team_id,'environment',r.environment,
   'plan',r.plan,'paidThrough',r.paid_through,'revokedAt',r.revoked_at,'snapshotSignedAt',r.snapshot_signed_at))
   from wm_billing.team_paid_remainders r where r.team_id=p_team and r.revoked_at is null
    and r.paid_through>floor(extract(epoch from now())*1000)),'[]'::jsonb),
  'familyCoverage',case when athlete_ok or record_ok then coalesce((select jsonb_agg(jsonb_build_object(
   'subscription',snapshot,'familyOwnerID',family_owner_id,'linkedProfileIDs',profiles)) from coverage),'[]'::jsonb)
   else '[]'::jsonb end) end from permission
$$;
revoke all on function wm_billing.resolve_access(uuid,uuid,uuid,uuid) from public;
grant execute on function wm_billing.resolve_access(uuid,uuid,uuid,uuid) to wm_billing_runtime;

-- The server accepts roster athlete IDs, then resolves profiles itself. Two
-- roster records of the same athlete cannot consume two coverage slots.
create function wm_billing.set_family_coverage(p_user uuid,p_athletes uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare profiles uuid[]; matched integer;
begin
 if auth.uid() is distinct from p_user or p_user is null or not private.board_personal(p_user)
  or private.board_minor(p_user) or not private.scoped_deletion_access_ok()
  or exists(select 1 from private.scoped_deletion_jobs where actor_id=p_user and state not in ('cancelled','completed')) then
  raise exception 'family_coverage_forbidden';
 end if;
 if p_athletes is null or cardinality(p_athletes)>2 or array_position(p_athletes,null) is not null
  or cardinality(p_athletes)<>(select count(distinct x) from unnest(p_athletes) x) then raise exception 'invalid_coverage';end if;
 -- The merge router takes the exclusive form before resolving profile IDs.
 -- Hold this through commit so a selection cannot recreate a retired profile.
 perform pg_advisory_xact_lock_shared(hashtext('athlete_merge'));
 select array_agg(a.profile_id order by array_position(p_athletes,a.id)),count(*) into profiles,matched
 from public.athletes a where a.id=any(p_athletes) and a.profile_id is not null and exists(
  select 1 from public.athlete_guardians g join public.team_memberships m
   on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id and m.role='parent_guardian' and m.active
  join public.roster_memberships r on r.athlete_id=a.id and r.active
  join public.seasons s on s.id=r.season_id and s.team_id=m.team_id and s.active
  join public.teams t on t.id=m.team_id
  where g.athlete_id=a.id and g.guardian_user_id=p_user and g.invitation_status='accepted'
   and not exists(select 1 from private.scoped_deletion_jobs j where j.state not in ('cancelled','completed')
    and (t.id=any(j.team_ids) or t.organization_id=any(j.organization_ids))))
 ;
 if matched<>cardinality(p_athletes) then raise exception 'family_coverage_forbidden';end if;
 if matched<>(select count(distinct x) from unnest(profiles) x) then raise exception 'invalid_coverage';end if;
 delete from wm_billing.family_coverage where user_id=p_user;
 insert into wm_billing.family_coverage(user_id,slot,athlete_profile_id)
  select p_user,ord::smallint,profile from unnest(profiles) with ordinality as selected(profile,ord);
 return jsonb_build_object('selectedCount',matched);
end $$;
revoke all on function wm_billing.set_family_coverage(uuid,uuid[]) from public;
grant execute on function wm_billing.set_family_coverage(uuid,uuid[]) to wm_billing_runtime;

-- Only accepted, currently active guardian/roster relationships are selectable.
-- One row per canonical profile prevents two team copies consuming two slots.
create function wm_billing.family_coverage_options(p_user uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is distinct from p_user or p_user is null or not private.board_personal(p_user)
  or private.board_minor(p_user) or not private.scoped_deletion_access_ok()
  or exists(select 1 from private.scoped_deletion_jobs where actor_id=p_user and state not in ('cancelled','completed')) then
  raise exception 'family_coverage_forbidden';
 end if;
 with candidates as (
  select distinct on (a.profile_id) a.id,a.profile_id,
   left(trim(concat_ws(' ',to_jsonb(a)->>'first_name',to_jsonb(a)->>'last_name')),240) as display_name,
   exists(select 1 from wm_billing.family_coverage c where c.user_id=p_user and c.athlete_profile_id=a.profile_id) as selected
  from public.athletes a where a.profile_id is not null and exists(
   select 1 from public.athlete_guardians g join public.team_memberships m
    on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id and m.role='parent_guardian' and m.active
   join public.roster_memberships r on r.athlete_id=a.id and r.active
   join public.seasons s on s.id=r.season_id and s.team_id=m.team_id and s.active
   join public.teams t on t.id=m.team_id
   where g.athlete_id=a.id and g.guardian_user_id=p_user and g.invitation_status='accepted'
    and not exists(select 1 from private.scoped_deletion_jobs j where j.state not in ('cancelled','completed')
     and (t.id=any(j.team_ids) or t.organization_id=any(j.organization_ids))))
  order by a.profile_id,a.id limit 1001
 ) select coalesce(jsonb_agg(jsonb_build_object('athlete_id',id,'profile_id',profile_id,
  'display_name',display_name,'selected',selected) order by display_name,id),'[]'::jsonb) into result from candidates;
 if jsonb_array_length(result)>1000 then raise exception 'family_coverage_forbidden';end if;
 return result;
end $$;
revoke all on function wm_billing.family_coverage_options(uuid) from public;
grant execute on function wm_billing.family_coverage_options(uuid) to wm_billing_runtime;


-- Isolated candidate. Apply after billing-access-candidate.sql and the reviewed
-- current merge router. This never approves a new deletion/merge fingerprint.
-- Apply in one transaction; a source-pin failure must roll back every change.
-- Coverage may be changed only through the authorized selection/merge helpers.
revoke insert,update,delete on wm_billing.family_coverage from wm_billing_runtime;

create function wm_billing.coverage_merge_version(p_duplicate uuid,p_keep uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare result text;
begin
 if auth.uid() is null then raise exception 'BILLING_MERGE_AUTH_REQUIRED';end if;
 select encode(sha256(convert_to(coalesce(string_agg(
  c.user_id::text||':'||c.slot::text||':'||c.athlete_profile_id::text,'|' order by c.user_id,c.slot),''),'UTF8')),'hex')
 into result from wm_billing.family_coverage c where c.athlete_profile_id in
  (select profile_id from public.athletes where id in(p_duplicate,p_keep));
 return result;
end $$;

create function wm_billing.merge_family_coverage(p_duplicate uuid,p_keep uuid)
returns void language plpgsql security definer set search_path='' as $$
declare source_profile uuid;target_profile uuid;
begin
 if auth.uid() is null or p_duplicate is null or p_keep is null or p_duplicate=p_keep then
  raise exception 'BILLING_MERGE_AUTH_REQUIRED';end if;
 -- Same order as the existing merge router; selection takes a shared lock.
 perform pg_advisory_xact_lock(hashtext('athlete_merge'));
 select profile_id into source_profile from public.athletes where id=p_duplicate;
 select profile_id into target_profile from public.athletes where id=p_keep;
 if source_profile is null or target_profile is null then raise exception 'BILLING_MERGE_PROFILE_REQUIRED';end if;
 if source_profile=target_profile then return;end if;
 if exists(select 1 from public.athletes where profile_id=source_profile and id<>p_duplicate) then
  raise exception 'BILLING_MERGE_SHARED_PROFILE_REVIEW';end if;
 perform 1 from wm_billing.family_coverage where athlete_profile_id in(source_profile,target_profile)
  order by user_id,slot for update;
 if exists(select 1 from wm_billing.family_coverage c join private.scoped_deletion_jobs j on j.actor_id=c.user_id
  where c.athlete_profile_id in(source_profile,target_profile) and j.state not in ('cancelled','completed')) then
  raise exception 'BILLING_MERGE_DELETION_PENDING';end if;
 -- Keep an already-selected target slot. Combining duplicate identities must
 -- not consume a second family slot or add any subscription entitlement.
 delete from wm_billing.family_coverage src using wm_billing.family_coverage dst
  where src.athlete_profile_id=source_profile and dst.athlete_profile_id=target_profile and src.user_id=dst.user_id;
 update wm_billing.family_coverage set athlete_profile_id=target_profile where athlete_profile_id=source_profile;
end $$;
revoke all on function wm_billing.coverage_merge_version(uuid,uuid),wm_billing.merge_family_coverage(uuid,uuid)
 from public,anon,authenticated,wm_billing_runtime;

-- Pin the complete currently deployed router, not just an editable marker.
-- A changed router must be inspected before generating the production migration.
do $$declare source text;old_plan text:='plan:=private.athlete_merge_plan(s,k,contact_resolution);';
 old_mutation text:='select * into a from public.athletes where id=s;select * into b from public.athletes where id=k;';
begin
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if encode(sha256(convert_to(source,'UTF8')),'hex')<>'991e2028b296773026c1a090426585d7af554636572e6ff42d2aa66754af4835'
  or (length(source)-length(replace(source,old_plan,'')))<>length(old_plan)
  or (length(source)-length(replace(source,old_mutation,'')))<>length(old_mutation) then
  raise exception 'BILLING_MERGE_ROUTER_REVIEW_REQUIRED';end if;
 source:=replace(source,old_plan,old_plan||E'\n plan:=jsonb_set(plan,''{version}'',to_jsonb(encode(sha256(convert_to((plan->>''version'')||''|''||wm_billing.coverage_merge_version(s,k),''UTF8'')),''hex'')));');
 source:=replace(source,old_mutation,old_mutation||E'\n perform wm_billing.merge_family_coverage(s,k);');
 execute source;
end $$;


create or replace function private.scoped_deletion_schema_hash() returns text
language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(coalesce(string_agg(x,'|' order by x),''),'UTF8')),'hex') from (
  select n.nspname||'.'||c.relname||'.'||a.attname||':'||a.atttypid||':'||a.atttypmod||':'||a.attnotnull||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),'') x
  from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
  where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%'
  union all select n.nspname||'.'||c.relname||':'||pg_get_constraintdef(k.oid)
   from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','private','wm_billing') and c.relname not like 'scoped_deletion_%'
  union all select pg_get_triggerdef(t.oid)||':'||pg_get_functiondef(t.tgfoid)
   from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where not t.tgisinternal and n.nspname in ('public','private','wm_billing') and t.tgname<>'scoped_deletion_freeze'
 ) s;
$$;
create or replace function private.scoped_deletion_read(p_table text,p_predicates jsonb,p_mention jsonb,p_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; s text; t text; col text;
begin
 s:=split_part(p_table,'.',1);t:=split_part(p_table,'.',2);
 if s not in ('public','private','wm_billing') or p_table!~'^[a-z_]+\.[a-z_][a-z0-9_]*$' or t like 'scoped_deletion_%'
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
end $$;
create or replace function private.scoped_deletion_media_inventory(p_job uuid,p_records jsonb) returns jsonb
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
    where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%' loop
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
    where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%' loop
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
create or replace function private.scoped_deletion_seal_media(p_job uuid,p_objects jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare records jsonb;actual jsonb;o jsonb;r record;
begin
 lock table storage.objects in share row exclusive mode;
 -- References can be introduced in any application table. Lock in stable order
 -- before the final cross-reference scan and install matching write freezes.
 for r in select n.nspname schema,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%' order by 1,2 loop
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
   where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%' on conflict do nothing;
 end loop;
 -- Copied email addresses are held to the same observed scope as UUID snapshots.
 insert into private.scoped_deletion_filters(job_id,table_name,predicate)
 select p_job,n.nspname||'.'||c.relname,jsonb_build_object('mention',jsonb_build_object('columns',jsonb_build_array('*'),'actorId',lower(u.email),'ignoreCase',true))
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join private.scoped_deletion_jobs j join auth.users u on u.id=j.actor_id
 where j.id=p_job and j.personal and n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%' on conflict do nothing;
end $$;
create or replace function private.scoped_deletion_service(p_op text,p_job uuid,p_lease uuid,p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
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
  -- Preserve paid team time while the sealed purchase evidence still exists.
  -- This runs in the same transaction, before the generic record erasure.
  perform wm_billing.prepare_deletion(j.id,p_lease);
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
end $$;
do $$declare tab text;begin
  foreach tab in array array['team_bindings','intents','subscriptions','deliveries','family_coverage','notification_inbox','team_paid_remainders'] loop
   execute format('create trigger scoped_deletion_freeze before insert or update or delete on wm_billing.%I for each row execute function private.scoped_deletion_freeze()',tab);
  end loop;
 end $$;

-- The unchanged baseline and six source pins were checked before any DDL.
-- Enroll exactly the seven reviewed tables, then update both compatibility gates
-- atomically with their lifecycle hooks. Never approve an arbitrary drifted hash.
do $$declare reviewed_catalog jsonb;new_hash text;source text;actual_tables text[];
 old_hash text:='c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8';
begin
 select array_agg(c.relname::text order by c.relname) into actual_tables from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and c.relkind='r';
 if actual_tables is distinct from array['deliveries','family_coverage','intents','notification_inbox','subscriptions','team_bindings','team_paid_remainders'] then raise exception 'CORE_BILLING_TABLE_REVIEW_REQUIRED';end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and c.relkind='r' and not c.relrowsecurity) then raise exception 'CORE_BILLING_RLS_REQUIRED';end if;
 if (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and t.tgname='scoped_deletion_freeze' and not t.tgisinternal)<>7 then raise exception 'CORE_BILLING_FREEZE_REQUIRED';end if;
 select jsonb_build_object(
 'tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'columns',
  (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull) order by a.attnum)
   from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) order by n.nspname,c.relname),'[]')
  from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%'),
 'constraints',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',k.conname,'type',k.contype,
  'columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.conkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=c.oid and a.attnum=z.num),
  'ref_schema',rn.nspname,'ref_table',rc.relname,
  'ref_columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.confkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=rc.oid and a.attnum=z.num),
  'delete_action',k.confdeltype) order by n.nspname,c.relname,k.conname),'[]')
  from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
  left join pg_class rc on rc.oid=k.confrelid left join pg_namespace rn on rn.oid=rc.relnamespace
  where n.nspname in ('public','private','wm_billing') and c.relname not like 'scoped_deletion_%')
) into reviewed_catalog;
 new_hash:=private.scoped_deletion_schema_hash();
 if new_hash=old_hash or new_hash!~'^[a-f0-9]{64}$' then raise exception 'CORE_BILLING_FINGERPRINT_REQUIRED';end if;
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if (length(source)-length(replace(source,old_hash,'')))<>length(old_hash)
  or position('wm_billing.merge_family_coverage(s,k)' in source)=0 then raise exception 'CORE_BILLING_MERGE_REVIEW_REQUIRED';end if;
 execute replace(source,old_hash,new_hash);
 update private.scoped_deletion_config set catalog=reviewed_catalog,catalog_hash=new_hash where id;
end $$;
commit;
