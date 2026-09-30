-- Production function definitions captured 2026-09-30; no user records.
set check_function_bodies=false;
CREATE OR REPLACE FUNCTION private.can_send_team_sms(p_team_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true
      and (
        tm.role='head_coach'
        or coalesce((tm.permissions->>'team_admin')::boolean,false)
        or coalesce((tm.permissions->>'mass_text')::boolean,false)
      )
  ) or exists(
    select 1 from public.teams t
    join public.organization_memberships om on om.organization_id=t.organization_id
    where t.id=p_team_id and om.user_id=p_user_id and om.role='organization_admin'
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_upload_communication_media_object(p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_parts text[]:=string_to_array(coalesce(p_name,''),'/');
  v_team uuid;
  v_thread uuid;
  v_kind text;
begin
  if v_user is null or cardinality(v_parts)<4 or v_parts[3]<>v_user::text then return false; end if;
  begin
    v_team:=v_parts[1]::uuid;
    v_thread:=v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  select t.kind into v_kind
  from public.communication_threads t
  join public.communication_thread_members m
    on m.thread_id=t.id and m.user_id=v_user and m.left_at is null and m.can_post
  where t.id=v_thread and t.team_id=v_team and t.archived_at is null;
  if not found then return false; end if;

  return not private.communication_user_is_minor(v_team,v_user)
    or private.communication_minor_capability(
      v_team,v_user,case when v_kind='direct' then 'media_send_direct' else 'media_send_group' end
    );
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_view_communication_media_object(p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_parts text[]:=string_to_array(coalesce(p_name,''),'/');
  v_team uuid;
  v_path_thread uuid;
  v_access_thread uuid;
begin
  if v_user is null or cardinality(v_parts)<4 then
    return false;
  end if;

  begin
    v_team:=v_parts[1]::uuid;
    v_path_thread:=v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  select coalesce(t.merged_into_thread_id,t.id)
  into v_access_thread
  from public.communication_threads t
  where t.id=v_path_thread and t.team_id=v_team;

  if v_access_thread is null or not exists(
    select 1
    from public.communication_threads t
    join public.communication_thread_members m
      on m.thread_id=t.id
     and m.user_id=v_user
     and m.left_at is null
    where t.id=v_access_thread
      and t.team_id=v_team
      and t.archived_at is null
  ) then
    return false;
  end if;

  return not private.communication_user_is_minor(v_team,v_user)
    or private.communication_minor_capability(v_team,v_user,'media_view');
end;
$function$;

CREATE OR REPLACE FUNCTION private.communication_authorized_adult(p_team_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.communication_user_is_staff(p_team_id,p_user_id)
  or exists(
    select 1 from public.team_memberships tm
    where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true and tm.role='manager'
      and coalesce(tm.permissions->>'staff_role','') in ('team_leader','club_president')
  );
$function$;

CREATE OR REPLACE FUNCTION private.communication_can_view_thread(p_thread_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from public.communication_thread_members m
    where m.thread_id=p_thread_id and m.user_id=p_user_id and m.left_at is null
  );
$function$;

CREATE OR REPLACE FUNCTION private.communication_direct_participant_key(p_user_ids uuid[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when count(*)=2 then string_agg(x::text,':' order by x::text)
    else null
  end
  from (
    select distinct user_id as x
    from unnest(coalesce(p_user_ids,'{}'::uuid[])) as ids(user_id)
    where user_id is not null
  ) normalized;
$function$;

CREATE OR REPLACE FUNCTION private.communication_enqueue_notification(p_team_id uuid, p_user_id uuid, p_category text, p_title text, p_body text, p_thread_id uuid, p_message_id uuid, p_urgent boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_pref public.communication_preferences%rowtype; v_payload jsonb;
begin
  select * into v_pref from public.communication_preferences where team_id=p_team_id and user_id=p_user_id;
  insert into public.communication_notifications(team_id,user_id,category,title,body,thread_id,message_id)
  values(p_team_id,p_user_id,p_category,left(p_title,160),left(p_body,500),p_thread_id,p_message_id) returning id into v_id;
  v_payload=jsonb_build_object('title',left(p_title,160),'body',left(p_body,500),'category',p_category,'thread_id',p_thread_id,'message_id',p_message_id,'urgent',p_urgent);
  if p_category='announcement' then
    if coalesce(v_pref.push_announcements,true) then insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'push',v_payload) on conflict do nothing; end if;
    if coalesce(v_pref.sms_announcements,true) then insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'sms',(v_payload-'body')||jsonb_build_object('body','Important team announcement — open Wrestling Manager for details.','reply_mode','disabled','route_context','announcement')) on conflict do nothing; end if;
    if coalesce(v_pref.email_announcements,true) then insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'email',v_payload) on conflict do nothing; end if;
  elsif p_category='safety' then
    insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'sms',(v_payload-'body')||jsonb_build_object('body','A message involving your athlete needs safety review. Open Wrestling Manager for details.','reply_mode','disabled','route_context','safety')) on conflict do nothing;
    insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'push',(v_payload-'body')||jsonb_build_object('body','A message needs safety review.')) on conflict do nothing;
  else
    if coalesce(v_pref.push_messages,true) then insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'push',v_payload) on conflict do nothing; end if;
    if coalesce(v_pref.email_messages,false) then insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload) values(v_id,p_team_id,p_user_id,'email',v_payload) on conflict do nothing; end if;
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.communication_member_eligible(t communication_threads, u uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select u is not null
 and private.communication_user_belongs_to_team(t.team_id,u)
 and not exists(select 1 from private.team_logins l where l.user_id=u)
 and (not private.communication_user_is_minor(t.team_id,u)
      or private.communication_minor_capability(t.team_id,u,case when t.kind='group' then 'group_chat' else 'team_chat' end))
 and case t.kind
  when 'group' then true
  when 'all_members' then exists(select 1 from public.team_memberships m where m.team_id=t.team_id and m.user_id=u and m.active)
    or exists(select 1 from public.roster_memberships r join public.athlete_guardians g on g.athlete_id=r.athlete_id where r.season_id=t.season_id and r.active and g.guardian_user_id=u)
  when 'team' then private.communication_authorized_adult(t.team_id,u)
    or exists(select 1 from public.team_memberships m where m.team_id=t.team_id and m.user_id=u and m.active and m.role='athlete')
  when 'staff' then exists(select 1 from public.team_memberships m where m.team_id=t.team_id and m.user_id=u and m.active and m.role in ('head_coach','assistant_coach'))
  when 'parents' then exists(select 1 from public.team_memberships m where m.team_id=t.team_id and m.user_id=u and m.active and m.role='parent_guardian')
    or exists(select 1 from public.roster_memberships r join public.athlete_guardians g on g.athlete_id=r.athlete_id where r.season_id=t.season_id and r.active and g.guardian_user_id=u)
  else false end;
$function$;

CREATE OR REPLACE FUNCTION private.communication_members_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid=auth.uid();t public.communication_threads;target uuid;ids uuid[];minor uuid;members jsonb;candidates jsonb;kept_mirror boolean=false;
begin
 if actor is null or exists(select 1 from private.team_logins l where l.user_id=actor) then raise exception 'Personal coach or administrator account required';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>8192 then raise exception 'Invalid member request';end if;
 select * into t from public.communication_threads where id=(p_data->>'thread_id')::uuid;
 if t.id is null or t.team_id is distinct from (p_data->>'team_id')::uuid
  or not private.communication_user_is_staff(t.team_id,actor)
  or not private.communication_can_view_thread(t.id,actor) then raise exception 'Coach or administrator conversation access required';end if;
 if t.kind not in ('group','team','staff','parents','all_members') or t.archived_at is not null or t.is_safety_test then raise exception 'Member management is available for active group chats';end if;
 if p_action not in ('list','add','remove') or p_action is null then raise exception 'Unknown member action';end if;
 if p_action<>'list' then
  select * into t from public.communication_threads where id=t.id for update;
  if not private.communication_user_is_staff(t.team_id,actor) or not private.communication_can_view_thread(t.id,actor) or t.archived_at is not null then raise exception 'Conversation access changed. Reopen the chat';end if;
  if (p_data->>'revision') is distinct from private.communication_members_revision(t.id) then raise exception 'Members changed. Reload the member list before trying again';end if;
  target:=(p_data->>'user_id')::uuid;
  if target is null or target=actor then raise exception 'Choose another team member';end if;
  if p_action='remove' then
   if not exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.user_id=target and m.left_at is null and m.member_role<>'guardian_mirror') then raise exception 'That person is no longer a chat participant';end if;
   if t.kind='group' and (select count(*) from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null and m.member_role<>'guardian_mirror')<=2 then raise exception 'Keep at least two people in this group';end if;
   kept_mirror:=exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.user_id<>target and m.left_at is null and m.member_role<>'guardian_mirror' and private.communication_user_is_minor(t.team_id,m.user_id) and private.communication_user_is_guardian_of(t.team_id,target,m.user_id));
   insert into private.communication_member_exclusions(thread_id,user_id,removed_by) values(t.id,target,actor) on conflict(thread_id,user_id) do update set removed_by=actor,removed_at=now();
   update public.communication_thread_members set member_role=case when kept_mirror then 'guardian_mirror' else member_role end,can_post=false,left_at=case when kept_mirror then null else now() end where thread_id=t.id and user_id=target;
   if kept_mirror then update public.communication_threads set guardian_mirrored=true where id=t.id;end if;
  else
   if not private.communication_member_eligible(t,target) then raise exception 'This person is not eligible for this chat. Team access and parent permissions are required';end if;
   if exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.user_id=target and m.left_at is null and m.member_role<>'guardian_mirror') then raise exception 'This person is already in the chat';end if;
   select array_agg(distinct x) into ids from (select m.user_id x from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null and m.member_role<>'guardian_mirror' union select target) q;
   if exists(select 1 from public.communication_blocks b where b.team_id=t.team_id and ((b.user_id=target and b.blocked_user_id=any(ids)) or (b.blocked_user_id=target and b.user_id=any(ids)))) then raise exception 'A member block prevents adding this person';end if;
   -- Recheck every minor before the audience changes, including existing members.
   foreach minor in array ids loop
    if private.communication_user_is_minor(t.team_id,minor) then
     if not private.communication_minor_capability(t.team_id,minor,case when t.kind='group' then 'group_chat' else 'team_chat' end) then raise exception 'Parent approval is required for each athlete in this chat';end if;
     if exists(select 1 from unnest(ids) x where not private.communication_user_is_minor(t.team_id,x)) then
      if not exists(select 1 from public.team_memberships m join public.athlete_guardians g on g.athlete_id=m.athlete_id where m.team_id=t.team_id and m.user_id=minor and m.role='athlete' and m.active and g.guardian_user_id is not null) then raise exception 'A connected parent or guardian is required';end if;
     end if;
    end if;
   end loop;
   delete from private.communication_member_exclusions where thread_id=t.id and user_id=target;
   insert into public.communication_thread_members(thread_id,user_id,member_role,can_post,added_by) values(t.id,target,'participant',true,actor)
    on conflict(thread_id,user_id) do update set member_role='participant',can_post=true,left_at=null,hidden_at=null,added_by=actor;
   if exists(select 1 from unnest(ids) x where not private.communication_user_is_minor(t.team_id,x)) then
    foreach minor in array ids loop
     if private.communication_user_is_minor(t.team_id,minor) then
      insert into public.communication_thread_members as existing(thread_id,user_id,member_role,can_post,added_by)
       select distinct t.id,g.guardian_user_id,'guardian_mirror',false,actor from public.team_memberships m join public.athlete_guardians g on g.athlete_id=m.athlete_id where m.team_id=t.team_id and m.user_id=minor and m.active and m.role='athlete' and g.guardian_user_id is not null
       on conflict(thread_id,user_id) do update set member_role=case when existing.left_at is null and existing.member_role<>'guardian_mirror' then existing.member_role else 'guardian_mirror' end,can_post=case when existing.left_at is null and existing.member_role<>'guardian_mirror' then existing.can_post else false end,left_at=null;
      update public.communication_threads set guardian_mirrored=true where id=t.id;
     end if;
    end loop;
   end if;
  end if;
  insert into private.communication_member_changes(thread_id,user_id,actor_id,action) values(t.id,target,actor,p_action);
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'display_name',private.communication_person_name(t.team_id,m.user_id),'is_self',m.user_id=actor) order by private.communication_person_name(t.team_id,m.user_id),m.user_id),'[]') into members
 from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null and m.member_role<>'guardian_mirror';
 with people as (
  select m.user_id from public.team_memberships m where m.team_id=t.team_id and m.active
  union select g.guardian_user_id from public.seasons s join public.roster_memberships r on r.season_id=s.id and r.active join public.athlete_guardians g on g.athlete_id=r.athlete_id where s.team_id=t.team_id and g.guardian_user_id is not null
  union select o.user_id from public.teams x join public.organization_memberships o on o.organization_id=x.organization_id and o.role='organization_admin' where x.id=t.team_id
 ) select coalesce(jsonb_agg(jsonb_build_object('user_id',u.user_id,'display_name',private.communication_person_name(t.team_id,u.user_id)) order by private.communication_person_name(t.team_id,u.user_id),u.user_id),'[]') into candidates
 from people u where u.user_id<>actor and private.communication_member_eligible(t,u.user_id)
 and not exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.user_id=u.user_id and m.left_at is null and m.member_role<>'guardian_mirror');
 return jsonb_build_object('thread_id',t.id,'team_id',t.team_id,'title',t.title,'members',members,'candidates',candidates,'revision',private.communication_members_revision(t.id),'kept_guardian_access',kept_mirror,'automatic',t.system_key is not null);
