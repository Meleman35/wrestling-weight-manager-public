-- Synthetic schema shape plus exact canonical app permission helpers inspected
-- read-only October 3, 2026. No private data or production rows are included.
alter table private.scoped_deletion_jobs add column personal boolean default false,
 add column sealed_at timestamptz, add column subject_hash text,
 add column team_ids uuid[] default '{}',add column organization_ids uuid[] default '{}';
alter table private.team_logins add column team_id uuid,add column kind text,
 add column active boolean default true,add column state text,add column permissions jsonb default '{}';
create table public.athlete_profiles(id uuid primary key);
create table public.athletes(id uuid primary key,profile_id uuid references public.athlete_profiles(id));
create table public.seasons(id uuid primary key,team_id uuid,active boolean default true);
create table public.roster_memberships(season_id uuid,athlete_id uuid,active boolean default true);
create table public.team_events(id uuid primary key,team_id uuid,season_id uuid);
create table private.video_pilot_control(id boolean primary key,enabled boolean,test_only boolean);
create table private.video_pilot_grants(team_id uuid,user_id uuid,revoked_at timestamptz,expires_at timestamptz);
create table private.video_athlete_permissions(team_id uuid,athlete_id uuid,guardian_id uuid,recording_allowed boolean);
create table private.video_event_settings(team_id uuid,event_id uuid,recording_permitted boolean);
create table private.video_recorder_assignments(team_id uuid,event_id uuid,athlete_id uuid,user_id uuid,expires_at timestamptz);
create table private.video_team_recorder_settings(team_id uuid,season_id uuid,enabled boolean);
create table private.tournament_visibility(athlete_id uuid,level text);
-- Managed identities are rejected by the access service before these helpers.
-- This stub is not evidence that managed-device authentication has been tested.
create function private.managed_login_access_ok() returns boolean language sql as $$select false$$;
CREATE OR REPLACE FUNCTION public.is_team_staff(check_team_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.team_memberships tm
    where tm.team_id=check_team_id
      and tm.user_id=(select auth.uid())
      and tm.active=true
      and (
        tm.role in ('head_coach','assistant_coach')
        or (
          tm.role='manager'
          and coalesce((tm.permissions->>'team_admin')::boolean,false)
        )
      )
  )
  or exists (
    select 1
    from public.teams t
    join public.organization_memberships om on om.organization_id=t.organization_id
    where t.id=check_team_id
      and om.user_id=(select auth.uid())
      and om.role='organization_admin'
  );
$function$
;

CREATE OR REPLACE FUNCTION private.tournament_guardian(t uuid, a uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.athlete_guardians g join public.team_memberships m on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id and m.team_id=t and m.role='parent_guardian' and m.active where g.athlete_id=a and g.guardian_user_id=auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION private.tournament_athlete_access(t uuid, a uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where r.athlete_id=a and r.active and s.active and s.team_id=t)
 and (public.is_team_staff(t) or private.tournament_guardian(t,a) or exists(select 1 from public.team_memberships m where m.team_id=t and m.athlete_id=a and m.user_id=auth.uid() and m.role='athlete' and m.active));
$function$
;

CREATE OR REPLACE FUNCTION private.video_recording_device(t uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and private.managed_login_access_ok()
 and exists(select 1 from private.team_logins l join public.team_memberships m on m.user_id=l.user_id and m.team_id=l.team_id
 where l.user_id=auth.uid() and l.team_id=t and l.kind='team_device' and l.active and l.state='ready'
 and l.permissions->'record_matches'='true'::jsonb and m.active and m.role='manager' and m.permissions->'record_matches'='true'::jsonb)
$function$
;

CREATE OR REPLACE FUNCTION private.video_team_enabled(t uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and (not exists(select 1 from private.team_logins where user_id=auth.uid()) or private.video_recording_device(t))
 and exists(select 1 from private.video_pilot_control where id and enabled)
 and exists(select 1 from private.video_pilot_grants g where g.team_id=t and g.revoked_at is null and g.expires_at>now())
$function$
;

CREATE OR REPLACE FUNCTION private.video_consent(t uuid, a uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from private.video_athlete_permissions p join public.athlete_guardians g on g.athlete_id=p.athlete_id and g.guardian_user_id=p.guardian_id
 join public.team_memberships m on m.team_id=p.team_id and m.user_id=p.guardian_id and m.athlete_id=p.athlete_id and m.role='parent_guardian' and m.active
 where p.team_id=t and p.athlete_id=a and p.recording_allowed)
 and not exists(select 1 from private.video_athlete_permissions p join public.athlete_guardians g on g.athlete_id=p.athlete_id and g.guardian_user_id=p.guardian_id
 join public.team_memberships m on m.team_id=p.team_id and m.user_id=p.guardian_id and m.athlete_id=p.athlete_id and m.role='parent_guardian' and m.active
 where p.team_id=t and p.athlete_id=a and not p.recording_allowed)
$function$
;

CREATE OR REPLACE FUNCTION private.video_team_recorder(t uuid, sid uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null
 and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and private.video_team_enabled(t)
 and exists(
  select 1 from private.video_team_recorder_settings v
  join public.seasons s on s.id=v.season_id and s.team_id=v.team_id and s.active
  join public.team_memberships m on m.team_id=v.team_id and m.user_id=auth.uid() and m.active
  where v.team_id=t and v.enabled and (sid is null or v.season_id=sid)
  and (m.role='manager' or (m.role='athlete' and exists(
   select 1 from public.roster_memberships r where r.season_id=s.id and r.athlete_id=m.athlete_id and r.active)))
 )
$function$
;

CREATE OR REPLACE FUNCTION private.video_can_record(t uuid, a uuid, ev uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select private.video_team_enabled(t) and not (select test_only from private.video_pilot_control where id) and private.video_consent(t,a)
 and exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where r.athlete_id=a and r.active and s.active and s.team_id=t)
 and exists(select 1 from private.video_event_settings v where v.team_id=t and v.event_id=ev and v.recording_permitted)
 and ( (public.is_team_staff(t) and exists(select 1 from private.video_pilot_grants g where g.team_id=t and g.user_id=auth.uid() and g.expires_at>now() and g.revoked_at is null))
 or private.video_recording_device(t)
 or exists(select 1 from public.team_events e where e.id=ev and e.team_id=t and private.video_team_recorder(t,e.season_id))
 or exists(select 1 from private.video_recorder_assignments r join public.team_memberships m on m.team_id=t and m.user_id=r.user_id and m.active
 where r.team_id=t and r.event_id=ev and r.athlete_id=a and r.user_id=auth.uid() and r.expires_at>now()) )
 -- A teammate shortcut must not reveal opponent details hidden by guardian visibility.
 and (public.is_team_staff(t) or private.tournament_guardian(t,a) or coalesce((select level from private.tournament_visibility where athlete_id=a),'upcoming')='full')
$function$
;

CREATE OR REPLACE FUNCTION private.scoped_deletion_access_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is null or not exists(
  select 1 from private.scoped_deletion_jobs j
  where j.subject_hash=encode(sha256(convert_to(auth.uid()::text,'UTF8')),'hex')
   and j.personal and j.sealed_at is not null
 );
$function$
;

