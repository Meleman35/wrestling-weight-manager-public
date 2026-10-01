CREATE OR REPLACE FUNCTION private.communication_person_name(p_team_id uuid, p_user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with account as (
  select p.display_name,sp.display_name staff_name,u.email,u.raw_user_meta_data meta
  from auth.users u left join public.profiles p on p.id=u.id
  left join public.team_staff_profiles sp on sp.user_id=u.id and sp.team_id=p_team_id
  where u.id=p_user_id
 ), own_names as (
  select distinct nullif(trim(concat_ws(' ',a.first_name,a.last_name)),'') name,m.active
  from public.team_memberships m join public.athletes a on a.id=m.athlete_id
  where m.team_id=p_team_id and m.user_id=p_user_id and m.role='athlete'
 ), candidates as (
  select name,1 priority from own_names where active
  union all select staff_name,2 from account
  union all select display_name,3 from account
  union all select min(name),4 from own_names having count(distinct name)=1
  union all select meta->>'full_name',5 from account
  union all select meta->>'name',6 from account
 )
 select coalesce((select trim(c.name) from candidates c cross join account a
  where nullif(trim(c.name),'') is not null
   and lower(trim(c.name))<>lower(coalesce(a.email,''))
   and lower(trim(c.name))<>lower(split_part(coalesce(a.email,''),'@',1))
  order by priority,lower(c.name) limit 1),'Team member');
$function$;
