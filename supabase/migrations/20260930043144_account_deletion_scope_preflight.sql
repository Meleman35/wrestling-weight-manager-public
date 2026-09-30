-- Separate personal identity, administrator roles and workspaces. No erasure RPC.
begin;
-- Organization deletion must not cascade through athletes or through every team.
-- A future reviewed workflow must preserve/rehome these rows before closure.
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.athletes'::regclass
      and conname='athletes_organization_id_fkey' and confrelid='public.organizations'::regclass and confdeltype='c')
     or not exists(select 1 from pg_constraint where conrelid='public.teams'::regclass
      and conname='teams_organization_id_fkey' and confrelid='public.organizations'::regclass and confdeltype='c') then
    raise exception 'Organization relationship definitions changed; review before installing preservation guards';
  end if;
end $$;
alter table public.athletes drop constraint athletes_organization_id_fkey,
  add constraint athletes_organization_id_fkey foreign key(organization_id) references public.organizations(id) on delete restrict;
alter table public.teams drop constraint teams_organization_id_fkey,
  add constraint teams_organization_id_fkey foreign key(organization_id) references public.organizations(id) on delete restrict;

create function private.account_deletion_scope_preflight()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_base jsonb := private.account_deletion_phone_preflight();
  v_uid uuid := auth.uid();
  v_teams jsonb;
  v_orgs jsonb;
begin
  -- Reuse the enrolled current-caller/live-session gate. Never accept target IDs.
  if v_base->>'enabled' is distinct from 'true' then return jsonb_build_object('enabled',false); end if;
  with admins as (
    select t.id,t.name,t.organization_id,
      exists(select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=v_uid and m.active
        and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false)))) as direct_admin,
      exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id
        and m.user_id=v_uid and m.role='organization_admin') as inherited_admin
    from public.teams t
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'direct_admin',t.direct_admin,'inherited_admin',t.inherited_admin,
    'needs_handoff',not exists(
      select 1 from public.team_memberships m join auth.users u on u.id=m.user_id
      where m.team_id=t.id and m.user_id<>v_uid and m.active
        and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
        and not exists(select 1 from private.team_logins l where l.user_id=u.id)
        and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and coalesce((m.permissions->>'team_admin')::boolean,false)))
    ) and not exists(
      select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id
      where m.organization_id=t.organization_id and m.user_id<>v_uid and m.role='organization_admin'
        and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
        and not exists(select 1 from private.team_logins l where l.user_id=u.id)
    )) order by t.name,t.id),'[]'::jsonb) into v_teams
    from admins t where t.direct_admin or t.inherited_admin;

  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,
    'team_count',(select count(*) from public.teams t where t.organization_id=o.id),
    'athlete_count',(select count(*) from public.athletes a where a.organization_id=o.id),
    'needs_handoff',not exists(
      select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id
      where m.organization_id=o.id and m.user_id<>v_uid and m.role='organization_admin'
        and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
        and not exists(select 1 from private.team_logins l where l.user_id=u.id)
    )) order by o.name,o.id),'[]'::jsonb) into v_orgs
    from public.organizations o where exists(select 1 from public.organization_memberships m
      where m.organization_id=o.id and m.user_id=v_uid and m.role='organization_admin');

  return v_base || jsonb_build_object('scope_version',1,'deletion_enabled',false,
    'scopes',jsonb_build_object('teams',v_teams,'organizations',v_orgs));
end $$;
revoke all on function private.account_deletion_scope_preflight() from public,anon,authenticated;
grant execute on function private.account_deletion_scope_preflight() to authenticated;
create function public.account_deletion_scope_preflight()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.account_deletion_scope_preflight();
$$;
revoke all on function public.account_deletion_scope_preflight() from public,anon,authenticated;
grant execute on function public.account_deletion_scope_preflight() to authenticated;
comment on function public.account_deletion_scope_preflight() is
  'Enrolled current-caller scope preview only; does not authorize, queue or perform any deletion.';
notify pgrst,'reload schema';
commit;
