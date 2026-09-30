-- Retire only a verified, tagged synthetic acceptance fixture. Never accepts an
-- arbitrary user, team, organization, file path or profile identifier.
begin;
create function private.scoped_deletion_acceptance_cleanup(p_action text,p_run uuid,p_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.scoped_deletion_acceptance_runs%rowtype;
begin
 if current_setting('role',true)<>'service_role' then raise sqlstate '42501' using message='SERVICE_ONLY';end if;
 select * into r from private.scoped_deletion_acceptance_runs where id=p_run and token_hash=p_hash and expires_at>now() and state='verified' for update;
 if not found or r.result->>'other_profiles_preserved' is distinct from 'true' then raise exception 'VERIFIED_FIXTURE_REQUIRED';end if;
 if p_action='context' then
  if (select count(*) from auth.users where id=any(array[r.retained_id,r.child_id]) and raw_app_meta_data->>'scoped_deletion_acceptance'=r.id::text and email like '%@tests.example.invalid')<>2 then raise exception 'FIXTURE_IDENTITY_CHANGED';end if;
  return jsonb_build_object('retained',r.retained_id,'child',r.child_id,'bucket','profile-photos','path',r.retained_id::text||'/'||r.id||'.jpg');
 elsif p_action='records' then
  if (select count(*) from auth.users where id=any(array[r.retained_id,r.child_id]) and raw_app_meta_data->>'scoped_deletion_acceptance'=r.id::text and email like '%@tests.example.invalid')<>2 then raise exception 'FIXTURE_IDENTITY_CHANGED';end if;
  if exists(select 1 from storage.objects where name like '%'||r.id::text||'%') then raise exception 'FIXTURE_FILE_REMAINS';end if;
  if exists(select 1 from public.team_memberships where team_id=r.other_team_id and user_id<>all(array[r.retained_id,r.child_id]))
    or exists(select 1 from public.organization_memberships where organization_id=r.other_organization_id and user_id<>r.retained_id)
    or exists(select 1 from public.team_memberships where athlete_id=r.athlete_id and team_id<>r.other_team_id)
    or exists(select 1 from public.athlete_guardians where athlete_id=r.athlete_id)
    or exists(select 1 from public.roster_memberships where athlete_id=r.athlete_id) then raise exception 'FIXTURE_HAS_UNEXPECTED_LINK';end if;
  delete from public.teams where id=r.other_team_id and organization_id=r.other_organization_id;
  delete from private.wrestling_profiles where athlete_profile_id=r.profile_id;
  delete from public.athletes where id=r.athlete_id and profile_id=r.profile_id and organization_id is null;
  delete from public.athlete_profiles where id=r.profile_id;
  delete from public.organizations where id=r.other_organization_id;
  return '{}';
 elsif p_action='complete' then
  if exists(select 1 from auth.users where id=any(array[r.actor_id,r.retained_id,r.child_id]))
    or exists(select 1 from public.profiles where id=any(array[r.actor_id,r.retained_id,r.child_id]))
    or exists(select 1 from public.teams where id=any(array[r.team_id,r.other_team_id]))
    or exists(select 1 from public.organizations where id=any(array[r.organization_id,r.other_organization_id]))
    or exists(select 1 from public.athlete_profiles where id=r.profile_id)
    or exists(select 1 from storage.objects where name like '%'||r.id::text||'%') then raise exception 'FIXTURE_CLEANUP_INCOMPLETE';end if;
  update private.scoped_deletion_acceptance_runs set state='cleaned',result=result||'{"fixtures_cleaned":true}'::jsonb,expires_at=now() where id=r.id;
  delete from vault.secrets where name='scoped-deletion-acceptance-'||r.id::text;
  return '{"cleaned":true}';
 end if;raise exception 'INVALID_FIXTURE_CLEANUP';
end $$;
create function public.scoped_deletion_acceptance_cleanup(p_action text,p_run uuid,p_hash text) returns jsonb
language sql security invoker set search_path='' as $$select private.scoped_deletion_acceptance_cleanup(p_action,p_run,p_hash)$$;
revoke all on function private.scoped_deletion_acceptance_cleanup(text,uuid,text),public.scoped_deletion_acceptance_cleanup(text,uuid,text) from public,anon,authenticated;
grant execute on function private.scoped_deletion_acceptance_cleanup(text,uuid,text),public.scoped_deletion_acceptance_cleanup(text,uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
