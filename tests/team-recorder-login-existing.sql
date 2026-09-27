-- Existing production login-session functions, frozen for regression tests.
CREATE OR REPLACE FUNCTION private.managed_login_access_ok()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a private.team_logins%rowtype; sid uuid;
begin
  select * into a from private.team_logins where user_id=(select auth.uid());
  if not found then return true; end if;
  if a.kind='shared' or not a.active or a.state<>'ready' then return false; end if;
  begin sid:=(auth.jwt()->>'session_id')::uuid; exception when others then return false; end;
  return exists(select 1 from private.team_login_sessions ms join auth.sessions s on s.id=ms.session_id
    where ms.session_id=sid and ms.login_id=a.id and ms.revision=a.revision and s.user_id=a.user_id and (a.parent_id is null or exists(
      select 1 from private.team_login_devices d join private.team_logins parent on parent.id=d.parent_id
      join auth.sessions credential on credential.id=d.credential_session_id
      where d.id=ms.device_id and d.current_session_id=sid and d.parent_id=a.parent_id
        and parent.active and parent.state='ready' and parent.revision=d.revision and credential.user_id=parent.user_id)));
end $function$
;
CREATE OR REPLACE FUNCTION private.register_team_login_session(p_id uuid, p_user uuid, p_session uuid, p_revision integer, p_code text, p_username text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a private.team_logins%rowtype;
begin
 select * into a from private.team_logins where id=p_id for update;
 if not found or a.parent_id is not null or a.kind='shared' or a.user_id<>p_user or not a.active or a.state<>'ready' or a.revision<>p_revision
   or a.username<>lower(trim(p_username)) or not exists(select 1 from private.team_login_settings where team_id=a.team_id and login_code=upper(trim(p_code)))
   or not exists(select 1 from auth.sessions where id=p_session and user_id=p_user) then return false; end if;
 insert into private.team_login_sessions(session_id,login_id,revision) values(p_session,a.id,a.revision) on conflict(session_id) do nothing;
 delete from private.team_login_attempts where bucket='user:'||encode(extensions.digest(upper(trim(p_code))||':'||lower(trim(p_username)),'sha256'),'hex');
 return true;
end $function$
;