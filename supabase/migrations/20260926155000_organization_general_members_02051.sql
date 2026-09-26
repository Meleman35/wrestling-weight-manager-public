-- Ordinary organization membership, separate from governance positions and managed teams.
create table private.organization_general_members (
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 invitation_id uuid not null references private.organization_leadership_invitations(id),
 created_at timestamptz not null default now(),
 primary key(organization_id,user_id)
);
alter table private.organization_general_members enable row level security;
revoke all on private.organization_general_members from public,anon,authenticated;
grant select on private.organization_general_members to authenticated;
create policy organization_general_members_self on private.organization_general_members for select to authenticated
 using (user_id=(select auth.uid()));
alter table private.organization_leadership_invitations drop constraint organization_leadership_invitations_kind_check;
alter table private.organization_leadership_invitations add constraint organization_leadership_invitations_kind_check check(kind in ('administrator','position','member'));
alter table private.organization_leadership_invitations drop constraint organization_leadership_invitations_check;
alter table private.organization_leadership_invitations add constraint organization_leadership_invitations_check check (
 (kind in ('administrator','member') and position_id is null and access_role is null)
 or (kind='position' and position_id is not null and position_revision is not null)
);
CREATE OR REPLACE FUNCTION private.ops_member(o uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and (
   exists(select 1 from public.organization_memberships where organization_id=o and user_id=auth.uid())
   or exists(select 1 from private.organization_general_members where organization_id=o and user_id=auth.uid())
   or exists(select 1 from private.ops_roles where organization_id=o and user_id=auth.uid())
   or exists(select 1 from private.organization_positions where organization_id=o and assigned_user_id=auth.uid() and active)
   or exists(
     select 1 from private.organization_affiliate_delegates d
     join private.organization_affiliates a on a.id=d.affiliate_id
     where a.organization_id=o and a.status='active' and d.user_id=auth.uid() and d.active
   )
   or exists(select 1 from private.ops_records where organization_id=o and kind='person' and data->>'user_id'=auth.uid()::text)
   or exists(
     select 1 from public.team_memberships m
     join public.teams t on t.id=m.team_id
     where m.user_id=auth.uid() and m.active
       and (t.organization_id=o or exists(
         select 1 from private.ops_links l
         where l.organization_id=o and l.team_id=t.id and l.approved
       ))
   )
 );
$function$;
create or replace function private.organization_leadership_invites(q jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid(); act text:=q->>'action'; o uuid:=nullif(q->>'organization_id','')::uuid;
 rid uuid:=nullif(q->>'id','')::uuid; target uuid; pos_id uuid:=nullif(q->>'position_id','')::uuid;
 mail text; confirmed timestamptz; token text:=coalesce(q->>'token',''); digest bytea;
 kind_text text:=q->>'kind'; role_text text:=nullif(q->>'access_role',''); summary jsonb;
 inv private.organization_leadership_invitations%rowtype;
 p private.organization_positions%rowtype; result jsonb; snapshot jsonb; rev integer;
 request_id uuid:=nullif(q->>'request_id','')::uuid;
begin
 if uid is null or not private.ops_personal() or not private.managed_login_access_ok() then
  raise sqlstate '42501' using message='Sign in with your own personal account.';
 end if;
 if jsonb_typeof(q) is distinct from 'object' or octet_length(q::text)>8000 then raise exception 'Invalid request.'; end if;
 if act not in ('context','create','preview','accept','revoke','email_context','remove_admin','remove_member') or act is null then raise exception 'Unknown invitation action.'; end if;
 if act in ('create','preview','accept','email_context') then
  if token !~ '^WMO-[0-9a-f]{64}$' then raise exception 'Use the complete organization invitation link or WMO token.'; end if;
  digest:=sha256(convert_to(token,'UTF8'));
 end if;

 if act in ('preview','accept') then
  -- Never reveal invitation details to another email, even with a valid token.
  select lower(trim(email)),email_confirmed_at into mail,confirmed from auth.users where id=uid;
  if confirmed is null then raise sqlstate '42501' using message='Confirm your account email before accepting an organization invitation.'; end if;
  select * into inv from private.organization_leadership_invitations where token_hash=digest;
  if not found or inv.invited_email is distinct from mail then
   raise sqlstate '42501' using message='Invitation unavailable for this account. Sign in with the invited email.';
  end if;
  o:=inv.organization_id;
  perform 1 from public.organizations where id=o for update;
  select * into inv from private.organization_leadership_invitations where id=inv.id for update;
  if inv.status='accepted' and inv.accepted_by=uid then
   return jsonb_build_object('organization_id',o,'accepted',true,'already_accepted',true);
  end if;
  if inv.status<>'pending' or inv.expires_at<=now() then raise exception 'This invitation expired or was revoked. Ask for a new invitation.'; end if;
  if not exists(select 1 from public.organization_memberships where organization_id=o and user_id=inv.created_by and role='organization_admin')
   or exists(select 1 from private.team_logins where user_id=inv.created_by) then raise exception 'The inviting administrator no longer has access. Ask a current administrator for a new invitation.'; end if;
  if inv.kind='position' then
   select * into p from private.organization_positions where id=inv.position_id and organization_id=o for update;
   if not found or not p.active or not p.assignment_enabled or lower(p.title)~'athlete.*rep'
    or p.assigned_user_id is not null or p.revision<>inv.position_revision then
    raise exception 'This position changed or is already assigned. Ask for a new invitation.';
   end if;
  end if;
  if not exists(select 1 from public.profiles where id=uid) then raise exception 'Finish your personal account profile first.'; end if;
  if exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
    where m.user_id=uid and m.role='athlete' and (a.birth_date is null or a.birth_date>(current_date-interval '18 years')::date)) then
   raise sqlstate '42501' using message='This leadership invitation requires an adult personal account.';
  end if;
  result:=jsonb_build_object('id',inv.id,'organization_id',o,'organization_name',(select name from public.organizations where id=o),
    'email',inv.invited_email,'kind',inv.kind,'access',inv.access_summary,'expires_at',inv.expires_at);
  if act='preview' then return result; end if;
  if q->'confirm_adult' is distinct from 'true'::jsonb or q->'confirm_access' is distinct from 'true'::jsonb then
   raise exception 'Confirm that you are at least 18, using your own account, and accept the displayed access.';
  end if;
  if inv.kind='member' then
   insert into private.organization_general_members(organization_id,user_id,invitation_id) values(o,uid,inv.id)
    on conflict(organization_id,user_id) do nothing;
  elsif inv.kind='administrator' then
   insert into public.organization_memberships(organization_id,user_id,role) values(o,uid,'organization_admin')
    on conflict(organization_id,user_id) do update set role='organization_admin';
  else
   update private.organization_positions set assigned_user_id=uid,access_role=inv.access_role,
    adult_confirmed_by=inv.created_by,adult_confirmed_at=inv.created_at,updated_by=uid,updated_at=now(),revision=revision+1
    where id=inv.position_id returning to_jsonb(organization_positions),revision into snapshot,rev;
   insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason,actor_id)
    values(o,'position',inv.position_id,rev,snapshot,'Accepted direct leadership invitation',uid);
  end if;
  update private.organization_leadership_invitations set status='accepted',accepted_by=uid,accepted_at=now() where id=inv.id;
  insert into private.ops_audit(organization_id,actor_id,action,record_id,detail)
   values(o,uid,'leadership_invitation_accepted',inv.id,jsonb_build_object('kind',inv.kind,'position_id',inv.position_id,'access',inv.access_summary));
  return result||jsonb_build_object('accepted',true);
 end if;

 if o is null then raise exception 'Choose an organization.'; end if;
 -- Serialize invitation and administrator mutations within one organization.
 perform 1 from public.organizations where id=o for update;
 if not private.ops_admin(o) then raise sqlstate '42501' using message='Organization administrator access required.'; end if;
 if act='context' then
  return jsonb_build_object(
   'organization_id',o,'organization_name',(select name from public.organizations where id=o),
   'positions',coalesce((select jsonb_agg(jsonb_build_object('id',listed.id,'title',listed.title,'revision',listed.revision,
     'division_name',coalesce(d.name,'Organization'),'voting_member',listed.voting_member,
     'can_manage_meetings',listed.can_manage_meetings,'can_manage_votes',listed.can_manage_votes) order by listed.sort_order,listed.title)
     from private.organization_positions listed left join private.ops_divisions d on d.id=listed.division_id
     where listed.organization_id=o and listed.active and listed.assignment_enabled and listed.assigned_user_id is null and lower(listed.title)!~'athlete.*rep'),'[]'::jsonb),
   'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce(pr.display_name,'Member'),'joined_at',m.created_at) order by pr.display_name)
     from private.organization_general_members m left join public.profiles pr on pr.id=m.user_id where m.organization_id=o),'[]'::jsonb),
   'administrators',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce(pr.display_name,'Organization administrator')) order by pr.display_name)
     from public.organization_memberships m left join public.profiles pr on pr.id=m.user_id where m.organization_id=o and m.role='organization_admin'),'[]'::jsonb),
   'invitations',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc) from (
     select id,invited_email,kind,position_id,access_summary,created_at,expires_at,accepted_at,
      case when status='pending' and expires_at<=now() then 'expired' else status end as status
     from private.organization_leadership_invitations where organization_id=o order by created_at desc limit 200) v),'[]'::jsonb));
 end if;
 if act='remove_member' then
  target:=nullif(q->>'user_id','')::uuid;
  if q->'confirm_remove' is distinct from 'true'::jsonb or target is null then raise exception 'Confirm the member to remove.'; end if;
  delete from private.organization_general_members where organization_id=o and user_id=target;
  insert into private.ops_audit(organization_id,actor_id,action,record_id,detail)
   values(o,uid,'organization_member_removed',target,'{}');
  return jsonb_build_object('removed',true);
 end if;
 if act='remove_admin' then
  target:=nullif(q->>'user_id','')::uuid;
  if q->'confirm_remove' is distinct from 'true'::jsonb or target is null then raise exception 'Confirm the administrator to remove.'; end if;
  if (select count(*) from public.organization_memberships where organization_id=o and role='organization_admin' and user_id<>target)=0 then raise exception 'Keep at least one organization administrator.'; end if;
  if target=uid then raise exception 'Ask another organization administrator to remove your access.'; end if;
  delete from public.organization_memberships where organization_id=o and user_id=target and role='organization_admin';
  update private.organization_leadership_invitations set status='revoked',revoked_by=uid,revoked_at=now()
   where organization_id=o and status='pending' and created_by=target;
  insert into private.ops_audit(organization_id,actor_id,action,record_id,detail)
   values(o,uid,'organization_admin_removed',target,'{}');
  return jsonb_build_object('removed',true);
 end if;
 if act='create' then
  mail:=lower(trim(coalesce(q->>'email','')));
  if length(mail)>254 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Enter a valid email address.'; end if;
  if rid is null or kind_text not in ('administrator','position','member') or kind_text is null then raise exception 'Choose an invitation role.'; end if;
  if q->'confirm_adult' is distinct from 'true'::jsonb or q->'confirm_access' is distinct from 'true'::jsonb then raise exception 'Confirm the adult recipient and selected permissions.'; end if;
  select * into inv from private.organization_leadership_invitations where id=rid;
  if found then
   if inv.organization_id<>o or inv.created_by<>uid or inv.token_hash<>digest or inv.invited_email<>mail
    or inv.kind<>kind_text or inv.position_id is distinct from pos_id or inv.access_role is distinct from role_text
    or (kind_text='position' and inv.position_revision is distinct from (q->>'revision')::integer) then raise exception 'Invitation request was reused with different content.'; end if;
   if inv.status<>'pending' or inv.expires_at<=now() then raise exception 'This invitation is no longer pending. Reload invitations.'; end if;
   return jsonb_build_object('id',inv.id,'expires_at',inv.expires_at,'access',inv.access_summary);
  end if;
  if (select count(*) from private.organization_leadership_invitations where organization_id=o and created_at>now()-interval '1 hour')>=100 then raise exception 'Please wait before creating more invitations.'; end if;
  if kind_text='member' then
   if pos_id is not null or role_text is not null then raise exception 'Member invitations cannot include a position permission.'; end if;
   summary:=jsonb_build_object('title','Organization member','scope','Organization','access_role','organization_member',
     'voting_member',false,'can_manage_meetings',false,'can_manage_votes',false);
  elsif kind_text='administrator' then
   if pos_id is not null or role_text is not null then raise exception 'Administrator invitations cannot include a position permission.'; end if;
   summary:=jsonb_build_object('title','Organization administrator','scope','Organization','access_role','organization_admin',
     'voting_member',false,'can_manage_meetings',true,'can_manage_votes',true);
  else
   select * into p from private.organization_positions where id=pos_id and organization_id=o for update;
   if not found or not p.active or not p.assignment_enabled or lower(p.title)~'athlete.*rep' or p.assigned_user_id is not null then raise exception 'Choose an active vacant adult position in this organization.'; end if;
   if p.revision is distinct from (q->>'revision')::integer then raise exception 'This position changed. Reload invitations.'; end if;
   if role_text is not null and role_text not in ('president','director','board','division_director','pairing_director','mat_director','coach','chaperone','team_leader','official','membership_coordinator') then raise exception 'Choose a supported access permission.'; end if;
   summary:=jsonb_build_object('title',p.title,'scope',coalesce((select name from private.ops_divisions where id=p.division_id),'Organization'),
    'access_role',role_text,'voting_member',p.voting_member,'can_manage_meetings',p.can_manage_meetings,'can_manage_votes',p.can_manage_votes);
  end if;
  if exists(select 1 from private.organization_leadership_invitations where organization_id=o and status='pending' and expires_at>now()
   and ((kind_text='position' and position_id=pos_id) or (kind_text in ('administrator','member') and kind=kind_text and invited_email=mail))) then
   raise exception 'A pending invitation already exists. Revoke it before creating a replacement.';
  end if;
  insert into private.organization_leadership_invitations(id,organization_id,invited_email,kind,position_id,position_revision,access_role,access_summary,token_hash,created_by)
   values(rid,o,mail,kind_text,pos_id,case when kind_text='position' then p.revision end,role_text,summary,digest,uid)
   returning * into inv;
  insert into private.ops_audit(organization_id,actor_id,action,record_id,detail)
   values(o,uid,'leadership_invitation_created',rid,jsonb_build_object('email',mail,'kind',kind_text,'access',summary,'adult_attestation',true));
  return jsonb_build_object('id',inv.id,'expires_at',inv.expires_at,'access',summary);
 end if;
 select * into inv from private.organization_leadership_invitations where id=rid and organization_id=o for update;
 if not found then raise exception 'Invitation not found in this organization.'; end if;
 if act='revoke' then
  if inv.status='accepted' then raise exception 'This invitation was accepted. Remove administrator access or clear the assigned position to remove access.'; end if;
  if inv.status='pending' then
   update private.organization_leadership_invitations set status='revoked',revoked_by=uid,revoked_at=now() where id=rid;
   insert into private.ops_audit(organization_id,actor_id,action,record_id,detail) values(o,uid,'leadership_invitation_revoked',rid,'{}');
  end if;
  return jsonb_build_object('revoked',true);
 end if;
 -- The email endpoint can send only this saved invitation to its saved email.
 if inv.token_hash<>digest or inv.status<>'pending' or inv.expires_at<=now() then raise exception 'This invitation is no longer available to email.'; end if;
 if request_id is null then raise exception 'An email request identifier is required.'; end if;
 if inv.email_request_id=request_id then
  if inv.email_requested_at<now()-interval '23 hours' then raise exception 'Start a new email request.'; end if;
 else
  if inv.email_requested_at>now()-interval '1 minute' then raise exception 'Wait one minute before requesting another email.'; end if;
  update private.organization_leadership_invitations set email_request_id=request_id,email_requested_at=now() where id=rid;
 end if;
 return jsonb_build_object('id',inv.id,'organization_name',(select name from public.organizations where id=o),
  'email',inv.invited_email,'access',inv.access_summary,'expires_at',inv.expires_at,'request_id',request_id);
end;
$$;
