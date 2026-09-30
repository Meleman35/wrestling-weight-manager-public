CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
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
CREATE OR REPLACE FUNCTION private.wrestling_role_guardian_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op='DELETE' or old.guardian_user_id is distinct from new.guardian_user_id or old.athlete_id is distinct from new.athlete_id then
 insert into private.wrestling_role_review_log(source,membership_id,snapshot,reviewer_id,action)
 select source,membership_id,snapshot,auth.uid(),'guardian_link_changed' from private.wrestling_role_approvals
 where snapshot->>'user'=old.guardian_user_id::text and snapshot->>'athlete'=old.athlete_id::text and snapshot->>'role'='parent_guardian';
 delete from private.wrestling_role_approvals where snapshot->>'user'=old.guardian_user_id::text and snapshot->>'athlete'=old.athlete_id::text and snapshot->>'role'='parent_guardian';
 end if;
 return null;
end $function$
;
CREATE OR REPLACE FUNCTION private.communication_audit_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='INSERT' then
    insert into public.communication_message_audit(message_id,thread_id,team_id,actor_user_id,event_type,body_snapshot)
    values(new.id,new.thread_id,new.team_id,coalesce((select auth.uid()),new.sender_user_id),'created',new.body);
  elsif new.deleted_at is distinct from old.deleted_at and new.deleted_at is not null then
    insert into public.communication_message_audit(message_id,thread_id,team_id,actor_user_id,event_type,body_snapshot)
    values(new.id,new.thread_id,new.team_id,coalesce((select auth.uid()),new.deleted_by),'removed',old.body);
  elsif new.body is distinct from old.body then
    insert into public.communication_message_audit(message_id,thread_id,team_id,actor_user_id,event_type,body_snapshot)
    values(new.id,new.thread_id,new.team_id,(select auth.uid()),'edited',old.body);
  end if;
  return new;
end;
$function$
;
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER athletes_set_updated_at BEFORE UPDATE ON public.athletes FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER roster_set_updated_at BEFORE UPDATE ON public.roster_memberships FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER challenge_rules_set_updated_at BEFORE UPDATE ON public.team_challenge_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER communication_message_audit_trigger AFTER INSERT OR UPDATE ON public.communication_messages FOR EACH ROW EXECUTE FUNCTION private.communication_audit_message();
CREATE TRIGGER wrestling_team_role_changed AFTER DELETE OR UPDATE ON public.team_memberships FOR EACH ROW EXECUTE FUNCTION private.wrestling_role_invalidate();
CREATE TRIGGER wrestling_org_role_changed AFTER DELETE OR UPDATE ON public.organization_memberships FOR EACH ROW EXECUTE FUNCTION private.wrestling_role_invalidate();
CREATE TRIGGER wrestling_role_guardian_link_changed AFTER DELETE OR UPDATE ON public.athlete_guardians FOR EACH ROW EXECUTE FUNCTION private.wrestling_role_guardian_change();