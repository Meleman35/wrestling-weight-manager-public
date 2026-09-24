-- Minimal isolated Postgres fixture for the existing 0.20.35 database contracts.
create schema auth; create schema private;
create role anon; create role authenticated; create role service_role;
grant usage on schema public,private,auth to authenticated,anon;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.profiles(id uuid primary key,display_name text);
create table public.organizations(id uuid primary key default gen_random_uuid(),name text,organization_type text default 'club');
create table public.organization_memberships(organization_id uuid,user_id uuid,role text);
create table public.teams(id uuid primary key,organization_id uuid,name text);
create table public.athletes(id uuid primary key,birth_date date);
create table public.team_memberships(team_id uuid,user_id uuid,role text,athlete_id uuid,active boolean default true);
create table private.team_logins(user_id uuid);
create table private.ops_roles(organization_id uuid,division_id uuid,user_id uuid,role text);
create table private.ops_records(organization_id uuid,kind text,data jsonb);
create table private.ops_links(organization_id uuid,team_id uuid,approved boolean);
create table private.ops_divisions(id uuid primary key,organization_id uuid,parent_id uuid,name text,unique(organization_id,id));
create table private.ops_audit(id bigint generated always as identity,organization_id uuid,actor_id uuid,action text,record_id uuid,detail jsonb,created_at timestamptz default now());
create table private.organization_positions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),division_id uuid,
 title text not null,assigned_user_id uuid references public.profiles(id),access_role text,voting_member boolean not null default false,
 can_manage_meetings boolean not null default false,can_manage_votes boolean not null default false,sort_order int not null default 100,
 active boolean not null default true,revision int not null default 1,created_by uuid references public.profiles(id),updated_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),foreign key(organization_id,division_id) references private.ops_divisions(organization_id,id));
create table private.organization_affiliates(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),name text not null,
 linked_team_id uuid references public.teams(id),status text not null default 'active',voting_eligible boolean not null default true,contact jsonb not null default '{}',
 sort_order int not null default 100,revision int not null default 1,created_by uuid references public.profiles(id),updated_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),archived_at timestamptz);
create table private.organization_affiliate_delegates(id uuid primary key,affiliate_id uuid,user_id uuid,active boolean);
create table private.organization_meetings(id uuid); create table private.organization_ballots(id uuid);
create function public.organization_governance(p_request jsonb) returns jsonb language sql as $$select '{}'::jsonb$$;
create function private.ops_personal() returns boolean language sql stable set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.team_logins where user_id=auth.uid())$$;
create function private.managed_login_access_ok() returns boolean language sql stable set search_path='' as $$select private.ops_personal()$$;
create function private.ops_admin(o uuid) returns boolean language sql stable set search_path='' as $$select private.ops_personal() and exists(select 1 from public.organization_memberships where organization_id=o and user_id=auth.uid() and role='organization_admin')$$;
create function private.gov_can_read(o uuid) returns boolean language sql stable set search_path='' as $$select private.ops_personal() and (
 exists(select 1 from public.organization_memberships where organization_id=o and user_id=auth.uid())
 or exists(select 1 from public.team_memberships m join public.teams t on t.id=m.team_id where m.user_id=auth.uid() and m.active and t.organization_id=o)
 or exists(select 1 from private.organization_positions where organization_id=o and active and assigned_user_id=auth.uid()))$$;
