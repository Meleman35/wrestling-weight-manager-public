CREATE OR REPLACE FUNCTION private.team_people_revision(t uuid, u uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select md5(jsonb_build_array(
  (select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]') from public.team_memberships m where m.team_id=t and m.user_id=u),
  (select to_jsonb(p) from public.team_staff_profiles p where p.team_id=t and p.user_id=u),
  (select coalesce(jsonb_agg(to_jsonb(o) order by o.organization_id),'[]') from public.organization_memberships o join public.teams x on x.organization_id=o.organization_id where x.id=t and o.user_id=u),
  (select coalesce(jsonb_agg(jsonb_build_array(a.id,a.birth_date,r.id,r.active,r.roster_status,s.active) order by a.id,r.id),'[]')
   from public.athletes a join public.team_memberships m on m.athlete_id=a.id and m.role='athlete'
   left join public.roster_memberships r on r.athlete_id=a.id left join public.seasons s on s.id=r.season_id and s.team_id=t
   where m.team_id=t and m.user_id=u)
 )::text);
$function$;

