-- Inspected production definitions. No customer data.
CREATE OR REPLACE FUNCTION public.is_team_admin(check_team_id uuid)
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
        tm.role='head_coach'
        or (
          tm.role in ('assistant_coach','manager')
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
$function$;


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
$function$;


CREATE OR REPLACE FUNCTION public.get_team_adult_access(p_team_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if not public.is_team_admin(p_team_id) then raise exception 'team admin access required'; end if;

  with team_info as (
    select t.organization_id from public.teams t where t.id=p_team_id
  ),
  people as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id
      and tm.active=true
      and tm.role in ('head_coach','assistant_coach','manager','parent_guardian')
    union
    select om.user_id
    from public.organization_memberships om
    join team_info ti on ti.organization_id=om.organization_id
    where om.role='organization_admin'
  ),
  details as (
    select
      pe.user_id,
      private.communication_person_name(p_team_id,pe.user_id) as display_name,
      u.email,
      tsp.title,
      sm.role as membership_role,
      coalesce(sm.permissions,'{}'::jsonb) as permissions,
      exists(
        select 1 from public.team_memberships pg
        where pg.team_id=p_team_id and pg.user_id=pe.user_id
          and pg.active=true and pg.role='parent_guardian'
      ) as is_parent_guardian,
      exists(
        select 1
        from public.organization_memberships om
        join team_info ti on ti.organization_id=om.organization_id
        where om.user_id=pe.user_id and om.role='organization_admin'
      ) as is_organization_admin
    from people pe
    join auth.users u on u.id=pe.user_id
    left join public.profiles p on p.id=pe.user_id
    left join public.team_staff_profiles tsp
      on tsp.team_id=p_team_id and tsp.user_id=pe.user_id
    left join lateral (
      select tm.role,tm.permissions
      from public.team_memberships tm
      where tm.team_id=p_team_id
        and tm.user_id=pe.user_id
        and tm.active=true
        and tm.role in ('head_coach','assistant_coach','manager')
      order by case tm.role when 'head_coach' then 1 when 'assistant_coach' then 2 else 3 end
      limit 1
    ) sm on true
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id',d.user_id,
      'display_name',d.display_name,
      'email',d.email,
      'title',coalesce(
        nullif(d.title,''),
        case
          when d.is_organization_admin then 'Organization Admin'
          when d.membership_role='head_coach' then 'Head Coach'
          when d.membership_role='assistant_coach' then 'Assistant Coach'
          when d.membership_role='manager' then 'Limited Staff'
          when d.is_parent_guardian then 'Parent / Guardian'
          else 'Adult Member'
        end
      ),
      'membership_role',d.membership_role,
      'staff_role',coalesce(
        nullif(d.permissions->>'staff_role',''),
        case
          when d.is_organization_admin and lower(coalesce(d.title,''))='club president' then 'club_president'
          when d.membership_role='head_coach' then 'head_coach'
          when d.membership_role='assistant_coach' and lower(coalesce(d.title,''))='volunteer coach' then 'volunteer_coach'
          when d.membership_role='assistant_coach' then 'assistant_coach'
          when d.membership_role='manager' and lower(coalesce(d.title,''))='team leader' then 'team_leader'
          when d.membership_role='manager' and lower(coalesce(d.title,''))='team mom' then 'team_mom'
          when d.membership_role='manager' then 'limited_staff'
          else null
        end
      ),
      'permissions',d.permissions,
      'is_parent_guardian',d.is_parent_guardian,
      'is_organization_admin',d.is_organization_admin,
      'is_team_admin',(
        d.is_organization_admin
        or d.membership_role='head_coach'
        or coalesce((d.permissions->>'team_admin')::boolean,false)
      )
    )
    order by
      case
        when d.membership_role='head_coach' then 1
        when d.is_organization_admin then 2
        when d.membership_role='assistant_coach' then 3
        when d.membership_role='manager' then 4
        when d.is_parent_guardian then 5
        else 9
      end,
      d.display_name
  ),'[]'::jsonb)
  into v_result
  from details d;

  return v_result;
end;
$function$;
