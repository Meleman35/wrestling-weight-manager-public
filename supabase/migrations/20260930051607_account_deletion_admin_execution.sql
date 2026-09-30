-- The administrator choice changes only the caller's role. It never erases an identity.
-- Personal/workspace/combined erasure remains unavailable; enrollment is still required.
begin;
create table private.account_admin_removal_receipts (
  actor_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  target_kind text not null check (target_kind in ('team','organization')),
  target_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id,request_id)
);
alter table private.account_admin_removal_receipts enable row level security;
revoke all on private.account_admin_removal_receipts from public,anon,authenticated;
grant select,delete on private.account_admin_removal_receipts to service_role;

create function private.account_remove_my_admin_access(
  p_target_kind text,p_target_id uuid,p_confirmation text,p_request_id uuid
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  v_actor uuid:=auth.uid(); v_base jsonb; v_result jsonb;
  v_receipt private.account_admin_removal_receipts%rowtype;
  v_team public.teams%rowtype; v_role text; v_inherited boolean:=false;
begin
  if p_confirmation is distinct from 'delete' or p_target_id is null or p_request_id is null
     or p_target_kind is null or p_target_kind not in ('team','organization') then
    raise sqlstate '22023' using message='ADMIN_REMOVAL_INVALID_CONFIRMATION';
  end if;
  -- Serialize membership changes, including ordinary admin edits, before rechecking
  -- authority and continuity. Row locks alone would miss newly inserted memberships.
  lock table public.team_memberships,public.organization_memberships in share row exclusive mode;
  lock table private.team_logins in share mode;
  v_base:=private.account_deletion_phone_preflight();
  if v_base->>'enabled' is distinct from 'true' then
    raise sqlstate '42501' using message='ADMIN_REMOVAL_SIGN_IN_REQUIRED';
  end if;
  select * into v_receipt from private.account_admin_removal_receipts
    where actor_id=v_actor and request_id=p_request_id;
  if found then
    if v_receipt.target_kind<>p_target_kind or v_receipt.target_id<>p_target_id then
      raise sqlstate '22023' using message='ADMIN_REMOVAL_REQUEST_MISMATCH';
    end if;
    return v_receipt.result;
  end if;
  if p_target_kind='team' then
    select * into v_team from public.teams where id=p_target_id for share;
    if not found then raise sqlstate '42501' using message='ADMIN_REMOVAL_ROLE_CHANGED'; end if;
    select role into v_role from public.team_memberships m
      where m.team_id=p_target_id and m.user_id=v_actor and m.active
      and (m.role='head_coach' or (m.role in ('assistant_coach','manager')
        and coalesce((m.permissions->>'team_admin')::boolean,false)))
      order by case when m.role='head_coach' then 0 else 1 end,m.role limit 1;
    if not found then raise sqlstate '42501' using message='ADMIN_REMOVAL_ROLE_CHANGED'; end if;
    -- Lock eligible identities against concurrent banning/deletion until commit.
    perform u.id from auth.users u where u.id=v_actor or exists (
      select 1 from public.team_memberships m where m.team_id=p_target_id and m.user_id=u.id
    ) or exists (
      select 1 from public.organization_memberships m where m.organization_id=v_team.organization_id and m.user_id=u.id
    ) order by u.id for share;
    v_inherited:=exists(select 1 from public.organization_memberships m
      where m.organization_id=v_team.organization_id and m.user_id=v_actor and m.role='organization_admin');
    if not v_inherited and not exists(
      select 1 from auth.users u where u.id<>v_actor and u.email_confirmed_at is not null
      and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
      and not exists(select 1 from private.team_logins l where l.user_id=u.id)
      and (exists(select 1 from public.team_memberships m where m.user_id=u.id and m.team_id=p_target_id and m.active
        and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false))))
        or exists(select 1 from public.organization_memberships m where m.user_id=u.id
          and m.organization_id=v_team.organization_id and m.role='organization_admin'))
    ) then raise sqlstate 'P0001' using message='ADMIN_REMOVAL_HANDOFF_REQUIRED'; end if;
    if private.account_deletion_phone_preflight()->>'enabled' is distinct from 'true' then
      raise sqlstate '42501' using message='ADMIN_REMOVAL_SIGN_IN_REQUIRED';
    end if;
    -- Multiple roles per person are allowed. Keep existing athlete/guardian rows,
    -- and avoid colliding with an already-held assistant-coach membership.
    delete from public.team_memberships h where h.team_id=p_target_id and h.user_id=v_actor
      and h.active and h.role='head_coach' and exists (
        select 1 from public.team_memberships a where a.team_id=h.team_id and a.user_id=h.user_id
          and a.role='assistant_coach' and a.athlete_id is not distinct from h.athlete_id and a.active
      );
    -- An inactive assistant row would conflict with demotion; preserve it and stop
    -- for a reviewed membership change instead of silently reactivating it.
    if exists(select 1 from public.team_memberships h join public.team_memberships a
      on a.team_id=h.team_id and a.user_id=h.user_id and a.athlete_id is not distinct from h.athlete_id
      where h.team_id=p_target_id and h.user_id=v_actor and h.active and h.role='head_coach'
        and a.role='assistant_coach' and not a.active) then
      raise sqlstate 'P0001' using message='ADMIN_REMOVAL_MEMBERSHIP_REVIEW';
    end if;
    update public.team_memberships set role='assistant_coach'
      where team_id=p_target_id and user_id=v_actor and active and role='head_coach';
    update public.team_memberships set permissions=coalesce(permissions,'{}'::jsonb)-'team_admin'
      where team_id=p_target_id and user_id=v_actor and active and role in ('assistant_coach','manager')
        and coalesce((permissions->>'team_admin')::boolean,false);
    v_result:=jsonb_build_object('status','removed','request_id',p_request_id,'target_kind','team',
      'target_id',p_target_id,'personal_account_preserved',true,'inherited_admin_remaining',v_inherited,
      'participation_role',case when v_role='head_coach' then 'assistant_coach' else v_role end);
  else
    perform id from public.organizations where id=p_target_id for share;
    if not found or not exists(select 1 from public.organization_memberships m
      where m.organization_id=p_target_id and m.user_id=v_actor and m.role='organization_admin') then
      raise sqlstate '42501' using message='ADMIN_REMOVAL_ROLE_CHANGED';
    end if;
    perform u.id from auth.users u where u.id=v_actor or exists (
      select 1 from public.organization_memberships m where m.organization_id=p_target_id and m.user_id=u.id
    ) order by u.id for share;
    if not exists(select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id
      where m.organization_id=p_target_id and m.user_id<>v_actor and m.role='organization_admin'
      and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
      and not exists(select 1 from private.team_logins l where l.user_id=u.id)) then
      raise sqlstate 'P0001' using message='ADMIN_REMOVAL_HANDOFF_REQUIRED';
    end if;
    -- An organization admin has no generic non-admin organization role. Remove
    -- this assignment, preserving every direct team membership and personal row.
    if private.account_deletion_phone_preflight()->>'enabled' is distinct from 'true' then
      raise sqlstate '42501' using message='ADMIN_REMOVAL_SIGN_IN_REQUIRED';
    end if;
    delete from public.organization_memberships where organization_id=p_target_id and user_id=v_actor and role='organization_admin';
    v_result:=jsonb_build_object('status','removed','request_id',p_request_id,'target_kind','organization',
      'target_id',p_target_id,'personal_account_preserved',true,'inherited_admin_remaining',false,
      'participation_role',null);
  end if;
  insert into private.account_admin_removal_receipts(actor_id,request_id,target_kind,target_id,result)
    values(v_actor,p_request_id,p_target_kind,p_target_id,v_result);
  return v_result;
end $$;
revoke all on function private.account_remove_my_admin_access(text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function private.account_remove_my_admin_access(text,uuid,text,uuid) to authenticated;
create function public.account_remove_my_admin_access(
  p_target_kind text,p_target_id uuid,p_confirmation text,p_request_id uuid
) returns jsonb language sql volatile security invoker set search_path='' as $$
  select private.account_remove_my_admin_access(p_target_kind,p_target_id,p_confirmation,p_request_id);
$$;
revoke all on function public.account_remove_my_admin_access(text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.account_remove_my_admin_access(text,uuid,text,uuid) to authenticated;

create or replace function public.account_deletion_scope_preflight()
returns jsonb language sql stable security invoker set search_path='' as $$
  select case when r->>'enabled'='true' then r || jsonb_build_object('actions',
    jsonb_build_object('administrator',true,'personal',false,'team',false,'organization',false,'all',false)) else r end
  from (select private.account_deletion_scope_preflight() r) s;
$$;
comment on function public.account_remove_my_admin_access(text,uuid,text,uuid) is
  'Enrolled caller-only role removal with locked continuity checks and idempotent receipts; no personal or workspace erasure.';
notify pgrst,'reload schema';
commit;
