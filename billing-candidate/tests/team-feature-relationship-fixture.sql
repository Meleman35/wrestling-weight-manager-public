-- Exact live relationship helpers inspected October 5; definitions only.
CREATE OR REPLACE FUNCTION public.is_self_athlete(check_athlete_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.team_memberships tm
    where tm.athlete_id=check_athlete_id
      and tm.user_id=auth.uid()
      and tm.role='athlete'
      and tm.active=true
  );
$function$
;
CREATE OR REPLACE FUNCTION public.is_guardian_for_athlete(check_athlete_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.athlete_guardians ag
    join public.team_memberships tm
      on tm.user_id=ag.guardian_user_id
     and tm.athlete_id=ag.athlete_id
     and tm.role='parent_guardian'
     and tm.active=true
    where ag.athlete_id=check_athlete_id
      and ag.guardian_user_id=auth.uid()
  );
$function$
;
