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
