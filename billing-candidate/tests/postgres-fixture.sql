-- Synthetic disposable database only. Never load into the live app database.
create role anon nologin;create role authenticated nologin;create role wm_billing_runtime nologin;create role service_role nologin;
create schema auth;create schema private;
create table auth.users(id uuid primary key,confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean default false);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create table private.team_logins(user_id uuid);
create table private.test_minors(user_id uuid);
create table private.scoped_deletion_jobs(actor_id uuid,state text,id uuid primary key default gen_random_uuid(),lease_token uuid,lease_until timestamptz);
create function private.board_personal(u uuid) returns boolean language sql as $$select u is not null and not exists(select 1 from private.team_logins where user_id=u)$$;
create function private.board_minor(u uuid) returns boolean language sql as $$select exists(select 1 from private.test_minors where user_id=u)$$;
create table public.teams(id uuid primary key,organization_id uuid);
create table public.organization_memberships(user_id uuid,organization_id uuid,role text);
create table public.team_memberships(team_id uuid,user_id uuid,athlete_id uuid,role text,permissions jsonb default '{}',active boolean default true);
create table public.athlete_guardians(athlete_id uuid,guardian_user_id uuid,invitation_status text);
create function public.is_team_admin(t uuid) returns boolean language sql as $$select exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=auth.uid() and m.active and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false)))) or exists(select 1 from public.teams x join public.organization_memberships o on o.organization_id=x.organization_id where x.id=t and o.user_id=auth.uid() and o.role='organization_admin')$$;
