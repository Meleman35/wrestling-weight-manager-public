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
  'teamSubscriptions',coalesce((select jsonb_agg(snapshot) from wm_billing.subscriptions
   where scope='team' and team_id=p_team),'[]'::jsonb),
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
