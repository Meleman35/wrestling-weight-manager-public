-- Connect existing protected operations to verified private subscription state.
-- No purchase endpoint or billing write is enabled by this migration.
begin;
do $$begin
 if encode(sha256(convert_to(pg_get_functiondef('private.wrestler_statistics_covered(uuid)'::regprocedure),'UTF8')),'hex')<>'c586b05564582b0351607a37a057d4d5971da269ea5b6f78aead6b19b032a251'
  or encode(sha256(convert_to(pg_get_functiondef('private.practice_plans_covered(uuid)'::regprocedure),'UTF8')),'hex')<>'782de82a359dae4151101513b530ea1055609f3ae7c91df76ea473d41782b3ad'
  or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'TEAM_PRO_FEATURE_REVIEW_REQUIRED';end if;
end $$;

-- Sandbox evidence is usable only for an explicitly enrolled caller/team and
-- only until the server-managed enrollment expires. User metadata/JWT claims
-- cannot opt in. Production is always the default; no tester is enrolled here.
create function wm_billing.feature_environment(p_team uuid) returns text
language plpgsql stable security definer set search_path='' as $$
declare enrollment jsonb; expires numeric;
begin
 select raw_app_meta_data->'wm_billing_sandbox' into enrollment from auth.users where id=auth.uid();
 if jsonb_typeof(enrollment)='object' and jsonb_typeof(enrollment->'team_ids')='array'
  and jsonb_typeof(enrollment->'expires_at')='number' and (enrollment->>'expires_at')~'^[0-9]{1,16}$'
  and enrollment->'team_ids' @> jsonb_build_array(p_team::text) then
  expires:=(enrollment->>'expires_at')::numeric;
  if expires<=9007199254740991 and expires>floor(extract(epoch from now())*1000) then return 'Sandbox';end if;
 end if;
 return 'Production';
end $$;

create function wm_billing.team_snapshot_active(s jsonb,p_team uuid,p_environment text,p_now bigint) returns boolean
language plpgsql immutable set search_path='' as $$
declare boundary text; signed_at text;
begin
 if s is null or p_team is null or p_environment is null or p_environment not in ('Sandbox','Production') or p_now is null or p_now<0
  or s->>'teamID' is distinct from p_team::text or s->>'environment' is distinct from p_environment
  or s->>'plan' is null or s->>'plan' not in ('team_pro_year','team_pro_month')
  or s->>'revokedAt' is not null or jsonb_typeof(s->'status') is distinct from 'number' then return false;end if;
 signed_at:=s->>'snapshotSignedAt';
 if jsonb_typeof(s->'snapshotSignedAt') is distinct from 'number' or signed_at!~'^[0-9]{1,16}$'
  or signed_at::numeric>9007199254740991 or signed_at::numeric>p_now::numeric+60000 then return false;end if;
 if s->>'status'='1' then
  if jsonb_typeof(s->'expiresAt') is distinct from 'number' then return false;end if;
  boundary:=s->>'expiresAt';
 elsif s->>'status'='4' then
  if jsonb_typeof(s->'graceExpiresAt') is distinct from 'number' then return false;end if;
  boundary:=s->>'graceExpiresAt';
 else return false;end if;
 if boundary!~'^[0-9]{1,16}$' then return false;end if;
 return boundary::numeric<=9007199254740991 and boundary::numeric>p_now;
end $$;

create function wm_billing.team_feature_covered(p_team uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); v_environment text; current_ms bigint:=floor(extract(epoch from now())*1000);
begin
 -- Protected operation roles and athlete scope still run in their existing
 -- routers. This guard additionally requires the current live personal session.
 if actor is null or not private.board_personal(actor) or not private.scoped_deletion_access_ok()
  or not exists(select 1 from auth.users u join auth.sessions s on s.user_id=u.id
   and s.id::text=auth.jwt()->>'session_id' where u.id=actor and u.confirmed_at is not null
   and not coalesce(u.is_anonymous,false) and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now()) and (s.not_after is null or s.not_after>now()))
  or not exists(select 1 from public.teams t where t.id=p_team and not exists(
   select 1 from private.scoped_deletion_jobs j where j.state not in ('cancelled','completed')
    and (j.actor_id=actor or t.id=any(j.team_ids) or t.organization_id=any(j.organization_ids))))
 then return false;end if;
 v_environment:=wm_billing.feature_environment(p_team);
 return exists(select 1 from wm_billing.subscriptions b join auth.users u on u.id=b.user_id
  where b.scope='team' and b.team_id=p_team and b.environment=v_environment
   and u.confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now()) and private.board_personal(u.id)
   and not exists(select 1 from private.scoped_deletion_jobs j where
    (j.actor_id=u.id and j.state not in ('cancelled','completed')) or
    (j.personal and j.sealed_at is not null and j.subject_hash=encode(sha256(convert_to(u.id::text,'UTF8')),'hex')))
   and wm_billing.team_snapshot_active(b.snapshot,p_team,v_environment,current_ms))
  or (wm_billing.remaining_team_admin(p_team) and exists(select 1 from wm_billing.team_paid_remainders r
   where r.team_id=p_team and r.environment=v_environment and r.revoked_at is null and r.paid_through>current_ms));
end $$;
revoke all on function wm_billing.feature_environment(uuid),wm_billing.team_snapshot_active(jsonb,uuid,text,bigint),wm_billing.team_feature_covered(uuid) from public,anon,authenticated,wm_billing_runtime;

create or replace function private.wrestler_statistics_covered(p_team uuid) returns boolean
language sql stable set search_path='' as $$select wm_billing.team_feature_covered(p_team)$$;
-- Practice plans already delegate to the statistics coverage adapter. Keep the
-- existing practice and statistics request authorization code unchanged.
revoke all on function private.wrestler_statistics_covered(uuid) from public,anon,authenticated;
commit;
