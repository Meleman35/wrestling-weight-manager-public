-- Existing production organization access predicate, read-only capture 2026-09-25.
CREATE OR REPLACE FUNCTION private.ops_member(o uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and (
   exists(select 1 from public.organization_memberships where organization_id=o and user_id=auth.uid())
   or exists(select 1 from private.ops_roles where organization_id=o and user_id=auth.uid())
   or exists(select 1 from private.organization_positions where organization_id=o and assigned_user_id=auth.uid() and active)
   or exists(
     select 1 from private.organization_affiliate_delegates d
     join private.organization_affiliates a on a.id=d.affiliate_id
     where a.organization_id=o and a.status='active' and d.user_id=auth.uid() and d.active
   )
   or exists(select 1 from private.ops_records where organization_id=o and kind='person' and data->>'user_id'=auth.uid()::text)
   or exists(
     select 1 from public.team_memberships m
     join public.teams t on t.id=m.team_id
     where m.user_id=auth.uid() and m.active
       and (t.organization_id=o or exists(
         select 1 from private.ops_links l
         where l.organization_id=o and l.team_id=t.id and l.approved
       ))
   )
 );
$function$
;
