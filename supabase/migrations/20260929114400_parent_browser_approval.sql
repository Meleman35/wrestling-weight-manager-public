-- Browser permission delegation for verified teen guardians. Not COPPA consent.
-- Default off until server, email and browser checks pass. Existing controls win.
create table private.parent_browser_settings(id boolean primary key default true check(id), enabled boolean not null default false);
insert into private.parent_browser_settings default values;
create table private.parent_browser_verifications(
 guardian_id uuid primary key references public.athlete_guardians(id) on delete cascade,
 athlete_id uuid not null references public.athletes(id) on delete cascade,
 profile_id uuid not null references private.wrestling_profiles(id) on delete cascade,
 team_id uuid not null references public.teams(id) on delete cascade,
 email text not null, birth_date date not null,
 verified_by uuid not null references auth.users(id) on delete cascade,
 verified_at timestamptz not null default clock_timestamp()
);
create table private.parent_browser_permissions(
 guardian_id uuid primary key references public.athlete_guardians(id) on delete cascade,
 mode text not null check(mode in ('teen_managed','revoked')),
 review_photos boolean not null default true,
 verification_at timestamptz not null,
 notice_version text not null check(notice_version='teen-profile-v1'),
 acknowledged_at timestamptz not null default clock_timestamp(),
 receipt_id uuid not null default gen_random_uuid()
);
create table private.parent_browser_links(
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 guardian_id uuid not null references public.athlete_guardians(id) on delete cascade,
 invitation_id uuid references public.guardian_invitations(id) on delete cascade,
 email text not null, purpose text not null check(purpose in ('approval','manage')),
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null,
 used_at timestamptz, decision text check(decision in ('approve','revoke')),
 receipt jsonb, revoked_at timestamptz, join_attempted_at timestamptz
);
create index parent_browser_link_guardian on private.parent_browser_links(guardian_id);
create table private.parent_browser_recovery_attempts(email_hash text primary key, attempted_at timestamptz not null default clock_timestamp());
create table private.parent_browser_events(
 id uuid primary key default gen_random_uuid(),
 guardian_id uuid references public.athlete_guardians(id) on delete set null,
 event text not null check(event in ('verified','approved','revoked')),
 notice_version text not null default 'teen-profile-v1',
 created_at timestamptz not null default clock_timestamp(), details jsonb not null default '{}'
);
alter table private.parent_browser_settings enable row level security;
alter table private.parent_browser_verifications enable row level security;
alter table private.parent_browser_permissions enable row level security;
alter table private.parent_browser_links enable row level security;
alter table private.parent_browser_recovery_attempts enable row level security;
alter table private.parent_browser_events enable row level security;
revoke all on private.parent_browser_settings,private.parent_browser_verifications,private.parent_browser_permissions,
 private.parent_browser_links,private.parent_browser_recovery_attempts,private.parent_browser_events from public,anon,authenticated;

create function private.parent_browser_verification_valid(p_guardian uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.parent_browser_verifications v
 join public.athlete_guardians g on g.id=v.guardian_id and g.athlete_id=v.athlete_id
 join public.athletes a on a.id=v.athlete_id
 left join public.athlete_private_identity identity on identity.athlete_id=a.id
 join private.wrestling_profiles w on w.id=v.profile_id and w.athlete_profile_id=a.profile_id
 where v.guardian_id=p_guardian and lower(trim(g.email))=v.email
 and g.invitation_status is distinct from 'approval_pending'
 and coalesce(identity.birth_date,a.birth_date)=v.birth_date and coalesce(identity.birth_date,a.birth_date)<=current_date-interval '13 years'
 and coalesce(identity.birth_date,a.birth_date)>current_date-interval '18 years'
 and (exists(select 1 from public.team_memberships staff where staff.team_id=v.team_id and staff.user_id=v.verified_by
   and staff.active and (staff.role in ('head_coach','assistant_coach') or (staff.role='manager' and coalesce((staff.permissions->>'team_admin')::boolean,false))))
  or exists(select 1 from public.teams t join public.organization_memberships om on om.organization_id=t.organization_id
   where t.id=v.team_id and om.user_id=v.verified_by and om.role='organization_admin'))
 and public.athlete_on_team(v.athlete_id,v.team_id)
 and not exists(select 1 from private.team_logins tl where tl.user_id=v.verified_by)
 and not exists(select 1 from auth.users u join public.team_memberships m on m.user_id=u.id
   where m.athlete_id in(select linked.id from public.athletes linked where linked.profile_id=a.profile_id) and m.role='athlete' and m.active and lower(trim(u.email))=v.email))
