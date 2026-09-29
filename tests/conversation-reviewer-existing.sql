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
