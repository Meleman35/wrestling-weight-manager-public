-- Read-only, privately enrolled phone test. This does not install/enable erasure.
begin;
create table private.account_deletion_phone_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table private.account_deletion_phone_testers enable row level security;
revoke all on private.account_deletion_phone_testers from public, anon, authenticated;
grant select, insert, update, delete on private.account_deletion_phone_testers to service_role;

create function private.account_deletion_phone_preflight()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_claims jsonb := auth.jwt();
  v_session uuid;
  v_exp numeric;
  v_sole_teams bigint;
begin
  if v_uid is null or v_claims->>'role' is distinct from 'authenticated'
     or v_claims->>'sub' is distinct from v_uid::text then
    return jsonb_build_object('enabled',false);
  end if;
  begin
    v_session := (v_claims->>'session_id')::uuid;
    v_exp := (v_claims->>'exp')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('enabled',false);
  end;
  if v_exp is null or v_exp <= extract(epoch from now()) or v_exp = 'NaN'::numeric
     or v_exp = 'Infinity'::numeric or v_session is null then
    return jsonb_build_object('enabled',false);
  end if;
  if not exists (
    select 1 from private.account_deletion_phone_testers t
    join auth.users u on u.id=t.user_id
    join auth.sessions s on s.user_id=u.id and s.id=v_session
    where t.user_id=v_uid and t.expires_at>now()
      and u.email_confirmed_at is not null and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now())
      and (s.not_after is null or s.not_after>now())
  ) or exists (select 1 from private.team_logins where user_id=v_uid) then
    return jsonb_build_object('enabled',false);
  end if;

  -- Mirror current team-admin roles, including organization authority. A count
  -- is a handoff warning, not permission to delete the team or linked children.
  select count(*) into v_sole_teams from public.teams t
  where (
    exists (select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=v_uid
      and m.active and (m.role='head_coach' or (m.role in ('assistant_coach','manager')
        and coalesce((m.permissions->>'team_admin')::boolean,false))))
    or exists (select 1 from public.organization_memberships m where m.organization_id=t.organization_id
      and m.user_id=v_uid and m.role='organization_admin')
  ) and not exists (
    select 1 from public.team_memberships m join auth.users u on u.id=m.user_id
    where m.team_id=t.id and m.user_id<>v_uid and m.active
      and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
      and (m.role='head_coach' or (m.role in ('assistant_coach','manager')
        and coalesce((m.permissions->>'team_admin')::boolean,false)))
  ) and not exists (
    select 1 from public.organization_memberships m join auth.users u on u.id=m.user_id
    where m.organization_id=t.organization_id and m.user_id<>v_uid and m.role='organization_admin'
      and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
  );

  return jsonb_build_object(
    'enabled',true,'deletion_enabled',false,'subject_id',v_uid,'checked_at',now(),
    'counts',jsonb_build_object(
      'account_photos',(select count(*) from public.profiles where id=v_uid and nullif(photo_path,'') is not null),
      'wrestling_profile_photos',(select count(*) from private.wrestling_profiles where user_id=v_uid and nullif(photo_path,'') is not null),
      'messages',(select count(*) from public.communication_messages where sender_user_id=v_uid),
      'message_attachments',(select count(*) from public.communication_attachments where uploader_user_id=v_uid),
      'team_posts',(select count(*) from public.team_posts where author_user_id=v_uid),
      'post_attachments',(select count(*) from public.team_post_attachments a join public.team_posts p on p.id=a.post_id where p.author_user_id=v_uid),
      'teams',(select count(*) from public.team_memberships where user_id=v_uid),
      'teams_needing_handoff',v_sole_teams,
      'guardian_links',(select count(*) from public.athlete_guardians where guardian_user_id=v_uid),
      'organization_roles',(select count(*) from public.organization_memberships where user_id=v_uid),
      'uploaded_objects',(select count(*) from storage.objects where owner=v_uid or owner_id=v_uid::text)
    )
  );
end $$;
revoke all on function private.account_deletion_phone_preflight() from public, anon, authenticated;
grant execute on function private.account_deletion_phone_preflight() to authenticated;

create function public.account_deletion_phone_preflight()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.account_deletion_phone_preflight();
$$;
revoke all on function public.account_deletion_phone_preflight() from public, anon, authenticated;
grant execute on function public.account_deletion_phone_preflight() to authenticated;
comment on function public.account_deletion_phone_preflight() is
  'Privately enrolled current-account counts only. No deletion request, worker, or erasure operation.';
notify pgrst, 'reload schema';
commit;