end $function$;

CREATE OR REPLACE FUNCTION private.communication_members_revision(tid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select md5(jsonb_build_array(
  (select jsonb_agg(jsonb_build_array(m.user_id,m.member_role,m.can_post,m.left_at) order by m.user_id) from public.communication_thread_members m where m.thread_id=tid),
  (select jsonb_agg(jsonb_build_array(e.user_id,e.removed_at) order by e.user_id) from private.communication_member_exclusions e where e.thread_id=tid)
 )::text);
$function$;

CREATE OR REPLACE FUNCTION private.communication_minor_capability(p_team_id uuid, p_user_id uuid, p_capability text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_athlete uuid;
  v_minor boolean;
begin
  v_minor:=private.communication_user_is_minor(p_team_id,p_user_id);
  if not v_minor then return true; end if;

  select tm.athlete_id into v_athlete
  from public.team_memberships tm
  where tm.team_id=p_team_id
    and tm.user_id=p_user_id
    and tm.role='athlete'
    and tm.active=true
  limit 1;

  if v_athlete is null then return false; end if;

  return coalesce((
    select case p_capability
      when 'team_chat' then cp.team_chat
      when 'group_chat' then cp.group_chat
      when 'peer_to_peer' then cp.peer_to_peer
      when 'coach_to_athlete' then cp.coach_to_athlete
      when 'media_view' then cp.media_view
      when 'media_send_group' then cp.media_send_group
      when 'media_send_direct' then cp.media_send_direct
      else false
    end
    from public.athlete_chat_permissions cp
    where cp.team_id=p_team_id and cp.athlete_id=v_athlete
  ),false);
end;
$function$;

CREATE OR REPLACE FUNCTION private.communication_person_name(p_team_id uuid, p_user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with account as (
  select p.display_name,sp.display_name staff_name,u.email,u.raw_user_meta_data meta
  from auth.users u left join public.profiles p on p.id=u.id
  left join public.team_staff_profiles sp on sp.user_id=u.id and sp.team_id=p_team_id
  where u.id=p_user_id
 ), own_names as (
  select distinct nullif(trim(concat_ws(' ',a.first_name,a.last_name)),'') name,m.active
  from public.team_memberships m join public.athletes a on a.id=m.athlete_id
  where m.team_id=p_team_id and m.user_id=p_user_id and m.role='athlete'
 ), candidates as (
  select name,1 priority from own_names where active
  union all select staff_name,2 from account
  union all select display_name,3 from account
  union all select min(name),4 from own_names having count(distinct name)=1
  union all select meta->>'full_name',5 from account
  union all select meta->>'name',6 from account
 )
 select coalesce((select trim(c.name) from candidates c cross join account a
  where nullif(trim(c.name),'') is not null
   and lower(trim(c.name))<>lower(coalesce(a.email,''))
   and lower(trim(c.name))<>lower(split_part(coalesce(a.email,''),'@',1))
  order by priority,lower(c.name) limit 1),'Team member');
$function$;

CREATE OR REPLACE FUNCTION private.communication_restore_required_mirrors(tid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.communication_threads;
begin
 select * into t from public.communication_threads where id=tid;
 if t.id is null then return;end if;
 if not exists(select 1 from public.communication_thread_members m where m.thread_id=tid and m.left_at is null and m.member_role<>'guardian_mirror' and not private.communication_user_is_minor(t.team_id,m.user_id)) then return;end if;
 insert into public.communication_thread_members as existing(thread_id,user_id,member_role,can_post,added_by)
 select distinct tid,g.guardian_user_id,'guardian_mirror',false,t.created_by
 from public.communication_thread_members child
 join public.team_memberships own on own.team_id=t.team_id and own.user_id=child.user_id and own.role='athlete' and own.active
 join public.athlete_guardians g on g.athlete_id=own.athlete_id and g.guardian_user_id is not null
 where child.thread_id=tid and child.left_at is null and child.member_role<>'guardian_mirror'
  and private.communication_user_is_minor(t.team_id,child.user_id)
 on conflict(thread_id,user_id) do update set
  member_role=case when existing.left_at is null and existing.member_role<>'guardian_mirror' then existing.member_role else 'guardian_mirror' end,
  can_post=case when existing.left_at is null and existing.member_role<>'guardian_mirror' then existing.can_post else false end,left_at=null;
 if exists(select 1 from public.communication_thread_members m where m.thread_id=tid and m.left_at is null and m.member_role='guardian_mirror') then update public.communication_threads set guardian_mirrored=true where id=tid;end if;
end $function$;

CREATE OR REPLACE FUNCTION private.communication_scan_level(p_body text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    (select r.severity from public.communication_safety_rules r
      where r.active and lower(coalesce(p_body,'')) like '%'||lower(r.pattern)||'%'
      order by case r.severity when 'high' then 3 when 'medium' then 2 else 1 end desc limit 1),
    'none'
  );
$function$;

CREATE OR REPLACE FUNCTION private.communication_send_message(p_thread_id uuid, p_body text, p_kind text DEFAULT 'text'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid()); v_thread public.communication_threads%rowtype; v_id uuid; v_level text;
  v_rec record; v_sender text; v_title text; v_body text; v_normalized text; v_flag record; v_notification uuid;
  v_staff_sms boolean; v_sender_label text; v_sms_enabled boolean;
  v_adult_to_minor boolean:=false; v_boundary_alert boolean:=false; v_boundary_high boolean:=false;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_thread from public.communication_threads where id=p_thread_id and archived_at is null;
  if not found then raise exception 'Conversation not found'; end if;
  if not exists(
    select 1 from public.communication_thread_members m
    where m.thread_id=p_thread_id and m.user_id=v_user and m.left_at is null and m.can_post
  ) then raise exception 'You cannot post in this conversation'; end if;
  if v_thread.kind='direct' and exists(
    select 1 from public.communication_blocks b
    join public.communication_thread_members other on other.thread_id=p_thread_id and other.left_at is null and other.user_id<>v_user
    where b.team_id=v_thread.team_id and
      ((b.user_id=v_user and b.blocked_user_id=other.user_id)
       or (b.blocked_user_id=v_user and b.user_id=other.user_id))
  ) then raise exception 'This direct conversation is blocked'; end if;

  v_body=trim(coalesce(p_body,''));
  if char_length(v_body)<1 or char_length(v_body)>4000 then
    raise exception 'Messages must be between 1 and 4,000 characters';
  end if;
  if (select count(*) from public.communication_messages m where m.sender_user_id=v_user and m.created_at>now()-interval '1 minute')>=30 then
    raise exception 'Please pause before sending more messages';
  end if;

  v_normalized:=lower(translate(v_body,'’‘`',''''));
  v_level=private.communication_scan_level(v_normalized);
  v_adult_to_minor:=private.communication_authorized_adult(v_thread.team_id,v_user)
    and exists(
      select 1 from public.communication_thread_members m
      where m.thread_id=p_thread_id and m.left_at is null and m.user_id<>v_user
        and private.communication_user_is_minor(v_thread.team_id,m.user_id)
    );

  if v_adult_to_minor then
    if v_normalized ~ '(keep|this is).{0,24}(a )?secret'
       or v_normalized ~ '(don''?t|do not).{0,30}(tell|show).{0,25}(parent|parents|mom|dad|guardian|coach|anyone)'
       or v_normalized ~ '(parent|parents|mom|dad|guardian).{0,28}(don''?t|do not|doesn''?t|does not).{0,18}(need|have).{0,10}(to )?know'
       or v_normalized ~ 'no one.{0,12}(needs|has).{0,8}to know'
       or v_normalized ~ 'delete.{0,16}(message|messages|chat|conversation)' then
      v_boundary_alert:=true; v_boundary_high:=true;
    end if;
    if v_normalized ~ '(send|show|share|take).{0,24}(nude|nudes|naked|without clothes)'
       or v_normalized ~ '(nude|nudes|naked).{0,24}(photo|picture|pic|image)' then
      v_boundary_alert:=true; v_boundary_high:=true;
    end if;
    if v_body ~ '(^|[^0-9])(\+?1[ .-]?)?\(?[2-9][0-9]{2}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}([^0-9]|$)'
       or v_normalized ~ '(my|personal|cell|phone).{0,10}number.{0,8}(is|:)'
       or v_normalized ~ 'text me.{0,8}(at|on)' then
      v_boundary_alert:=true;
    end if;
    if v_normalized ~ '(dm|message|contact|add).{0,12}(me|my).{0,18}(snapchat|instagram|whatsapp|signal|telegram|discord)'
       or v_normalized ~ '(message|talk).{0,10}(privately|somewhere else|off app)' then
      v_boundary_alert:=true; v_boundary_high:=true;
    end if;
  end if;

  if v_boundary_high then v_level:='high';
  elsif v_boundary_alert and v_level in ('none','low') then v_level:='medium';
  end if;

  insert into public.communication_messages(thread_id,team_id,sender_user_id,body,message_kind,safety_level)
    values(p_thread_id,v_thread.team_id,v_user,v_body,p_kind,v_level) returning id into v_id;
  update public.communication_threads set last_message_at=now(),updated_at=now() where id=p_thread_id;
  insert into public.communication_message_receipts(message_id,user_id)
    select v_id,m.user_id from public.communication_thread_members m
    where m.thread_id=p_thread_id and m.left_at is null and m.user_id<>v_user
    on conflict do nothing;

  select coalesce(nullif(display_name,''),'A team member') into v_sender from public.profiles where id=v_user;
  v_sender=coalesce(v_sender,'A team member');
  v_title=case when p_kind='announcement' then 'Important team announcement' else coalesce(v_thread.title,'New team message') end;
  v_staff_sms:=p_kind<>'announcement' and v_thread.kind in ('team','all_members','group')
    and private.can_send_team_sms(v_thread.team_id,v_user);
  if v_staff_sms then v_sender_label:=private.sms_sender_label(v_thread.team_id,v_user); end if;

  for v_rec in
    select m.user_id,m.member_role,m.muted_until
    from public.communication_thread_members m
    where m.thread_id=p_thread_id and m.left_at is null and m.user_id<>v_user
  loop
    if p_kind<>'announcement' and v_rec.member_role='guardian_mirror'
       and exists (
         select 1 from public.communication_preferences cp
         where cp.team_id=v_thread.team_id and cp.user_id=v_rec.user_id
           and cp.guardian_alerts_only
       ) then
      -- Keep the guardian's read access and receipts; suppress routine alerts.
      -- Medium flags receive an urgent, content-free safety notice here.
      -- High and boundary flags use the existing safety path below.
      if v_level='medium' and not v_boundary_alert then
        perform private.communication_enqueue_notification(
          v_thread.team_id,v_rec.user_id,'safety','Safety review needed',
          'A message involving your athlete needs review.',p_thread_id,v_id,true
        );
      end if;
    else
      v_notification:=private.communication_enqueue_notification(
        v_thread.team_id,v_rec.user_id,
        case when p_kind='announcement' then 'announcement' else 'message' end,
        v_title,
        case when p_kind='announcement' then v_body else v_sender||': '||v_body end,
        p_thread_id,v_id,p_kind='announcement'
      );
      if p_kind<>'announcement' and v_rec.muted_until is not null and v_rec.muted_until>now() then
        delete from public.communication_delivery_queue where notification_id=v_notification;
      elsif v_staff_sms then
        select coalesce(cp.sms_message_fallback,true) into v_sms_enabled
        from public.communication_preferences cp
        where cp.team_id=v_thread.team_id and cp.user_id=v_rec.user_id;
        v_sms_enabled:=coalesce(v_sms_enabled,true);
        if v_sms_enabled then
          insert into public.communication_delivery_queue(notification_id,team_id,recipient_user_id,channel,payload)
          values(v_notification,v_thread.team_id,v_rec.user_id,'sms',
            jsonb_build_object(
              'title','New team chat post',
              'body',v_sender_label||' posted in '||coalesce(nullif(v_thread.title,''),'Team Chat')||'. Open Wrestling Manager to read it.',
              'category','message','thread_id',p_thread_id,'message_id',v_id,'urgent',false,
              'reply_mode','disabled','route_context','chat_alert'
            )
          ) on conflict do nothing;
        end if;
      end if;
    end if;
  end loop;

  for v_flag in
    select r.rule_code,r.severity
    from public.communication_safety_rules r
    where r.active and lower(v_normalized) like '%'||lower(r.pattern)||'%'
  loop
    insert into public.communication_safety_flags(message_id,team_id,rule_code,severity)
      values(v_id,v_thread.team_id,v_flag.rule_code,v_flag.severity) on conflict do nothing;
  end loop;

  if v_adult_to_minor then
    if v_normalized ~ '(keep|this is).{0,24}(a )?secret'
       or v_normalized ~ '(don''?t|do not).{0,30}(tell|show).{0,25}(parent|parents|mom|dad|guardian|coach|anyone)'
       or v_normalized ~ '(parent|parents|mom|dad|guardian).{0,28}(don''?t|do not|doesn''?t|does not).{0,18}(need|have).{0,10}(to )?know'
       or v_normalized ~ 'no one.{0,12}(needs|has).{0,8}to know'
       or v_normalized ~ 'delete.{0,16}(message|messages|chat|conversation)' then
      insert into public.communication_safety_flags(message_id,team_id,rule_code,severity)
        values(v_id,v_thread.team_id,'adult_minor_secrecy','high') on conflict do nothing;
    end if;
    if v_normalized ~ '(send|show|share|take).{0,24}(nude|nudes|naked|without clothes)'
       or v_normalized ~ '(nude|nudes|naked).{0,24}(photo|picture|pic|image)' then
      insert into public.communication_safety_flags(message_id,team_id,rule_code,severity)
        values(v_id,v_thread.team_id,'adult_minor_sexual_request','high') on conflict do nothing;
    end if;
    if v_body ~ '(^|[^0-9])(\+?1[ .-]?)?\(?[2-9][0-9]{2}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}([^0-9]|$)'
       or v_normalized ~ '(my|personal|cell|phone).{0,10}number.{0,8}(is|:)'
       or v_normalized ~ 'text me.{0,8}(at|on)' then
      insert into public.communication_safety_flags(message_id,team_id,rule_code,severity)
        values(v_id,v_thread.team_id,'adult_minor_phone_exchange','medium') on conflict do nothing;
    end if;
    if v_normalized ~ '(dm|message|contact|add).{0,12}(me|my).{0,18}(snapchat|instagram|whatsapp|signal|telegram|discord)'
       or v_normalized ~ '(message|talk).{0,10}(privately|somewhere else|off app)' then
      insert into public.communication_safety_flags(message_id,team_id,rule_code,severity)
        values(v_id,v_thread.team_id,'adult_minor_off_platform','high') on conflict do nothing;
    end if;
  end if;

  if v_level='high' or v_boundary_alert then
    for v_rec in
      select distinct ag.guardian_user_id as user_id
      from public.communication_thread_members minor_member
      join public.team_memberships athlete_tm
        on athlete_tm.team_id=v_thread.team_id and athlete_tm.user_id=minor_member.user_id
        and athlete_tm.role='athlete' and athlete_tm.active=true
      join public.athlete_guardians ag on ag.athlete_id=athlete_tm.athlete_id
      where minor_member.thread_id=p_thread_id and minor_member.left_at is null
        and private.communication_user_is_minor(v_thread.team_id,minor_member.user_id)
        and ag.guardian_user_id is not null and ag.guardian_user_id<>v_user
    loop
      perform private.communication_enqueue_notification(
        v_thread.team_id,v_rec.user_id,'safety','Safety review needed',
        'A message involving your athlete needs review.',p_thread_id,v_id,true
      );
    end loop;

    for v_rec in
      select distinct tm.user_id
      from public.team_memberships tm
      where tm.team_id=v_thread.team_id and tm.active=true and tm.user_id<>v_user
        and private.communication_user_is_staff(v_thread.team_id,tm.user_id)
    loop
      perform private.communication_enqueue_notification(
        v_thread.team_id,v_rec.user_id,'safety','Team safety review needed',
        'A safeguarded conversation triggered a safety review.',p_thread_id,v_id,true
      );
    end loop;
  end if;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.communication_user_belongs_to_team(p_team_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from public.team_memberships tm
    where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true
  ) or exists(
    select 1 from public.teams t
    join public.organization_memberships om on om.organization_id=t.organization_id
    where t.id=p_team_id and om.user_id=p_user_id and om.role='organization_admin'
  ) or exists(
    select 1 from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.team_id=p_team_id and ag.guardian_user_id=p_user_id
  );
$function$;

CREATE OR REPLACE FUNCTION private.communication_user_is_guardian_of(p_team_id uuid, p_guardian uuid, p_minor_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from public.team_memberships tm
    join public.athlete_guardians ag on ag.athlete_id=tm.athlete_id
    where tm.team_id=p_team_id and tm.user_id=p_minor_user and tm.role='athlete' and tm.active=true and ag.guardian_user_id=p_guardian
  );
$function$;

CREATE OR REPLACE FUNCTION private.communication_user_is_minor(p_team_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1
    from public.team_memberships tm
    join public.athletes a on a.id=tm.athlete_id
    where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true and tm.role='athlete'
      and (a.birth_date is null or a.birth_date > current_date - interval '18 years')
  );
$function$;

CREATE OR REPLACE FUNCTION private.communication_user_is_staff(p_team_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from public.team_memberships tm
    where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true
      and (tm.role in ('head_coach','assistant_coach')
        or (tm.role='manager' and coalesce((tm.permissions->>'team_admin')::boolean,false)))
  ) or exists(
    select 1 from public.teams t
    join public.organization_memberships om on om.organization_id=t.organization_id
    where t.id=p_team_id and om.user_id=p_user_id and om.role='organization_admin'
  );
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_admin(tid uuid, uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select uid is not null and not exists(select 1 from private.team_logins where user_id=uid) and (
 exists(select 1 from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active
  and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and m.permissions->>'team_admin'='true')))
 or exists(select 1 from public.teams t join public.organization_memberships o on o.organization_id=t.organization_id
  where t.id=tid and o.user_id=uid and o.role='organization_admin'))
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_adult(tid uuid, uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select uid is not null and not exists(select 1 from private.team_logins where user_id=uid)
 and exists(select 1 from auth.users u where u.id=uid and u.email_confirmed_at is not null)
 and exists(select 1 from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active
  and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->>'staff_role' in ('team_mom','team_leader','volunteer_coach','club_president','limited_staff'))))
 and not exists(select 1 from public.team_memberships own join public.athletes a on a.id=own.athlete_id
  left join public.athlete_private_identity i on i.athlete_id=a.id where own.user_id=uid and own.role='athlete'
  and (coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'
    or (own.active and coalesce(i.birth_date,a.birth_date) is null)))
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_assigned(tid uuid, uid uuid, accepted boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from private.conversation_review_settings where id and enabled)
 and private.conversation_review_adult(tid,uid)
 and exists(select 1 from private.conversation_reviewers r join public.team_memberships m on m.id=r.membership_id
  where r.team_id=tid and r.user_id=uid and r.active and (not accepted or r.accepted_at is not null)
  and m.team_id=tid and m.user_id=uid and m.active
  and r.role_key=case when m.role='manager' then m.permissions->>'staff_role' else m.role::text end
  and private.conversation_review_admin(tid,r.approved_by))
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_can_view(th uuid, uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select private.conversation_review_covered(th) and exists(select 1 from public.communication_threads t
 where t.id=th and private.conversation_review_assigned(t.team_id,uid))
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_covered(th uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.communication_threads t where t.id=th and t.kind in ('direct','group')
 and t.archived_at is null and not coalesce(t.is_safety_test,false)
 and exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null
   and m.member_role='participant' and private.conversation_review_minor(t.team_id,m.user_id))
 and exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null
   and m.member_role='participant' and private.communication_authorized_adult(t.team_id,m.user_id)
   and not private.conversation_review_minor(t.team_id,m.user_id)
   and not exists(select 1 from private.team_logins where user_id=m.user_id)))
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_minor(tid uuid, uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
 left join public.athlete_private_identity i on i.athlete_id=a.id
 where m.team_id=tid and m.user_id=uid and m.role='athlete' and m.active
 and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'))
$function$;

CREATE OR REPLACE FUNCTION private.conversation_review_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid=auth.uid();tid uuid;uid uuid;th uuid;mem public.team_memberships%rowtype;
 result jsonb;admin boolean;offset_value integer;before_time timestamptz;before_id uuid;
begin
 if actor is null or exists(select 1 from private.team_logins where user_id=actor) then raise exception 'Use your personal account.' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'Invalid review request.';end if;
 tid:=nullif(p_data->>'team_id','')::uuid;th:=nullif(p_data->>'thread_id','')::uuid;
 if th is not null then select team_id into tid from public.communication_threads where id=th;end if;
 if tid is null or not private.communication_user_belongs_to_team(tid,actor) then raise exception 'Team access required.' using errcode='42501';end if;
 admin:=private.conversation_review_admin(tid,actor);
 if p_action='context' then
  return jsonb_build_object('enabled',exists(select 1 from private.conversation_review_settings where id and enabled),
   'admin',admin,'assigned',private.conversation_review_assigned(tid,actor,false),'accepted',private.conversation_review_assigned(tid,actor));
 end if;
 if not exists(select 1 from private.conversation_review_settings where id and enabled) then raise exception 'Conversation review is not enabled yet.';end if;
 if p_action='observers' then
  if th is null or not(private.communication_can_view_thread(th,actor) or private.conversation_review_can_view(th,actor)) then raise exception 'Conversation access required.';end if;
  select coalesce(jsonb_agg(jsonb_build_object('name',private.communication_person_name(tid,r.user_id),'role',r.role_key) order by r.approved_at),'[]') into result
  from private.conversation_reviewers r where r.team_id=tid and private.conversation_review_assigned(tid,r.user_id)
   and private.conversation_review_covered(th);
  return result;
 elsif p_action='manage' then
  if not admin then raise exception 'Team administrator access required.' using errcode='42501';end if;
  select coalesce(jsonb_agg(x.item order by x.item->>'name'),'[]') into result from (
   select distinct on(m.user_id) jsonb_build_object('user_id',m.user_id,'name',private.communication_person_name(tid,m.user_id),
    'role',case when m.role='manager' then m.permissions->>'staff_role' else m.role::text end,
    'assigned',coalesce(r.active,false),'accepted',private.conversation_review_assigned(tid,m.user_id),
    'eligible',private.conversation_review_adult(tid,m.user_id)) item
   from public.team_memberships m left join private.conversation_reviewers r on r.team_id=tid and r.user_id=m.user_id
   where m.team_id=tid and m.active and m.role in ('head_coach','assistant_coach','manager')
    and not exists(select 1 from private.team_logins where user_id=m.user_id)
   order by m.user_id,case m.role when 'head_coach' then 1 when 'assistant_coach' then 2 else 3 end,m.id
  ) x;
  return result;
 elsif p_action in ('assign','revoke','accept','leave') then
  if p_action in ('assign','revoke') then
   if not admin then raise exception 'Team administrator access required.' using errcode='42501';end if;
   uid:=nullif(p_data->>'user_id','')::uuid;
  else uid:=actor;end if;
  if uid is null then raise exception 'Choose an adult team member.';end if;
  perform 1 from public.teams where id=tid for update;
  if p_action in ('assign','revoke') and not private.conversation_review_admin(tid,actor) then raise exception 'Team administrator access required.';end if;
  if p_action='assign' then
   if p_data->'confirm_adult' is distinct from 'true'::jsonb then raise exception 'Verify this adult and their authority under your team policies.';end if;
   if not private.conversation_review_adult(tid,uid) then raise exception 'Choose a confirmed personal adult staff account. Check any under-18 or unknown-age athlete membership.';end if;
   select * into mem from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active
    and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->>'staff_role' in ('team_mom','team_leader','volunteer_coach','club_president','limited_staff')))
    order by case m.role when 'head_coach' then 1 when 'assistant_coach' then 2 else 3 end,m.id limit 1;
   insert into private.conversation_reviewers(team_id,user_id,membership_id,role_key,approved_by)
   values(tid,uid,mem.id,case when mem.role='manager' then mem.permissions->>'staff_role' else mem.role::text end,actor)
   on conflict(team_id,user_id) do update set membership_id=excluded.membership_id,role_key=excluded.role_key,
    approved_by=actor,approved_at=clock_timestamp(),active=true,accepted_at=null;
  elsif p_action='accept' then
   if p_data->'acknowledge' is distinct from 'true'::jsonb or not private.conversation_review_assigned(tid,actor,false) then raise exception 'Review the responsibility statement and confirm your assignment.';end if;
   update private.conversation_reviewers set accepted_at=clock_timestamp() where team_id=tid and user_id=actor and active;
  else
   update private.conversation_reviewers set active=false,accepted_at=null where team_id=tid and user_id=uid;
   if not found then raise exception 'Reviewer assignment not found.';end if;
  end if;
  insert into private.conversation_review_events(team_id,actor_id,subject_id,event)
  values(tid,actor,uid,case p_action when 'assign' then 'assigned' when 'accept' then 'accepted' when 'revoke' then 'revoked' else 'left' end);
  return jsonb_build_object('saved',true);
 elsif p_action='inbox' then
  if not private.conversation_review_assigned(tid,actor) then raise exception 'An accepted, current adult reviewer assignment is required.' using errcode='42501';end if;
  offset_value:=least(greatest(coalesce((p_data->>'offset')::integer,0),0),5000);
  select coalesce(jsonb_agg(x.item order by x.last_at desc,x.id),'[]') into result from (
   select t.id,coalesce(lm.created_at,t.created_at) last_at,jsonb_build_object('id',t.id,
    'title',coalesce(nullif(t.title,''),(select string_agg(private.communication_person_name(tid,m.user_id),' · ' order by m.joined_at) from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null and m.member_role='participant'),'Conversation'),
    'last_at',coalesce(lm.created_at,t.created_at),'safety_flags',(select count(*) from public.communication_messages msg where msg.thread_id=t.id and msg.deleted_at is null and msg.safety_level in ('medium','high'))) item
   from public.communication_threads t left join lateral(select created_at from public.communication_messages where thread_id=t.id order by created_at desc limit 1) lm on true
   where t.team_id=tid and private.conversation_review_covered(t.id)
   order by coalesce(lm.created_at,t.created_at) desc,t.id limit 51 offset offset_value
  ) x;
  return result;
 elsif p_action='media' then
  if th is null or not private.conversation_review_can_view(th,actor) then raise exception 'Reviewer access ended.' using errcode='42501';end if;
  select jsonb_build_object('path',a.storage_path) into result
  from public.communication_attachments a join public.communication_messages m on m.id=a.message_id and m.thread_id=a.thread_id
  where a.id=nullif(p_data->>'attachment_id','')::uuid and a.thread_id=th and a.removed_at is null and m.deleted_at is null
   and split_part(a.storage_path,'/',1)=tid::text
   and exists(select 1 from public.communication_threads source where source.id::text=split_part(a.storage_path,'/',2)
    and source.team_id=tid and coalesce(source.merged_into_thread_id,source.id)=th);
  if result is null then raise exception 'This media is unavailable.' using errcode='42501';end if;
  return result;
 elsif p_action='check' then
  if th is null or not private.conversation_review_can_view(th,actor) then raise exception 'Reviewer access ended.' using errcode='42501';end if;
  return jsonb_build_object('allowed',true);
 elsif p_action='messages' then
  if th is null or not private.conversation_review_can_view(th,actor) then raise exception 'Reviewer access to this conversation is required.' using errcode='42501';end if;
  before_time:=nullif(p_data->>'before_at','')::timestamptz;before_id:=nullif(p_data->>'before_id','')::uuid;
  if (before_time is null)<>(before_id is null) then raise exception 'Invalid message page.';end if;
  select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id desc),'[]') into result from (
   select m.id,m.created_at,jsonb_build_object('id',m.id,'at',m.created_at,'sender',private.communication_person_name(tid,m.sender_user_id),
    'body',case when m.deleted_at is null then m.body else 'Message removed' end,'safety_level',m.safety_level,
    'attachments',case when m.deleted_at is not null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'mime',a.mime_type,'name',a.file_name)) from public.communication_attachments a where a.message_id=m.id and a.thread_id=th and a.removed_at is null),'[]'::jsonb) end) item
   from public.communication_messages m where m.thread_id=th and (before_time is null or (m.created_at,m.id)<(before_time,before_id))
   order by m.created_at desc,m.id desc limit 81
  ) x;
  insert into private.conversation_review_events(team_id,actor_id,event,thread_id)
   select tid,actor,'viewed',th where not exists(select 1 from private.conversation_review_events where team_id=tid and actor_id=actor and thread_id=th and event='viewed' and created_at>now()-interval '5 minutes');
  return result;
 end if;
 raise exception 'Unsupported reviewer action.';
end $function$;

CREATE OR REPLACE FUNCTION private.parent_browser_service(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare inv public.guardian_invitations%rowtype; g public.athlete_guardians%rowtype;
 link private.parent_browser_links%rowtype; v private.parent_browser_verifications%rowtype;
 perm private.parent_browser_permissions%rowtype; hash text; email_value text; result jsonb;
 eligible boolean; aid uuid; pid uuid; used timestamptz;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service authentication required.' using errcode='42501';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'Invalid request.';end if;
 if p_action='email_mode' then return jsonb_build_object('enabled',exists(select 1 from private.parent_browser_settings where id and enabled));end if;
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
end $function$;

CREATE OR REPLACE FUNCTION private.parent_browser_verification_valid(p_guardian uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.parent_browser_verify(p_guardian uuid, p_team uuid, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION private.profile_approval_policy(p_profile uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

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

CREATE OR REPLACE FUNCTION private.sms_sender_label(p_team_id uuid, p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_name text; v_role text; v_last text; v_prefix text;
begin
  select coalesce(nullif(tsp.display_name,''),nullif(p.display_name,''),'Team Staff'),
         coalesce(nullif(tm.permissions->>'staff_role',''),tm.role)
  into v_name,v_role
  from public.team_memberships tm
  left join public.team_staff_profiles tsp on tsp.team_id=tm.team_id and tsp.user_id=tm.user_id
  left join public.profiles p on p.id=tm.user_id
  where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true
  order by case tm.role when 'head_coach' then 1 when 'assistant_coach' then 2 when 'manager' then 3 else 9 end
  limit 1;
  if v_name is null then
    select coalesce(nullif(tsp.display_name,''),nullif(p.display_name,''),'Team Staff') into v_name
    from public.profiles p left join public.team_staff_profiles tsp on tsp.team_id=p_team_id and tsp.user_id=p.id
    where p.id=p_user_id;
  end if;
  v_name:=coalesce(v_name,'Team Staff');
  v_last:=regexp_replace(trim(v_name),'^.*\s+','');
  v_prefix:=case
    when v_role in ('head_coach','assistant_coach','volunteer_coach') then 'Coach'
    when v_role='team_leader' then 'Team Leader'
    when v_role='team_mom' then 'Team Mom'
    when v_role='club_president' then 'Club President'
    else 'Team Staff'
  end;
  return trim(v_prefix||' '||v_last);
end;
$function$;

CREATE OR REPLACE FUNCTION public.athlete_on_team(check_athlete_id uuid, check_team_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.roster_memberships rm
    join public.seasons s on s.id=rm.season_id
    where rm.athlete_id=check_athlete_id
      and s.team_id=check_team_id
      and rm.active=true
      and rm.roster_status not in ('inactive','standby','removed')
  )
  or exists (
    select 1
    from public.team_memberships tm
    where tm.team_id=check_team_id
      and tm.athlete_id=check_athlete_id
      and tm.role='athlete'
      and tm.active=true
  );
$function$;

CREATE OR REPLACE FUNCTION public.communication_members_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.communication_members_request(p_action,p_data); $function$;

CREATE OR REPLACE FUNCTION public.conversation_review_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.conversation_review_request(p_action,p_data)$function$;

CREATE OR REPLACE FUNCTION public.create_communication_thread(p_team_id uuid, p_season_id uuid, p_title text, p_participant_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_id uuid;
  v_ids uuid[];
  v_target uuid;
  v_minor uuid;
  v_guardians integer;
  v_kind text;
  v_adults boolean;
  v_other uuid;
  v_direct_key text;
begin
  if v_user is null or not private.communication_user_belongs_to_team(p_team_id,v_user) then
    raise exception 'Team access required';
  end if;

  select array_agg(distinct x order by x)
  into v_ids
  from unnest(coalesce(p_participant_ids,'{}'::uuid[])||array[v_user]) x
  where x is not null;

  if cardinality(v_ids)<2 then
    raise exception 'Choose at least one teammate';
  end if;

  foreach v_target in array v_ids loop
    if not private.communication_user_belongs_to_team(p_team_id,v_target) then
      raise exception 'Every participant must belong to this team';
    end if;
  end loop;

  if exists(
    select 1
    from public.communication_blocks b
    where b.team_id=p_team_id
      and ((b.user_id=v_user and b.blocked_user_id=any(v_ids))
        or (b.blocked_user_id=v_user and b.user_id=any(v_ids)))
  ) then
    raise exception 'This conversation cannot be created because a participant is blocked';
  end if;

  v_kind:=case when cardinality(v_ids)=2 then 'direct' else 'group' end;

  if v_kind='direct' then
    if (select count(*) from unnest(v_ids) x where private.communication_user_is_minor(p_team_id,x))=2 then
      foreach v_target in array v_ids loop
        if not private.communication_minor_capability(p_team_id,v_target,'peer_to_peer') then
          raise exception 'Parent approval is required for athlete-to-athlete direct chat';
        end if;
      end loop;
    elsif exists(select 1 from unnest(v_ids) x where private.communication_user_is_minor(p_team_id,x)) then
      select x into v_minor
      from unnest(v_ids) x
      where private.communication_user_is_minor(p_team_id,x)
      limit 1;

      select x into v_other
      from unnest(v_ids) x
      where x<>v_minor
      limit 1;

      if not private.communication_minor_capability(p_team_id,v_minor,'coach_to_athlete') then
        raise exception 'Parent approval is required for coach-to-athlete direct chat';
      end if;

      if not private.communication_authorized_adult(p_team_id,v_other)
         and not private.communication_user_is_guardian_of(p_team_id,v_other,v_minor) then
        raise exception 'Only an authorized coach, team leader, or the athlete guardian may directly message this minor';
      end if;
    end if;
  else
    for v_minor in
      select x from unnest(v_ids) x
      where private.communication_user_is_minor(p_team_id,x)
    loop
      if not private.communication_minor_capability(p_team_id,v_minor,'group_chat') then
        raise exception 'Parent approval is required before this athlete can join a group chat';
      end if;
    end loop;
  end if;

  select exists(
    select 1 from unnest(v_ids) x
    where not private.communication_user_is_minor(p_team_id,x)
  ) into v_adults;

  if v_kind='direct' then
    v_direct_key:=private.communication_direct_participant_key(v_ids);

    -- Serialize creation for this exact team/person pair. The partial unique
    -- index remains the final invariant if another code path is added later.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext(p_team_id::text),
      pg_catalog.hashtext(v_direct_key)
    );

    select t.id into v_id
    from public.communication_threads t
    where t.team_id=p_team_id
      and t.kind='direct'
      and t.archived_at is null
      and not coalesce(t.is_safety_test,false)
      and t.direct_participant_key=v_direct_key
    order by t.created_at,t.id
    limit 1;
  end if;

  if v_id is null then
    insert into public.communication_threads(
      team_id,season_id,kind,title,guardian_mirrored,created_by,
      direct_participant_key
    )
    values(
      p_team_id,
      case when v_kind='direct' then null else p_season_id end,
      v_kind,
      nullif(left(trim(coalesce(p_title,'')),120),''),
      false,
      v_user,
      v_direct_key
    )
    returning id into v_id;

    insert into public.communication_thread_members(
      thread_id,user_id,member_role,can_post,added_by
    )
    select v_id,x,'participant',true,v_user
    from unnest(v_ids) x;
  else
    insert into public.communication_thread_members(
      thread_id,user_id,member_role,can_post,added_by
    )
    select v_id,x,'participant',true,v_user
    from unnest(v_ids) x
    on conflict(thread_id,user_id) do update set
      member_role='participant',
      can_post=true,
      left_at=null;

    -- Starting an existing conversation makes it visible again for the person
    -- who deliberately opened it. Other users' hidden state is preserved until
    -- a new message arrives.
    update public.communication_thread_members
    set hidden_at=null
    where thread_id=v_id and user_id=v_user;
  end if;

  if v_adults then
    for v_minor in
      select x from unnest(v_ids) x
      where private.communication_user_is_minor(p_team_id,x)
    loop
      insert into public.communication_thread_members as existing_member(
        thread_id,user_id,member_role,can_post,added_by
      )
      select distinct
        v_id,ag.guardian_user_id,'guardian_mirror',false,v_user
      from public.team_memberships athlete_tm
      join public.athlete_guardians ag on ag.athlete_id=athlete_tm.athlete_id
      where athlete_tm.team_id=p_team_id
        and athlete_tm.user_id=v_minor
        and athlete_tm.role='athlete'
        and athlete_tm.active=true
        and ag.guardian_user_id is not null
      on conflict(thread_id,user_id) do update set
        member_role=case
          when existing_member.member_role='participant'
            then 'participant'
          else 'guardian_mirror'
        end,
        can_post=case
          when existing_member.member_role='participant'
            then existing_member.can_post
          else false
        end,
        left_at=null;

      get diagnostics v_guardians=row_count;

      if v_guardians=0 and not exists(
        select 1
        from public.team_memberships athlete_tm
        join public.athlete_guardians ag
          on ag.athlete_id=athlete_tm.athlete_id
         and ag.guardian_user_id is not null
        join public.communication_thread_members m
          on m.thread_id=v_id
         and m.user_id=ag.guardian_user_id
         and m.left_at is null
        where athlete_tm.team_id=p_team_id
          and athlete_tm.user_id=v_minor
          and athlete_tm.role='athlete'
          and athlete_tm.active=true
      ) then
        raise exception 'A connected parent or guardian is required before an adult can message this minor';
      end if;

      update public.communication_threads
      set guardian_mirrored=true
      where id=v_id;
    end loop;
  end if;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_team_communication_channels(p_team_id uuid, p_season_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_team uuid; v_staff uuid; v_parents uuid; v_all uuid; v_ann uuid;
begin
  if v_user is null or not private.communication_user_belongs_to_team(p_team_id,v_user) then
    raise exception 'Team access required';
  end if;

  insert into public.communication_threads(team_id,season_id,kind,system_key,title,created_by)
    values(p_team_id,p_season_id,'team','team-chat','Team Chat',v_user) on conflict do nothing;
  insert into public.communication_threads(team_id,season_id,kind,system_key,title,created_by)
    values(p_team_id,p_season_id,'staff','staff-chat','Coaches Chat',v_user) on conflict do nothing;
  insert into public.communication_threads(team_id,season_id,kind,system_key,title,created_by)
    values(p_team_id,p_season_id,'parents','parent-chat','Parent Chat',v_user) on conflict do nothing;
  insert into public.communication_threads(team_id,season_id,kind,system_key,title,created_by)
    values(p_team_id,p_season_id,'all_members','all-members-chat','All Members',v_user) on conflict do nothing;
  insert into public.communication_threads(team_id,season_id,kind,system_key,title,created_by)
    values(p_team_id,p_season_id,'announcements','announcements','Announcements',v_user) on conflict do nothing;

  select id into v_team from public.communication_threads where team_id=p_team_id and season_id is not distinct from p_season_id and system_key='team-chat';
  select id into v_staff from public.communication_threads where team_id=p_team_id and season_id is not distinct from p_season_id and system_key='staff-chat';
  select id into v_parents from public.communication_threads where team_id=p_team_id and season_id is not distinct from p_season_id and system_key='parent-chat';
  select id into v_all from public.communication_threads where team_id=p_team_id and season_id is not distinct from p_season_id and system_key='all-members-chat';
  select id into v_ann from public.communication_threads where team_id=p_team_id and season_id is not distinct from p_season_id and system_key='announcements';

  -- Serialize automatic refresh with deliberate membership edits.
  perform 1 from public.communication_threads where id=any(array[v_team,v_staff,v_parents,v_all,v_ann]) order by id for update;

  update public.communication_threads set kind='team',title='Team Chat' where id=v_team;
  update public.communication_threads set kind='staff',title='Coaches Chat' where id=v_staff;
  update public.communication_threads set kind='parents',title='Parent Chat' where id=v_parents;
  update public.communication_threads set kind='all_members',title='All Members' where id=v_all;
  update public.communication_threads set kind='announcements',title='Announcements' where id=v_ann;

  with participants as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and (
        (tm.role='athlete' and (not private.communication_user_is_minor(p_team_id,tm.user_id)
          or private.communication_minor_capability(p_team_id,tm.user_id,'team_chat')))
        or private.communication_authorized_adult(p_team_id,tm.user_id)
      )
  ), guardians as (
    select distinct ag.guardian_user_id as user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.team_memberships atm on atm.team_id=s.team_id and atm.athlete_id=rm.athlete_id and atm.role='athlete' and atm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
      and private.communication_user_is_minor(p_team_id,atm.user_id)
      and not exists(select 1 from participants p where p.user_id=ag.guardian_user_id)
  ), desired as (
    select user_id,'participant'::text member_role,true can_post from participants
    union all
    select user_id,'guardian_mirror'::text,false from guardians
  )
  insert into public.communication_thread_members(thread_id,user_id,member_role,can_post,added_by)
  select v_team,d.user_id,d.member_role,d.can_post,v_user from desired d
  on conflict(thread_id,user_id) do update
    set left_at=null,member_role=excluded.member_role,can_post=excluded.can_post;

  with participants as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and (
        (tm.role='athlete' and (not private.communication_user_is_minor(p_team_id,tm.user_id)
          or private.communication_minor_capability(p_team_id,tm.user_id,'team_chat')))
        or private.communication_authorized_adult(p_team_id,tm.user_id)
      )
  ), guardians as (
    select distinct ag.guardian_user_id as user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.team_memberships atm on atm.team_id=s.team_id and atm.athlete_id=rm.athlete_id and atm.role='athlete' and atm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
      and private.communication_user_is_minor(p_team_id,atm.user_id)
      and not exists(select 1 from participants p where p.user_id=ag.guardian_user_id)
  ), desired as (
    select user_id from participants union select user_id from guardians
  )
  update public.communication_thread_members m set left_at=now(),can_post=false
  where m.thread_id=v_team and m.left_at is null
    and not exists(select 1 from desired d where d.user_id=m.user_id);

  with desired as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and tm.role in ('head_coach','assistant_coach')
  )
  insert into public.communication_thread_members(thread_id,user_id,member_role,can_post,added_by)
  select v_staff,d.user_id,'participant',true,v_user from desired d
  on conflict(thread_id,user_id) do update
    set left_at=null,member_role='participant',can_post=true;

  with desired as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and tm.role in ('head_coach','assistant_coach')
  )
  update public.communication_thread_members m set left_at=now(),can_post=false
  where m.thread_id=v_staff and m.left_at is null
    and not exists(select 1 from desired d where d.user_id=m.user_id);

  with desired as (
    select tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.role='parent_guardian' and tm.user_id is not null
    union
    select ag.guardian_user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
  )
  insert into public.communication_thread_members(thread_id,user_id,member_role,can_post,added_by)
  select v_parents,d.user_id,'participant',true,v_user from desired d
  on conflict(thread_id,user_id) do update
    set left_at=null,member_role='participant',can_post=true;

  with desired as (
    select tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.role='parent_guardian' and tm.user_id is not null
    union
    select ag.guardian_user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
  )
  update public.communication_thread_members m set left_at=now(),can_post=false
  where m.thread_id=v_parents and m.left_at is null
    and not exists(select 1 from desired d where d.user_id=m.user_id);

  with desired as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and (tm.role<>'athlete'
        or not private.communication_user_is_minor(p_team_id,tm.user_id)
        or private.communication_minor_capability(p_team_id,tm.user_id,'team_chat'))
    union
    select ag.guardian_user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
  )
  insert into public.communication_thread_members(thread_id,user_id,member_role,can_post,added_by)
  select v_all,d.user_id,'participant',true,v_user from desired d
  on conflict(thread_id,user_id) do update
    set left_at=null,member_role='participant',can_post=true;

  with desired as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and (tm.role<>'athlete'
        or not private.communication_user_is_minor(p_team_id,tm.user_id)
        or private.communication_minor_capability(p_team_id,tm.user_id,'team_chat'))
    union
    select ag.guardian_user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
  )
  update public.communication_thread_members m set left_at=now(),can_post=false
  where m.thread_id=v_all and m.left_at is null
    and not exists(select 1 from desired d where d.user_id=m.user_id);

  with desired as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and (tm.role<>'athlete'
        or not private.communication_user_is_minor(p_team_id,tm.user_id)
        or private.communication_minor_capability(p_team_id,tm.user_id,'team_chat'))
    union
    select ag.guardian_user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
  )
  insert into public.communication_thread_members(thread_id,user_id,member_role,can_post,added_by)
  select v_ann,d.user_id,'participant',private.communication_authorized_adult(p_team_id,d.user_id),v_user from desired d
  on conflict(thread_id,user_id) do update
    set left_at=null,member_role='participant',can_post=excluded.can_post;

  with desired as (
    select distinct tm.user_id
    from public.team_memberships tm
    where tm.team_id=p_team_id and tm.active=true and tm.user_id is not null
      and (tm.role<>'athlete'
        or not private.communication_user_is_minor(p_team_id,tm.user_id)
        or private.communication_minor_capability(p_team_id,tm.user_id,'team_chat'))
    union
    select ag.guardian_user_id
    from public.seasons s
    join public.roster_memberships rm on rm.season_id=s.id and rm.active=true
    join public.athlete_guardians ag on ag.athlete_id=rm.athlete_id
    where s.id=p_season_id and s.team_id=p_team_id and ag.guardian_user_id is not null
  )
  update public.communication_thread_members m set left_at=now(),can_post=false
  where m.thread_id=v_ann and m.left_at is null
    and not exists(select 1 from desired d where d.user_id=m.user_id);

  perform private.communication_restore_required_mirrors(v_team);
  perform private.communication_restore_required_mirrors(v_all);

  return jsonb_build_object(
    'team_thread_id',case when exists(select 1 from public.communication_thread_members m where m.thread_id=v_team and m.user_id=v_user and m.left_at is null) then v_team else null end,
    'staff_thread_id',case when exists(select 1 from public.communication_thread_members m where m.thread_id=v_staff and m.user_id=v_user and m.left_at is null) then v_staff else null end,
    'parent_thread_id',case when exists(select 1 from public.communication_thread_members m where m.thread_id=v_parents and m.user_id=v_user and m.left_at is null) then v_parents else null end,
    'all_members_thread_id',case when exists(select 1 from public.communication_thread_members m where m.thread_id=v_all and m.user_id=v_user and m.left_at is null) then v_all else null end,
    'announcement_thread_id',case when exists(select 1 from public.communication_thread_members m where m.thread_id=v_ann and m.user_id=v_user and m.left_at is null) then v_ann else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_communication_media_access(p_thread_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_thread public.communication_threads%rowtype;
  v_member public.communication_thread_members%rowtype;
  v_minor boolean;
  v_view boolean;
  v_send boolean;
  v_reason text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select * into v_thread
  from public.communication_threads t
  where t.id=p_thread_id and t.archived_at is null;
  if not found then raise exception 'Conversation not found'; end if;

  select * into v_member
  from public.communication_thread_members m
  where m.thread_id=p_thread_id and m.user_id=v_user and m.left_at is null;
  if not found then raise exception 'Conversation access required'; end if;

  v_minor:=private.communication_user_is_minor(v_thread.team_id,v_user);
  v_view:=not v_minor or private.communication_minor_capability(v_thread.team_id,v_user,'media_view');
  v_send:=v_member.can_post and (
    not v_minor or private.communication_minor_capability(
      v_thread.team_id,
      v_user,
      case when v_thread.kind='direct' then 'media_send_direct' else 'media_send_group' end
    )
  );

  if not v_member.can_post then
    v_reason:='This is a read-only safeguarded view.';
  elsif v_minor and not v_send then
    v_reason:=case when v_thread.kind='direct'
      then 'A parent or guardian has not enabled media sending in private chats.'
      else 'A parent or guardian has not enabled media sending in group chats.'
    end;
  else
    v_reason:='';
  end if;

  return jsonb_build_object(
    'can_view',v_view,
    'can_send',v_send,
    'thread_kind',v_thread.kind,
    'reason',v_reason
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.is_team_staff(check_team_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.team_memberships tm
    where tm.team_id=check_team_id
      and tm.user_id=(select auth.uid())
      and tm.active=true
      and (
        tm.role in ('head_coach','assistant_coach')
        or (
          tm.role='manager'
          and coalesce((tm.permissions->>'team_admin')::boolean,false)
        )
      )
  )
  or exists (
    select 1
    from public.teams t
    join public.organization_memberships om on om.organization_id=t.organization_id
    where t.id=check_team_id
      and om.user_id=(select auth.uid())
      and om.role='organization_admin'
  );
$function$;

CREATE OR REPLACE FUNCTION public.parent_browser_service(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.parent_browser_service(p_action,p_data)$function$;

CREATE OR REPLACE FUNCTION public.parent_browser_verify(p_guardian uuid, p_team uuid, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.parent_browser_verify(p_guardian,p_team,p_confirm)$function$;

CREATE OR REPLACE FUNCTION public.send_communication_attachment(p_thread_id uuid, p_storage_path text, p_mime_type text, p_file_name text, p_size_bytes bigint, p_caption text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_thread public.communication_threads%rowtype;
  v_message uuid;
  v_body text;
  v_review boolean:=false;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not private.can_upload_communication_media_object(p_storage_path) then
    raise exception 'Media sending is not allowed for this account or conversation';
  end if;

  select * into v_thread
  from public.communication_threads t
  where t.id=p_thread_id and t.archived_at is null;
  if not found then raise exception 'Conversation not found'; end if;

  if p_storage_path not like v_thread.team_id::text||'/'||p_thread_id::text||'/'||v_user::text||'/%' then
    raise exception 'Invalid media path';
  end if;
  if p_mime_type not in ('image/jpeg','image/png','image/webp','image/heic','image/heif','video/mp4','video/quicktime') then
    raise exception 'Unsupported photo or video format';
  end if;
  if p_size_bytes is null or p_size_bytes<=0 or p_size_bytes>52428800 then
    raise exception 'Media file is too large';
  end if;
  if p_mime_type like 'image/%' and p_size_bytes>12582912 then
    raise exception 'Photos must be 12 MB or smaller';
  end if;
  if not exists(
    select 1 from storage.objects o
    where o.bucket_id='communication-media' and o.name=p_storage_path
  ) then raise exception 'Uploaded media was not found'; end if;

  v_body:=nullif(left(trim(coalesce(p_caption,'')),4000),'');
  if v_body is null then
    v_body:=case when p_mime_type like 'video/%' then '[Video]' else '[Photo]' end;
  end if;

  v_review:=v_thread.kind='direct' and exists(
    select 1
    from public.communication_thread_members m
    where m.thread_id=p_thread_id and m.left_at is null
      and private.communication_user_is_minor(v_thread.team_id,m.user_id)
  );

  v_message:=private.communication_send_message(p_thread_id,v_body,'text');

  insert into public.communication_attachments(
    message_id,thread_id,team_id,uploader_user_id,storage_path,mime_type,file_name,size_bytes,safety_status
  ) values(
    v_message,p_thread_id,v_thread.team_id,v_user,p_storage_path,p_mime_type,
    nullif(left(coalesce(p_file_name,''),255),''),p_size_bytes,
    case when v_review then 'review' else 'logged' end
  );

  if v_review then
    insert into public.communication_safety_flags(message_id,team_id,rule_code,severity,source)
    values(v_message,v_thread.team_id,'media_direct_minor','medium','automatic')
    on conflict(message_id,rule_code,source) do nothing;
  end if;

  return v_message;
end;
$function$;

CREATE OR REPLACE FUNCTION public.send_communication_message(p_thread_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ select private.communication_send_message(p_thread_id,p_body,'text'); $function$;

set check_function_bodies=true;
revoke all on function private.can_send_team_sms(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.can_upload_communication_media_object(p_name text) from public,anon,authenticated;
revoke all on function private.can_view_communication_media_object(p_name text) from public,anon,authenticated;
revoke all on function private.communication_authorized_adult(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.communication_can_view_thread(p_thread_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.communication_direct_participant_key(p_user_ids uuid[]) from public,anon,authenticated;
revoke all on function private.communication_enqueue_notification(p_team_id uuid, p_user_id uuid, p_category text, p_title text, p_body text, p_thread_id uuid, p_message_id uuid, p_urgent boolean) from public,anon,authenticated;
revoke all on function private.communication_member_eligible(t communication_threads, u uuid) from public,anon,authenticated;
revoke all on function private.communication_members_request(p_action text, p_data jsonb) from public,anon,authenticated;
revoke all on function private.communication_members_revision(tid uuid) from public,anon,authenticated;
revoke all on function private.communication_minor_capability(p_team_id uuid, p_user_id uuid, p_capability text) from public,anon,authenticated;
revoke all on function private.communication_person_name(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.communication_restore_required_mirrors(tid uuid) from public,anon,authenticated;
revoke all on function private.communication_scan_level(p_body text) from public,anon,authenticated;
revoke all on function private.communication_send_message(p_thread_id uuid, p_body text, p_kind text) from public,anon,authenticated;
revoke all on function private.communication_user_belongs_to_team(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.communication_user_is_guardian_of(p_team_id uuid, p_guardian uuid, p_minor_user uuid) from public,anon,authenticated;
revoke all on function private.communication_user_is_minor(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.communication_user_is_staff(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
revoke all on function private.conversation_review_admin(tid uuid, uid uuid) from public,anon,authenticated;
revoke all on function private.conversation_review_adult(tid uuid, uid uuid) from public,anon,authenticated;
revoke all on function private.conversation_review_assigned(tid uuid, uid uuid, accepted boolean) from public,anon,authenticated;
revoke all on function private.conversation_review_can_view(th uuid, uid uuid) from public,anon,authenticated;
revoke all on function private.conversation_review_covered(th uuid) from public,anon,authenticated;
revoke all on function private.conversation_review_minor(tid uuid, uid uuid) from public,anon,authenticated;
revoke all on function private.conversation_review_request(p_action text, p_data jsonb) from public,anon,authenticated;
revoke all on function private.parent_browser_service(p_action text, p_data jsonb) from public,anon,authenticated;
revoke all on function private.parent_browser_verification_valid(p_guardian uuid) from public,anon,authenticated;
revoke all on function private.parent_browser_verify(p_guardian uuid, p_team uuid, p_confirm boolean) from public,anon,authenticated;
revoke all on function private.profile_approval_policy(p_profile uuid) from public,anon,authenticated;
revoke all on function private.profile_approval_policy_before_browser(p_profile uuid) from public,anon,authenticated;
revoke all on function private.sms_sender_label(p_team_id uuid, p_user_id uuid) from public,anon,authenticated;
grant execute on function private.parent_browser_service(text,jsonb) to service_role;
grant execute on function private.conversation_review_request(text,jsonb) to authenticated;
grant execute on function private.parent_browser_verify(uuid,uuid,boolean) to authenticated;
grant execute on function private.communication_send_message(uuid,text,text) to authenticated;
grant execute on function private.communication_members_request(text,jsonb) to authenticated;
