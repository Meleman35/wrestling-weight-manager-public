-- Production function/trigger definitions inspected 2026-09-30; synthetic rows only.
CREATE OR REPLACE FUNCTION public.is_org_admin(check_org_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.organization_memberships om
    where om.organization_id = check_org_id
      and om.user_id = auth.uid()
      and om.role = 'organization_admin'
  );
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION private.wrestling_role_invalidate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare src text; oldj jsonb:=to_jsonb(old); newj jsonb:=to_jsonb(new);
begin
 src:=case when tg_table_name='team_memberships' then 'team' else 'organization' end;
 if tg_op='DELETE' or (oldj-array['notifications_paused']) is distinct from (newj-array['notifications_paused']) then
 insert into private.wrestling_role_review_log(source,membership_id,snapshot,reviewer_id,action)
 select source,membership_id,snapshot,auth.uid(),'assignment_changed' from private.wrestling_role_approvals where source=src and membership_id=old.id;
 delete from private.wrestling_role_approvals where source=src and membership_id=old.id;
 end if;
 return null;
end $function$
;
CREATE TRIGGER wrestling_team_role_changed AFTER DELETE OR UPDATE ON public.team_memberships FOR EACH ROW EXECUTE FUNCTION private.wrestling_role_invalidate();

CREATE TRIGGER wrestling_org_role_changed AFTER DELETE OR UPDATE ON public.organization_memberships FOR EACH ROW EXECUTE FUNCTION private.wrestling_role_invalidate();