$$;
revoke all on function private.parent_browser_verification_valid(uuid) from public,anon,authenticated;

create function private.parent_browser_verify(p_guardian uuid,p_team uuid,p_confirm boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g public.athlete_guardians%rowtype; a public.athletes%rowtype; pid uuid; stamp timestamptz; dob date;
begin
 if auth.uid() is null or exists(select 1 from private.team_logins where user_id=auth.uid())
   or not public.is_team_staff(p_team) then raise exception 'A coach must verify the guardian contact.' using errcode='42501';end if;
 if p_confirm is distinct from true then raise exception 'Confirm the guardian relationship, email and athlete birth date.';end if;
 select * into g from public.athlete_guardians where id=p_guardian;
 select * into a from public.athletes where id=g.athlete_id;
 select id into pid from private.wrestling_profiles where athlete_profile_id=a.profile_id;
 select coalesce((select birth_date from public.athlete_private_identity where athlete_id=a.id),a.birth_date) into dob;
 if g.id is null or not public.athlete_on_team(g.athlete_id,p_team) then raise exception 'Choose a guardian for an athlete on this team.';end if;
 if g.invitation_status='approval_pending' then raise exception 'Review and save this guardian relationship before verifying browser permission.';end if;
 if g.guardian_user_id is not null then raise exception 'This guardian already has an account. Use the existing Parent Controls.';end if;
 if g.email is null or g.email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Save the guardian email first.';end if;
 if pid is null then raise exception 'The athlete must open My Profile first.';end if;
 if dob is null or dob>current_date-interval '13 years' or dob<=current_date-interval '18 years' then
   raise exception 'Browser delegation is for athletes with a recorded age of 13–17. Check the athlete birth date.';end if;
 if exists(select 1 from auth.users u join public.team_memberships m on m.user_id=u.id where m.athlete_id in(select linked.id from public.athletes linked where linked.profile_id=a.profile_id) and m.role='athlete' and m.active and lower(trim(u.email))=lower(trim(g.email))) then
   raise exception 'Use the parent or guardian email, not the athlete email.';end if;
 perform 1 from private.wrestling_profiles where id=pid for update;
 stamp:=clock_timestamp();
 insert into private.parent_browser_verifications(guardian_id,athlete_id,profile_id,team_id,email,birth_date,verified_by,verified_at)
 values(g.id,a.id,pid,p_team,lower(trim(g.email)),dob,auth.uid(),stamp)
 on conflict(guardian_id) do update set athlete_id=excluded.athlete_id,profile_id=excluded.profile_id,team_id=excluded.team_id,
  email=excluded.email,birth_date=excluded.birth_date,verified_by=excluded.verified_by,verified_at=excluded.verified_at;
 -- Reverification requires new parent approval; prior receipts remain historical.
 update private.parent_browser_links set revoked_at=stamp where guardian_id=g.id and used_at is null;
 insert into private.parent_browser_events(guardian_id,event,details) values(g.id,'verified',jsonb_build_object('verified_by',auth.uid(),'team_id',p_team));
 return jsonb_build_object('verified',true,'guardian_id',g.id,'message','Contact verified. Create or resend the parent choices email.');
end $$;
revoke all on function private.parent_browser_verify(uuid,uuid,boolean) from public,anon;
grant execute on function private.parent_browser_verify(uuid,uuid,boolean) to authenticated;
create function public.parent_browser_verify(p_guardian uuid,p_team uuid,p_confirm boolean)
returns jsonb language sql security invoker set search_path='' as $$select private.parent_browser_verify(p_guardian,p_team,p_confirm)$$;
revoke all on function public.parent_browser_verify(uuid,uuid,boolean) from public,anon;
grant execute on function public.parent_browser_verify(uuid,uuid,boolean) to authenticated;

-- Server-only API. The Edge Function authenticates the unguessable emailed
-- capability; neither anon nor signed-in athletes can call this service RPC.
create function private.parent_browser_service(p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare inv public.guardian_invitations%rowtype; g public.athlete_guardians%rowtype;
 link private.parent_browser_links%rowtype; v private.parent_browser_verifications%rowtype;
 perm private.parent_browser_permissions%rowtype; hash text; email_value text; result jsonb;
 eligible boolean; aid uuid; pid uuid; used timestamptz;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service authentication required.' using errcode='42501';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'Invalid request.';end if;
 if not exists(select 1 from private.parent_browser_settings where id and enabled) then raise exception 'Parent browser choices are temporarily unavailable.';end if;
 if p_action='issue' then
  select * into inv from public.guardian_invitations where id=(p_data->>'invitation_id')::uuid;
  if inv.id is null or inv.status<>'pending' or inv.expires_at<=now() or not public.athlete_on_team(inv.athlete_id,inv.team_id)
    or not exists(select 1 from private.invitation_email_attempts x where x.invitation_id=inv.id and x.request_id=(p_data->>'request_id')::uuid and x.attempted_at>now()-interval '1 minute') then raise exception 'Invitation unavailable.';end if;
  select * into g from public.athlete_guardians where athlete_id=inv.athlete_id and lower(trim(email))=lower(trim(inv.email)) order by created_at,id limit 1;
  hash:=p_data->>'token_hash';
  if g.id is null or hash is null or hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid parent link.';end if;
  update private.parent_browser_links set revoked_at=clock_timestamp() where guardian_id=g.id and purpose='approval' and used_at is null;
  insert into private.parent_browser_links(token_hash,guardian_id,invitation_id,email,purpose,expires_at)
  values(hash,g.id,inv.id,lower(trim(inv.email)),'approval',least(inv.expires_at,now()+interval '7 days'));
  return jsonb_build_object('ok',true,'email',lower(trim(inv.email)));
 elsif p_action='recovery_context' then
  email_value:=lower(trim(coalesce(p_data->>'email','')));
  if length(email_value)>254 or email_value !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then return '[]'::jsonb;end if;
  hash:=encode(extensions.digest(email_value,'sha256'),'hex');
  -- Budget is global as well as per recipient; unknown email addresses are not stored.
  if (select count(*) from private.parent_browser_recovery_attempts where attempted_at>now()-interval '1 hour')>=100 then return '[]'::jsonb;end if;
  if not exists(select 1 from private.parent_browser_permissions p join public.athlete_guardians x on x.id=p.guardian_id where lower(trim(x.email))=email_value) then return '[]'::jsonb;end if;
  insert into private.parent_browser_recovery_attempts(email_hash) values(hash)
  on conflict(email_hash) do update set attempted_at=clock_timestamp()
  where private.parent_browser_recovery_attempts.attempted_at<now()-interval '1 hour';
  if not found then return '[]'::jsonb;end if;
  select coalesce(jsonb_agg(jsonb_build_object('guardian_id',x.id,'email',email_value)),'[]') into result
  from (select g2.id from public.athlete_guardians g2 join private.parent_browser_permissions p on p.guardian_id=g2.id
    where lower(trim(g2.email))=email_value order by g2.id limit 10) x;
  return result;
 elsif p_action='issue_management' then
  select * into g from public.athlete_guardians where id=(p_data->>'guardian_id')::uuid;
  hash:=p_data->>'token_hash';email_value:=lower(trim(g.email));
  if g.id is null or hash is null or hash !~ '^[a-f0-9]{64}$' or not exists(select 1 from private.parent_browser_permissions where guardian_id=g.id)
   or not exists(select 1 from private.parent_browser_recovery_attempts where email_hash=encode(extensions.digest(email_value,'sha256'),'hex') and attempted_at>now()-interval '1 minute') then raise exception 'Management link unavailable.';end if;
  insert into private.parent_browser_links(token_hash,guardian_id,email,purpose,expires_at) values(hash,g.id,email_value,'manage',now()+interval '1 hour');
  return jsonb_build_object('ok',true);
 end if;
 hash:=p_data->>'token_hash';
 if hash is null or hash !~ '^[a-f0-9]{64}$' then raise exception 'Open the newest private link from your email.';end if;
 select * into link from private.parent_browser_links where token_hash=hash;
 select * into g from public.athlete_guardians where id=link.guardian_id;
 if link.token_hash is null or link.revoked_at is not null or link.expires_at<=now() or lower(trim(g.email)) is distinct from link.email then raise exception 'This link is expired or replaced. Request a fresh management link below.';end if;
 select * into v from private.parent_browser_verifications where guardian_id=g.id;
 select * into perm from private.parent_browser_permissions where guardian_id=g.id;
 select * into inv from public.guardian_invitations where id=link.invitation_id;
 eligible:=link.purpose='approval' and inv.id is not null and inv.status='pending' and inv.expires_at>now()
   and public.athlete_on_team(inv.athlete_id,inv.team_id) and lower(trim(inv.email))=link.email
   and private.parent_browser_verification_valid(g.id)
   and g.guardian_user_id is null;
 -- An already linked parent retains their existing controls. External choices
 -- cannot override any account-linked guardian for this shared athlete profile.
 if eligible and exists(select 1 from public.athlete_guardians other_g join public.athletes a on a.id=other_g.athlete_id
    where a.profile_id=(select athlete_profile_id from private.wrestling_profiles where id=v.profile_id)
    and other_g.guardian_user_id is not null) then eligible:=false;end if;
 if p_action='preview' then
  return jsonb_build_object('athlete_name',(select first_name||' '||left(last_name,1)||'.' from public.athletes where id=g.athlete_id),
   'eligible',coalesce(eligible,false),'can_join',inv.id is not null and inv.status='pending' and inv.expires_at>now() and public.athlete_on_team(inv.athlete_id,inv.team_id) and lower(trim(inv.email))=link.email,
   'purpose',link.purpose,'used',link.used_at is not null,'receipt',link.receipt,
   'effective',coalesce((private.profile_approval_policy(v.profile_id)->>'auto_approve')::boolean,false) and private.profile_approval_policy(v.profile_id)->>'source'='parent_browser',
   'current_mode',perm.mode,'review_photos',coalesce(perm.review_photos,true),'notice_version','teen-profile-v1');
 elsif p_action='join' then
  if inv.id is null or inv.status<>'pending' or inv.expires_at<=now() or not public.athlete_on_team(inv.athlete_id,inv.team_id) or lower(trim(inv.email)) is distinct from link.email then raise exception 'Ask your coach for a new account invitation.';end if;
  update private.parent_browser_links set join_attempted_at=clock_timestamp() where token_hash=hash and (join_attempted_at is null or join_attempted_at<now()-interval '1 minute');
  if not found then raise exception 'Wait a minute before retrying sign-in.';end if;
  return jsonb_build_object('email',link.email,'name',g.name,'role','parent_guardian');
 elsif p_action in ('approve','revoke') then
  -- Match the publishing lock to make revocation effective against concurrent saves.
  if v.profile_id is not null then perform 1 from private.wrestling_profiles where id=v.profile_id for update;end if;
  select * into link from private.parent_browser_links where token_hash=hash for update;
  if link.revoked_at is not null or link.expires_at<=now() then raise exception 'Link expired or replaced.';end if;
  if link.used_at is not null then
   if link.decision=p_action then return link.receipt;end if;
   raise exception 'This link was already used. Request a fresh management link.';
  end if;
  if p_data->>'acknowledge' is distinct from 'true' or p_data->>'notice_version' is distinct from 'teen-profile-v1' then raise exception 'Review the choices and confirm you are the parent or legal guardian.';end if;
  if p_action='approve' then
   if not coalesce(eligible,false) or not private.parent_browser_verification_valid(g.id) then raise exception 'Coach verification and an eligible teen profile are required. Existing parent controls remain in place.';end if;
   if jsonb_typeof(p_data->'review_photos') is distinct from 'boolean' then raise exception 'Choose the photo permission.';end if;
   insert into private.parent_browser_permissions(guardian_id,mode,review_photos,verification_at,notice_version)
   values(g.id,'teen_managed',(p_data->>'review_photos')::boolean,v.verified_at,'teen-profile-v1')
   on conflict(guardian_id) do update set mode=excluded.mode,review_photos=excluded.review_photos,verification_at=excluded.verification_at,
    notice_version=excluded.notice_version,acknowledged_at=clock_timestamp(),receipt_id=gen_random_uuid() returning * into perm;
  else
   if link.purpose<>'manage' or perm.guardian_id is null then raise exception 'Use a fresh management link to withdraw permission.';end if;
   update private.parent_browser_permissions set mode='revoked',acknowledged_at=clock_timestamp(),receipt_id=gen_random_uuid()
   where guardian_id=g.id returning * into perm;
  end if;
  result:=jsonb_build_object('id',perm.receipt_id,'mode',perm.mode,'review_photos',perm.review_photos,'at',perm.acknowledged_at,'notice_version',perm.notice_version);
  update private.parent_browser_links set used_at=clock_timestamp(),decision=p_action,receipt=result where token_hash=hash;
  insert into private.parent_browser_events(guardian_id,event,details) values(g.id,case when p_action='approve' then 'approved' else 'revoked' end,result);
  return result;
 end if;
 raise exception 'Unsupported parent action.';
end $$;
revoke all on function private.parent_browser_service(text,jsonb) from public,anon,authenticated;
grant execute on function private.parent_browser_service(text,jsonb) to service_role;
create function public.parent_browser_service(p_action text,p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.parent_browser_service(p_action,p_data)$$;
revoke all on function public.parent_browser_service(text,jsonb) from public,anon,authenticated;
grant execute on function public.parent_browser_service(text,jsonb) to service_role;

CREATE OR REPLACE FUNCTION private.profile_approval_policy_before_browser(p_profile uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select jsonb_build_object('auto_approve',x.auto_approve,'review_photos',x.review_photos)
 from private.profile_approval_preferences x where x.profile_id=p_profile and exists(
  select 1 from private.wrestling_profiles w join public.athletes a on a.profile_id=w.athlete_profile_id
  join public.athlete_guardians g on g.athlete_id=a.id and g.guardian_user_id=x.updated_by
  join public.team_memberships m on m.athlete_id=a.id and m.user_id=g.guardian_user_id and m.role='parent_guardian' and m.active
  where w.id=p_profile and not exists(select 1 from private.team_logins tl where tl.user_id=x.updated_by)
 )), '{"auto_approve":false,"review_photos":true}'::jsonb)
$function$;

revoke all on function private.profile_approval_policy_before_browser(uuid) from public,anon,authenticated;

create or replace function private.profile_approval_policy(p_profile uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare original jsonb; choice jsonb;
begin
 original:=private.profile_approval_policy_before_browser(p_profile);
 if not exists(select 1 from private.parent_browser_settings where id and enabled)
  or exists(select 1 from private.wrestling_profiles w join public.athletes a on a.profile_id=w.athlete_profile_id
    join public.athlete_guardians g on g.athlete_id=a.id where w.id=p_profile and g.guardian_user_id is not null) then return original;end if;
 select jsonb_build_object('auto_approve',bool_and(p.mode='teen_managed'),'review_photos',bool_or(p.review_photos),'source','parent_browser')
 into choice from private.parent_browser_permissions p join private.parent_browser_verifications v on v.guardian_id=p.guardian_id
 where v.profile_id=p_profile and v.verified_at=p.verification_at and private.parent_browser_verification_valid(v.guardian_id);
 if choice->>'auto_approve' is null then return original;end if;
 return choice;
end $$;
revoke all on function private.profile_approval_policy(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.profile_request_can_auto_approve(p_request uuid, p_profile uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and private.wrestling_profile_self(p_profile)
 and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and exists(select 1 from private.profile_approval_requests r join private.wrestling_profiles w on w.id=r.profile_id
 where r.id=p_request and r.profile_id=p_profile and r.submitted_by=auth.uid() and r.status='pending'
 and private.profile_approval_policy(p_profile)->>'auto_approve'='true'
 and r.expected=private.profile_approval_snapshot(p_profile)
 and (coalesce(private.profile_approval_policy(p_profile)->>'source','')<>'parent_browser'
   or (not(r.proposal ? 'team_profile') and r.proposal->'sharing'=w.sharing and r.proposal->'discoverable'=to_jsonb(w.discoverable)))
 and r.proposal->>'name'=w.name
 and (not (r.proposal ? 'contact') or r.proposal->'contact'=private.profile_approval_contact(p_profile))
 and (r.path is null or private.profile_approval_policy(p_profile)->>'review_photos'='false'))
$function$;

-- Photo opt-in can finish without an account-linked notification recipient.
-- The same publishing check runs again after upload and after the profile lock.
CREATE OR REPLACE FUNCTION private.wm_profile_approval_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid();pid uuid;rid uuid;n integer;w private.wrestling_profiles%rowtype;
 r private.profile_approval_requests%rowtype;prior private.profile_approval_requests%rowtype;
 result jsonb;prop jsonb;d jsonb;sh jsonb;snapshot jsonb;recipient record;newpath text; c jsonb; policy jsonb;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use your personal account for profile setup';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then raise exception 'Invalid profile request';end if;
 if p_action in ('settings','set_settings') then
  pid:=nullif(p_data->>'profile_id','')::uuid;
  if p_action='set_settings' then
   if pid is null or not private.profile_approval_guardian(pid) then raise exception 'Only a currently linked parent can change approval settings';end if;
   perform 1 from private.wrestling_profiles where id=pid for update;
   if jsonb_typeof(p_data->'auto_approve') is distinct from 'boolean' or jsonb_typeof(p_data->'review_photos') is distinct from 'boolean' then raise exception 'Choose both approval settings';end if;
   insert into private.profile_approval_preferences(profile_id,auto_approve,review_photos,updated_by)
    values(pid,(p_data->>'auto_approve')::boolean,(p_data->>'review_photos')::boolean,uid)
    on conflict(profile_id) do update set auto_approve=excluded.auto_approve,review_photos=excluded.review_photos,updated_by=uid,updated_at=now();
  end if;
  perform private.wrestling_profiles_request('mine','{}');
  select coalesce(jsonb_agg(jsonb_build_object('profile_id',policy_profile.id,'name',policy_profile.name,'can_manage',private.profile_approval_guardian(policy_profile.id),'policy',private.profile_approval_policy(policy_profile.id)) order by policy_profile.name),'[]') into result
  from private.wrestling_profiles policy_profile where (pid is null or policy_profile.id=pid) and policy_profile.athlete_profile_id is not null
   and (private.profile_approval_guardian(policy_profile.id) or private.wrestling_profile_self(policy_profile.id));
  return result;
 end if;
 if p_action in ('context','prepare') then
  perform private.wrestling_profiles_request('mine','{}');
  if p_data->>'kind'='social' then pid:=nullif(p_data->>'id','')::uuid;
  elsif p_data->>'kind'='athlete' then select wp.id into pid from public.athletes a join private.wrestling_profiles wp on wp.athlete_profile_id=a.profile_id where a.id=(p_data->>'id')::uuid;
  elsif p_data->>'kind'='account' then
   select count(distinct a.profile_id) into n from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=uid and m.role='athlete' and m.active;
   if n>1 then raise exception 'Choose your athlete profile from My profiles';end if;
   if n=1 then select wp.id into pid from public.team_memberships m join public.athletes a on a.id=m.athlete_id join private.wrestling_profiles wp on wp.athlete_profile_id=a.profile_id where m.user_id=uid and m.role='athlete' and m.active limit 1;
   else select id into pid from private.wrestling_profiles where user_id=uid;end if;
  else raise exception 'Choose a profile to edit';end if;
  if pid is null then raise exception 'Finish joining your team, then open your athlete profile';end if;
  if private.wrestling_profile_manager(pid) then return jsonb_build_object('approval_required',false,'profile_id',pid);end if;
  if not private.wrestling_profile_self(pid) then raise exception 'Choose your own athlete profile';end if;
  select * into w from private.wrestling_profiles where id=pid for update;
  snapshot:=private.profile_approval_snapshot(pid);
  select * into prior from private.profile_approval_requests where profile_id=pid and submitted_by=uid and status in ('draft','pending','rejected') order by created_at desc limit 1;
  if p_action='context' then
   return jsonb_build_object('approval_required',true,'profile_id',pid,'expected',snapshot,'policy',private.profile_approval_policy(pid),'contact',private.profile_approval_contact(pid),'draft_stale',prior.id is not null and prior.expected is distinct from snapshot,'draft',case when prior.id is null then null else to_jsonb(prior) end);
  end if;
  if p_data ? 'expected' and p_data->'expected' is distinct from snapshot then raise exception 'The profile changed. Reopen it before saving your draft';end if;
  if not (p_data ? 'proposal') and prior.id is not null and prior.expected is distinct from snapshot then raise exception 'Your saved draft needs review. Open Edit profile and send it again';end if;
  prop:=coalesce(p_data->'proposal',prior.proposal,jsonb_build_object('name',w.name,'details',w.details,'sharing',w.sharing,'discoverable',w.discoverable));
  if jsonb_typeof(prop)<>'object' or jsonb_typeof(prop->'name') is distinct from 'string' or length(trim(prop->>'name')) not between 1 and 120 then raise exception 'Enter your name (up to 120 characters)';end if;
  d:=coalesce(prop->'details','{}');sh:=coalesce(prop->'sharing','{}');
  if jsonb_typeof(d)<>'object' or jsonb_typeof(sh)<>'object' then raise exception 'Invalid profile details';end if;
  if exists(select 1 from jsonb_each(d) where key in ('roles','bio','age_division','affiliation','mat_rank','pairing_rank','music_title','music_url') and jsonb_typeof(value)<>'string') then raise exception 'Profile text must be text';end if;
  if length(coalesce(d->>'bio',''))>1200 or exists(select 1 from jsonb_each_text(d) where key in ('roles','age_division','affiliation','mat_rank','pairing_rank','music_title') and length(value)>160) then raise exception 'Please shorten the profile text';end if;
  if length(coalesce(d->>'music_url',''))>1000 or (coalesce(d->>'music_url','')<>'' and d->>'music_url' !~ '^https://(music[.]apple[.]com|open[.]spotify[.]com)/[^[:space:]]+$') then raise exception 'Use an Apple Music or Spotify HTTPS link';end if;
  if d ? 'results' then
   if jsonb_typeof(d->'results')<>'array' then raise exception 'Invalid tournament results';end if;
   if jsonb_array_length(d->'results')>30 or exists(select 1 from jsonb_array_elements(d->'results') x where jsonb_typeof(x)<>'object' or octet_length(x::text)>2500) then raise exception 'Use up to 30 short tournament results';end if;
  end if;
  select coalesce(jsonb_object_agg(key,value),'{}') into d from jsonb_each(d) where key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url']);
  select coalesce(jsonb_object_agg(key,value),'{}') into sh from jsonb_each(sh) where value in ('true'::jsonb,'false'::jsonb) and key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url','photo','corner','follow','outgoing_follow']);
  prop:=jsonb_build_object('name',trim(prop->>'name'),'details',d||'{"roles":"Athlete"}','sharing',sh,'discoverable',coalesce((prop->>'discoverable')::boolean,false));
  if coalesce(p_data->'proposal',prior.proposal) ? 'contact' then
   c:=coalesce(p_data->'proposal',prior.proposal)->'contact';
   if jsonb_typeof(c)<>'object' or jsonb_typeof(c->'email') is distinct from 'string' or jsonb_typeof(c->'phone') is distinct from 'string'
    or jsonb_typeof(c->'share_email_with_coaches') is distinct from 'boolean' or jsonb_typeof(c->'share_phone_with_coaches') is distinct from 'boolean'
    then raise exception 'Check your contact details';end if;
   if length(c->>'email')>254 or (trim(c->>'email')<>'' and c->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then raise exception 'Enter a valid contact email';end if;
   if length(c->>'phone')>32 or c->>'phone' !~ '^[+0-9() .-]*$' then raise exception 'Enter a valid phone number';end if;
   c:=jsonb_build_object('email',lower(trim(c->>'email')),'phone',trim(c->>'phone'),'share_email_with_coaches',(c->>'share_email_with_coaches')::boolean,'share_phone_with_coaches',(c->>'share_phone_with_coaches')::boolean);
   prop:=prop||jsonb_build_object('contact',c);
  end if;
  if p_data->'proposal' ? 'team_profile' then prop:=prop||jsonb_build_object('team_profile',private.normalize_profile_team_edit(pid,p_data->'proposal'->'team_profile'));end if;
  rid:=gen_random_uuid();newpath:=case when p_data->>'new_photo'='true' then uid::text||'/'||rid::text||'.jpg' when p_data->'proposal' ? 'team_profile' then null when prior.expected=snapshot then prior.path else null end;
  insert into private.profile_approval_requests(id,profile_id,submitted_by,path,proposal,expected) values(rid,pid,uid,newpath,prop,snapshot);
  return jsonb_build_object('approval_required',true,'id',rid,'profile_id',pid,'bucket','profile-photo-requests','path',newpath);
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]') into result from (
   select req.id,req.profile_id,wp.name,req.path,req.proposal,req.status,req.created_at,req.auto_approved,private.profile_approval_guardian(req.profile_id) as can_review
   from private.profile_approval_requests req join private.wrestling_profiles wp on wp.id=req.profile_id
   where req.status not in ('uploading','superseded') and
    ((req.status<>'draft' and private.profile_approval_guardian(req.profile_id)) or (req.submitted_by=uid and private.wrestling_profile_self(req.profile_id)))
   and (nullif(p_data->>'profile_id','') is null or req.profile_id=(p_data->>'profile_id')::uuid)
   and (nullif(p_data->>'id','') is null or req.id=(p_data->>'id')::uuid)
   order by (req.status='pending') desc,req.created_at desc limit 50
  ) q;return result;
 end if;
 rid:=nullif(p_data->>'id','')::uuid;
 select profile_id into pid from private.profile_approval_requests where id=rid;
 if pid is null then raise exception 'Profile request is no longer available';end if;
 perform 1 from private.wrestling_profiles where id=pid for update;
 select * into r from private.profile_approval_requests where id=rid for update;
 if p_action in ('save_draft','submit') then
  if r.submitted_by<>uid or not private.wrestling_profile_self(pid) then raise exception 'Only the athlete can send their own draft';end if;
  if r.status in ('pending','approved') then return jsonb_build_object('id',rid,'pending',r.status='pending','status',r.status);end if;
  if r.status not in ('uploading','draft') then raise exception 'Reopen your profile to start a new draft';end if;
  if r.expected is distinct from private.profile_approval_snapshot(pid) then raise exception 'The profile changed. Reopen it before sending this draft';end if;
  if r.path is not null and not exists(select 1 from storage.objects where bucket_id='profile-photo-requests' and name=r.path and owner_id=uid::text and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 1 and 12000000) then raise exception 'Upload the complete photo before saving';end if;
  update private.profile_approval_requests set status='superseded',reviewed_at=now() where profile_id=pid and status in ('pending','draft') and id<>rid;
  update public.communication_notifications cn set read_at=coalesce(read_at,now()) where profile_request_id in (select id from private.profile_approval_requests where profile_id=pid and status='superseded');
  update private.profile_approval_requests set status=case when p_action='submit' then 'pending' else 'draft' end,submitted_at=case when p_action='submit' then now() else null end where id=rid;
  if p_action='save_draft' then return jsonb_build_object('id',rid,'status','draft');end if;
  if r.path is null and private.profile_request_can_auto_approve(rid,pid) then
   perform private.complete_profile_approval(rid,pid);
   return jsonb_build_object('id',rid,'status','approved','auto_approved',true,'pending',false);
  end if;
  n:=0;
  for recipient in
   select distinct on(g.guardian_user_id) g.guardian_user_id,m.team_id,a.id as athlete_id
   from private.wrestling_profiles wp join public.athletes a on a.profile_id=wp.athlete_profile_id join public.athlete_guardians g on g.athlete_id=a.id
   join public.team_memberships m on m.athlete_id=a.id and m.user_id=g.guardian_user_id and m.role='parent_guardian' and m.active
   where wp.id=pid and not exists(select 1 from private.team_logins where user_id=g.guardian_user_id) order by g.guardian_user_id,m.created_at
  loop
   insert into public.communication_notifications(team_id,user_id,category,title,body,athlete_id,profile_request_id)
   values(recipient.team_id,recipient.guardian_user_id,'system','Review athlete profile','Your athlete sent a profile for approval. Review the name, photo, details and sharing choices before they go live.',recipient.athlete_id,rid);
   n:=n+1;
  end loop;
  if n=0 and not (r.path is not null and private.profile_request_can_auto_approve(rid,pid)) then raise exception 'Ask your coach to link a parent or guardian, then send your saved draft for approval';end if;
  return jsonb_build_object('id',rid,'pending',true,'status','pending','auto_photo',r.path is not null and private.profile_request_can_auto_approve(rid,pid));
 end if;
 if p_action in ('reject','approve') then
  if not private.profile_approval_guardian(pid) then raise exception 'A linked parent or guardian must review this profile';end if;
  if r.status=p_action||'d' or (p_action='reject' and r.status='rejected') then return jsonb_build_object('id',rid,'status',r.status);end if;
  if r.status<>'pending' then raise exception 'This request was already reviewed or replaced. Refresh the list';end if;
  if p_action='approve' then perform private.complete_profile_approval(rid,pid);return jsonb_build_object('id',rid,'status','approved');end if;
  update private.profile_approval_requests set status='rejected',reviewed_at=now(),reviewed_by=uid where id=rid;
  update public.communication_notifications set read_at=coalesce(read_at,now()) where profile_request_id=rid;
  return jsonb_build_object('id',rid,'status','rejected');
 end if;
 raise exception 'Unknown profile approval action';
end $function$;
