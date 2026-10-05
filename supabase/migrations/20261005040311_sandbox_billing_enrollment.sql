-- Narrow sandbox enrollment check. No user is enrolled by this migration.
begin;
do $$begin
 if not wm_billing.notification_deployment_ready() then raise exception 'BILLING_SANDBOX_REVIEW_REQUIRED';end if;
end $$;
create function wm_billing.sandbox_team_enrolled(p_team uuid default null) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare enrollment jsonb; expires numeric; actor uuid:=auth.uid();
begin
 if actor is null or not private.board_personal(actor) or not private.scoped_deletion_access_ok() then return false;end if;
 select raw_app_meta_data->'wm_billing_sandbox' into enrollment from auth.users where id=actor;
 if jsonb_typeof(enrollment) is distinct from 'object' or jsonb_typeof(enrollment->'team_ids') is distinct from 'array'
  or jsonb_typeof(enrollment->'expires_at') is distinct from 'number' or (enrollment->>'expires_at')!~'^[0-9]{1,16}$'
 then return false;end if;
 expires:=(enrollment->>'expires_at')::numeric;
 if expires>9007199254740991 or expires<=floor(extract(epoch from clock_timestamp())*1000) then return false;end if;
 return exists(select 1 from public.teams t where (p_team is null or t.id=p_team)
  and enrollment->'team_ids' @> jsonb_build_array(t.id::text)
  and (public.is_team_staff(t.id) or exists(select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=actor and m.active))
  and not exists(select 1 from private.scoped_deletion_jobs j where j.state not in ('completed','cancelled')
   and (j.actor_id=actor or t.id=any(j.team_ids) or t.organization_id=any(j.organization_ids))));
end $$;
revoke all on function wm_billing.sandbox_team_enrolled(uuid) from public,anon,authenticated,service_role;
grant execute on function wm_billing.sandbox_team_enrolled(uuid) to wm_billing_runtime;
commit;
