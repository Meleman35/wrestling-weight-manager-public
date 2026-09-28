-- Email authentication secrets never return to the inviting coach or athlete.
-- This endpoint resolves the bound recipient and verifies live invitation authority.
create table private.invitation_email_attempts(
 invitation_id uuid primary key, attempted_at timestamptz not null default now(),
 requested_by uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null unique
);
alter table private.invitation_email_attempts enable row level security;
revoke all on private.invitation_email_attempts from public,anon,authenticated;
create function private.invitation_email_context(p_token text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();inv record;result jsonb;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use a personal account to send invitations';end if;
 if p_request_id is null or p_token is null or p_token !~ '^WMW[AG]-[a-f0-9]{48}$' then raise exception 'Invalid invitation';end if;
 if p_token like 'WMWA-%' then
  select i.id,i.athlete_id,i.team_id,i.email,i.created_by,i.expires_at,concat_ws(' ',a.first_name,a.last_name) as name,'athlete'::text as role
   into inv from public.athlete_claim_invitations i join public.athletes a on a.id=i.athlete_id
   where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.status='pending' and (i.expires_at is null or i.expires_at>now());
  if inv.id is null or not public.is_team_staff(inv.team_id) or not public.can_manage_athlete(inv.athlete_id) then raise exception 'Invitation is unavailable or not authorized';end if;
 else
  select i.id,i.athlete_id,i.team_id,i.email,i.created_by,i.expires_at,i.name,'parent_guardian'::text as role
   into inv from public.guardian_invitations i
   where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.status='pending' and (i.expires_at is null or i.expires_at>now());
  if inv.id is null or not(public.is_team_staff(inv.team_id) or (inv.created_by=uid and public.is_self_athlete(inv.athlete_id))) then raise exception 'Invitation is unavailable or not authorized';end if;
 end if;
 if not public.athlete_on_team(inv.athlete_id,inv.team_id) then raise exception 'Athlete is no longer on this team';end if;
 if nullif(trim(inv.email),'') is null then raise exception 'Add an email address to this invitation first';end if;
 if exists(select 1 from auth.users u join private.team_logins t on t.user_id=u.id where lower(u.email)=lower(inv.email)) then raise exception 'Invite a personal email address';end if;
 if exists(select 1 from public.team_communication_settings where team_id=inv.team_id and email_enabled=false) then raise exception 'Email sending is disabled for this team';end if;
 -- An atomic cooldown also prevents double taps from sending twice.
 insert into private.invitation_email_attempts(invitation_id,requested_by,request_id) values(inv.id,uid,p_request_id)
 on conflict(invitation_id) do update set attempted_at=now(),requested_by=uid,request_id=p_request_id
 where private.invitation_email_attempts.attempted_at<now()-interval '60 seconds'
   and private.invitation_email_attempts.request_id<>p_request_id;
 if not found then raise exception 'This invitation was just submitted. Wait a minute before sending another email';end if;
 select jsonb_build_object('id',inv.id,'email',lower(trim(inv.email)),'name',inv.name,'role',inv.role,'team_id',inv.team_id,'team_name',name,'request_id',p_request_id) into result from public.teams where id=inv.team_id;
 return result;
end $$;
revoke all on function private.invitation_email_context(text,uuid) from public,anon;
grant execute on function private.invitation_email_context(text,uuid) to authenticated;
create function public.invitation_email_context(p_token text,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.invitation_email_context(p_token,p_request_id)$$;
revoke all on function public.invitation_email_context(text,uuid) from public,anon;
grant execute on function public.invitation_email_context(text,uuid) to authenticated;

create function private.accept_athlete_email_invitation(p_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();v_email text;inv public.athlete_claim_invitations%rowtype;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use a personal account';end if;
 select lower(u.email) into v_email from auth.users u where u.id=uid and u.email_confirmed_at is not null;
 select * into inv from public.athlete_claim_invitations where id=p_id for update;
 if inv.id is null or v_email is null or v_email<>lower(inv.email) then raise exception 'Confirm the email address this invitation was sent to';end if;
 if inv.status='accepted' and exists(select 1 from public.team_memberships where team_id=inv.team_id and athlete_id=inv.athlete_id and user_id=uid and role='athlete' and active) then return inv.athlete_id;end if;
 if inv.status<>'pending' or inv.expires_at<=now() or not public.athlete_on_team(inv.athlete_id,inv.team_id) then raise exception 'Invitation is no longer available';end if;
 -- Lock the athlete too: two different invites cannot claim it concurrently.
 perform 1 from public.athletes where id=inv.athlete_id for update;
 if exists(select 1 from public.team_memberships where team_id=inv.team_id and athlete_id=inv.athlete_id and role='athlete' and user_id<>uid) then raise exception 'This athlete is already connected to another account. Ask your coach for help';end if;
 insert into public.team_memberships(team_id,user_id,role,athlete_id) values(inv.team_id,uid,'athlete',inv.athlete_id) on conflict do nothing;
 update public.athlete_claim_invitations set status='accepted' where id=p_id;
 update public.athletes set email=coalesce(public.athletes.email,inv.email) where id=inv.athlete_id;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(uid,'claim_athlete_profile','athlete',inv.athlete_id,jsonb_build_object('team_id',inv.team_id));
 return inv.athlete_id;
end $$;
revoke all on function private.accept_athlete_email_invitation(uuid) from public,anon,authenticated;
create function private.accept_athlete_claim_invitation(p_invitation_token text)
returns uuid language plpgsql security definer set search_path='' as $$
declare invitation_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first';end if;
 select id into invitation_id from public.athlete_claim_invitations where token_hash=encode(extensions.digest(p_invitation_token,'sha256'),'hex');
 return private.accept_athlete_email_invitation(invitation_id);
end $$;

revoke all on function private.accept_athlete_claim_invitation(text) from public,anon;
grant execute on function private.accept_athlete_claim_invitation(text) to authenticated;
create or replace function public.accept_athlete_claim_invitation(p_invitation_token text)
returns uuid language sql security invoker set search_path='' as $$select private.accept_athlete_claim_invitation(p_invitation_token)$$;
revoke all on function public.accept_athlete_claim_invitation(text) from public,anon;
grant execute on function public.accept_athlete_claim_invitation(text) to authenticated;

create function private.accept_verified_email_invitations()
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();v_email text;r record;n integer=0;skipped integer=0;guardians integer=0;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use your personal account';end if;
 select lower(u.email) into v_email from auth.users u where u.id=uid and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Confirm your email before joining your team';end if;
 guardians:=public.accept_matching_guardian_invitations();
 for r in select id from public.athlete_claim_invitations i where lower(i.email)=v_email and status='pending' and (expires_at is null or expires_at>now()) and public.athlete_on_team(athlete_id,team_id) order by created_at,id limit 20
 loop
  begin perform private.accept_athlete_email_invitation(r.id);n:=n+1;exception when others then skipped:=skipped+1;end;
 end loop;
 return jsonb_build_object('athletes',n,'guardians',guardians,'needs_help',skipped);
end $$;
revoke all on function private.accept_verified_email_invitations() from public,anon;
grant execute on function private.accept_verified_email_invitations() to authenticated;
create function public.accept_verified_email_invitations()
returns jsonb language sql security invoker set search_path='' as $$select private.accept_verified_email_invitations()$$;
revoke all on function public.accept_verified_email_invitations() from public,anon;
grant execute on function public.accept_verified_email_invitations() to authenticated;
