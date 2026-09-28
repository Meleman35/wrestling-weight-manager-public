-- Display names follow a personal account and its shared wrestling profiles.
-- Roster first/last names remain the existing athlete identity fields.
create or replace function private.sync_account_display_name()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.display_name is null or length(trim(new.display_name)) not between 1 and 120
     or exists(select 1 from private.team_logins where user_id=new.id) then return new; end if;
  update private.wrestling_profiles w set name=trim(new.display_name),updated_at=now()
  where w.name is distinct from trim(new.display_name) and
    (w.user_id=new.id or exists(
      select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
      where m.user_id=new.id and m.role='athlete' and m.active and a.profile_id=w.athlete_profile_id
    ));
  return new;
end $$;
revoke all on function private.sync_account_display_name() from public,anon,authenticated;
create trigger account_display_name_sync after update of display_name on public.profiles
for each row when (old.display_name is distinct from new.display_name)
execute function private.sync_account_display_name();

create or replace function private.sync_wrestling_display_name()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Only athlete memberships identify the child account. Guardian accounts keep their own names.
  update public.profiles p set display_name=new.name,updated_at=now()
  where p.display_name is distinct from new.name
    and not exists(select 1 from private.team_logins where user_id=p.id)
    and (p.id=new.user_id or exists(
      select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
      where m.user_id=p.id and m.role='athlete' and m.active and a.profile_id=new.athlete_profile_id
    ));
  return new;
end $$;
revoke all on function private.sync_wrestling_display_name() from public,anon,authenticated;
create trigger wrestling_display_name_sync after update of name on private.wrestling_profiles
for each row when (old.name is distinct from new.name)
execute function private.sync_wrestling_display_name();

-- A separate name-only endpoint lets minor athletes correct their own display name
-- without receiving permission to change parent-controlled discovery or sharing.
create or replace function private.update_profile_name(p_profile_id uuid,p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid=auth.uid(); clean_name text=trim(p_name);
begin
  if uid is null or exists(select 1 from private.team_logins where user_id=uid) then
    raise exception 'Use your personal account to edit your name';
  end if;
  if clean_name is null or length(clean_name) not between 1 and 120 then
    raise exception 'Enter a name between 1 and 120 characters';
  end if;
  if not (private.wrestling_profile_self(p_profile_id) or private.wrestling_profile_manager(p_profile_id)) then
    raise exception 'You can edit your own name or a child profile you manage';
  end if;
  update private.wrestling_profiles set name=clean_name,updated_at=now() where id=p_profile_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id)
    values(uid,'update_profile_name','wrestling_profile',p_profile_id);
  return jsonb_build_object('id',p_profile_id,'name',clean_name);
end $$;
revoke all on function private.update_profile_name(uuid,text) from public,anon;
grant execute on function private.update_profile_name(uuid,text) to authenticated;

create or replace function public.update_profile_name(p_profile_id uuid,p_name text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.update_profile_name(p_profile_id,p_name)
$$;
revoke all on function public.update_profile_name(uuid,text) from public,anon;
grant execute on function public.update_profile_name(uuid,text) to authenticated;
