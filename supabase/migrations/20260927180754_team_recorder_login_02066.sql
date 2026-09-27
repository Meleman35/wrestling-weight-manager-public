-- Coach-created shared recording logins. Existing team code/password authentication and session revocation are reused.
begin;
CREATE OR REPLACE FUNCTION private.team_login_permissions(p_kind text, p_permissions jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object('attendance',p_kind='team_device' and not coalesce(p_permissions->'record_matches'='true'::jsonb,false) and coalesce(p_permissions->'attendance'='true'::jsonb,false),
    'weigh_in',p_kind='team_device' and not coalesce(p_permissions->'record_matches'='true'::jsonb,false) and coalesce(p_permissions->'weigh_in'='true'::jsonb,false),
    'equipment',p_kind='team_device' and not coalesce(p_permissions->'record_matches'='true'::jsonb,false) and coalesce(p_permissions->'equipment'='true'::jsonb,false),
    'checkout',p_kind='team_device' and not coalesce(p_permissions->'record_matches'='true'::jsonb,false) and coalesce(p_permissions->'checkout'='true'::jsonb,false),
    'messages',p_kind='team_device' and not coalesce(p_permissions->'record_matches'='true'::jsonb,false) and coalesce(p_permissions->'messages'='true'::jsonb,false),
    'record_matches',p_kind='team_device' and coalesce(p_permissions->'record_matches'='true'::jsonb,false),'mass_text',false,'team_admin',false,'managed_login',true,'staff_role','limited_staff');
$function$
;

CREATE OR REPLACE FUNCTION private.enforce_team_login_request()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a private.team_logins%rowtype; p text:=trim(leading '/' from coalesce(current_setting('request.path',true),'')); f text; allowed boolean:=false;
begin
  select * into a from private.team_logins where user_id=(select auth.uid());
  if not found then return; end if;
  if not private.managed_login_access_ok() then raise sqlstate '42501' using message='TEAM_LOGIN_REVOKED: Sign in again using Team Login or ask your team admin.'; end if;
  -- Recorder logins use a narrow RPC surface, never the general team client.
  if a.permissions->'record_matches'='true'::jsonb then
    if p not in ('rpc/get_my_team_login','rpc/video_pilot_context','rpc/video_match_request') then
      raise sqlstate '42501' using message='This team login is for scoring and recording only.';
    end if;
    return;
  end if;
  if p not like 'rpc/%' then
    if not private.managed_resource_allowed(p) then raise sqlstate '42501' using message='This tool is not enabled for this team login.'; end if;
    return;
  end if;
  f:=substring(p from 5);
  if f in ('get_or_create_team_join_code','get_team_join_code') then raise sqlstate '42501' using message='A personal team administrator account is required.'; end if;
  -- Private account sessions cannot enroll elsewhere or change their authority.
  if f ~ '(communication|team_sms|guardian_safety)' and f not in ('get_communication_preferences','set_communication_preferences') then
    if a.kind<>'team_device' or not coalesce((a.permissions->>'messages')::boolean,false) then
      raise sqlstate '42501' using message='Messaging is not enabled for this team login.';
    end if;
  end if;
  allowed:=f ~ '^(get_|can_|is_)' or f in ('save_operations','team_dashboard_counts_v3','register_native_push_device','disable_native_push_device','set_communication_preferences','set_weigh_in_push_preference','sync_recurring_practices_for_season');
  if a.kind='test_athlete' then
    allowed:=allowed or f in ('record_self_scale_weight','record_self_scale_weight_v2','authorize_teammate_weight_check','record_teammate_scale_weight','cancel_teammate_weight_check','set_athlete_weight_pin');
  else
    if coalesce((a.permissions->>'weigh_in')::boolean,false) then
      allowed:=allowed or f in ('create_official_weigh_in_session','delete_official_weigh_in_session','seed_home_team_weigh_in_roster','add_official_roster_entry','record_official_weigh_in','record_team_scale_weight','record_kiosk_weigh_in','resolve_session_credential','resolve_operational_credential','resolve_athlete_credential');
    end if;
    if coalesce((a.permissions->>'attendance')::boolean,false) then allowed:=allowed or f='mark_event_attendance'; end if;
    if coalesce((a.permissions->>'checkout')::boolean,false) then allowed:=allowed or f in ('approve_event_checkout','coach_check_out_athlete'); end if;
    if coalesce((a.permissions->>'messages')::boolean,false) then
      allowed:=allowed or f in ('create_communication_thread','send_communication_message','send_communication_attachment','mark_communication_thread_read','mark_communication_notifications_read','edit_communication_message','remove_communication_message','hide_communication_thread','search_communication_messages','mute_communication_thread','set_communication_block','report_communication_message');
    end if;
  end if;
  if not allowed then raise sqlstate '42501' using message='This action requires a personal account with the appropriate team role.'; end if;
end $function$
;

CREATE OR REPLACE FUNCTION private.managed_resource_allowed(p_resource text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a private.team_logins%rowtype;
begin
  select * into a from private.team_logins where user_id=(select auth.uid());
  if not found then return true; end if;
  if not private.managed_login_access_ok() then return false; end if;
  if a.permissions->'record_matches'='true'::jsonb then return false; end if;
  if p_resource ~ '(^communication_|^team_sms_|^team_posts$|^team_post_attachments$|^athlete_chat_permissions$)' then
    return a.kind='team_device' and coalesce((a.permissions->>'messages')::boolean,false);
  end if;
  if p_resource ~ '^equipment_' then return coalesce((a.permissions->>'equipment')::boolean,false); end if;
  if p_resource='event_checkouts' then return coalesce((a.permissions->>'checkout')::boolean,false); end if;
  if p_resource='event_attendance' and a.kind='team_device' then return coalesce((a.permissions->>'attendance')::boolean,false); end if;
  if a.kind='team_device' and p_resource in ('weigh_ins','weigh_in_corrections','certification_plans','certification_plan_rows','athlete_private_identity','athlete_private_contact','athlete_medical_private','medical_clearance_cases','medical_clearance_documents') then return false; end if;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION private.team_login_label(p_account private.team_logins)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select (p_account).display_name||case when (p_account).kind='shared' then ' · Team Login' when (p_account).kind='team_device' and (p_account).permissions->'record_matches'='true'::jsonb then ' · Team Recorder' when (p_account).kind='team_device' then ' · Team Device' else ' · Test Login' end;
$function$
;

CREATE OR REPLACE FUNCTION private.sync_team_login(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a private.team_logins%rowtype; v_role text; child record;
begin
 select * into strict a from private.team_logins where id=p_id;
 if a.user_id is null then return; end if;
 if a.kind='shared' then
   delete from public.team_memberships where user_id=a.user_id;
   update public.profiles set display_name=private.team_login_label(a) where id=a.user_id;
   delete from private.team_login_devices where parent_id=a.id;
   for child in select id from private.team_logins where parent_id=a.id loop
     update private.team_logins set active=a.active,state=a.state,revision=a.revision,display_name=a.display_name,
       permissions=private.team_login_permissions(kind,a.permissions),issue_operation_id=null,issue_until=null,updated_at=now() where id=child.id;
     delete from private.team_login_sessions where login_id=child.id;
     perform private.sync_team_login(child.id);
   end loop;
   return;
 end if;
 v_role:=case when a.kind='test_athlete' then 'athlete' else 'manager' end;
 delete from public.team_memberships where user_id=a.user_id;
 insert into public.team_memberships(team_id,user_id,role,athlete_id,permissions,active)
 values(a.team_id,a.user_id,v_role,a.athlete_id,a.permissions,a.active and a.state='ready');
 update public.profiles set display_name=private.team_login_label(a) where id=a.user_id;
 if a.kind='team_device' then
  insert into public.team_staff_profiles(team_id,user_id,display_name,title,contact_email,share_email_with_athletes,share_email_with_parents)
  values(a.team_id,a.user_id,private.team_login_label(a),case when a.permissions->'record_matches'='true'::jsonb then 'Team Recorder' else 'Team Device' end,null,false,false)
  on conflict(team_id,user_id) do update set display_name=excluded.display_name,title=excluded.title,contact_email=null;
 end if;
end $function$
;


create function private.video_recording_device(t uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.managed_login_access_ok()
 and exists(select 1 from private.team_logins l join public.team_memberships m on m.user_id=l.user_id and m.team_id=l.team_id
 where l.user_id=auth.uid() and l.team_id=t and l.kind='team_device' and l.active and l.state='ready'
 and l.permissions->'record_matches'='true'::jsonb and m.active and m.role='manager' and m.permissions->'record_matches'='true'::jsonb)
$$;
revoke all on function private.video_recording_device(uuid) from public,anon,authenticated;


create or replace function private.video_team_enabled(t uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (not exists(select 1 from private.team_logins where user_id=auth.uid()) or private.video_recording_device(t))
 and exists(select 1 from private.video_pilot_control where id and enabled)
 and exists(select 1 from private.video_pilot_grants g where g.team_id=t and g.revoked_at is null and g.expires_at>now())
$$;

create or replace function private.video_can_record(t uuid,a uuid,ev uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.video_team_enabled(t) and not (select test_only from private.video_pilot_control where id) and private.video_consent(t,a)
 and exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where r.athlete_id=a and r.active and s.active and s.team_id=t)
 and exists(select 1 from private.video_event_settings v where v.team_id=t and v.event_id=ev and v.recording_permitted)
 and ( (public.is_team_staff(t) and exists(select 1 from private.video_pilot_grants g where g.team_id=t and g.user_id=auth.uid() and g.expires_at>now() and g.revoked_at is null))
 or private.video_recording_device(t)
 or exists(select 1 from public.team_events e where e.id=ev and e.team_id=t and private.video_team_recorder(t,e.season_id))
 or exists(select 1 from private.video_recorder_assignments r join public.team_memberships m on m.team_id=t and m.user_id=r.user_id and m.active
 where r.team_id=t and r.event_id=ev and r.athlete_id=a and r.user_id=auth.uid() and r.expires_at>now()) )
 -- A teammate shortcut must not reveal opponent details hidden by guardian visibility.
 and (public.is_team_staff(t) or private.tournament_guardian(t,a) or coalesce((select level from private.tournament_visibility where athlete_id=a),'upcoming')='full')
$$;
create or replace function private.video_pilot_context(p_team_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare uid uuid=auth.uid(); expiry timestamptz; people jsonb; staff boolean=public.is_team_staff(p_team_id);
begin
 if uid is null or (exists(select 1 from private.team_logins where user_id=uid) and not private.video_recording_device(p_team_id)) then raise exception 'Personal coach or assigned recorder account required'; end if;
 if not private.video_team_enabled(p_team_id) then return jsonb_build_object('allowed',false); end if;
 if staff or ((select test_only from private.video_pilot_control where id) and exists(select 1 from public.team_memberships where team_id=p_team_id and user_id=uid and active and role in ('athlete','manager'))) then select expires_at into expiry from private.video_pilot_grants where team_id=p_team_id and user_id=uid and revoked_at is null and expires_at>now(); end if;
 if expiry is not null then
  select coalesce(jsonb_agg(distinct r.athlete_id),'[]') into people from public.roster_memberships r join public.seasons s on s.id=r.season_id where s.team_id=p_team_id and s.active and r.active;
 else
  select max(r.expires_at),coalesce(jsonb_agg(distinct r.athlete_id),'[]') into expiry,people from private.video_recorder_assignments r
  where r.team_id=p_team_id and r.user_id=uid and private.video_can_record(r.team_id,r.athlete_id,r.event_id);
 end if;
 if private.video_team_recorder(p_team_id) or private.video_recording_device(p_team_id) then
  -- Test mode grants only the synthetic camera test. Real bouts keep event, guardian and visibility checks.
  select greatest(expiry,max(g.expires_at)) into expiry from private.video_pilot_grants g
   where g.team_id=p_team_id and g.revoked_at is null and g.expires_at>now();
  if not (select test_only from private.video_pilot_control where id) then
   select coalesce(jsonb_agg(distinct r.athlete_id),'[]'::jsonb) into people
   from public.roster_memberships r join public.seasons s on s.id=r.season_id and s.active and s.team_id=p_team_id
   where r.active and exists(select 1 from public.team_events e where e.season_id=s.id and e.team_id=p_team_id and private.video_can_record(p_team_id,r.athlete_id,e.id));
  end if;
 end if;
 if expiry is null then return jsonb_build_object('allowed',false); end if;
 if (select test_only from private.video_pilot_control where id) then people='[]'::jsonb; end if;
 return jsonb_build_object('allowed',true,'user_id',uid,'team_id',p_team_id,'lease_seconds',greatest(0,least(7200,extract(epoch from expiry-now())::int)),
 'athlete_ids',people,'test_only',(select test_only from private.video_pilot_control where id),'cloud_upload',(select cloud_enabled and not test_only from private.video_pilot_control where id),'live',false,'billing',false);
end $$;
create or replace function private.video_match_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
 u uuid=auth.uid(); t uuid=(p_data->>'team_id')::uuid; a uuid=(p_data->>'athlete_id')::uuid;
 ev uuid=(p_data->>'event_id')::uuid; bid uuid=(p_data->>'bout_id')::uuid; rid uuid=(p_data->>'id')::uuid;
 b record; m private.video_scored_matches; rec private.video_recordings; rules jsonb; d jsonb; items jsonb; n bigint; settings jsonb;
begin
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from private.team_logins where user_id=u) then
  if not private.video_recording_device(t) then raise exception 'Approved team recorder login required'; end if;
  if p_action not in ('device_context','assignments','recorder_test','begin','save','prepare','complete','playback','go_live') then
   raise exception 'This team login is for scoring and recording only';
  end if;
 end if;
 if p_action='device_context' then
  if not private.video_recording_device(t) then raise exception 'Team recorder login required'; end if;
  return jsonb_build_object('team', (select jsonb_build_object('id',id,'name',name) from public.teams where id=t),
   'seasons',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',coalesce(to_jsonb(s)->>'name','Active season')) order by s.id),'[]'::jsonb) from public.seasons s where s.team_id=t and s.active),
   'available',private.video_team_enabled(t),'test_only',(select test_only from private.video_pilot_control where id));
 end if;
 if not private.video_team_enabled(t) then raise exception 'Video pilot is not enabled for this team'; end if;
 if p_action in ('recorder_settings','recorder_settings_save') then return private.video_recorder_policy(t,p_action,p_data); end if;
 if p_action='recorder_test' then
  if not coalesce((private.video_pilot_context(t)->>'allowed')::boolean,false) then raise exception 'Approved recorder access required for a camera test'; end if;
  rid=gen_random_uuid();
  d=jsonb_build_object('id',rid,'video_test',true,'book_type','test','flowVersion',1,'nfhs',false,'rules_authority','custom','ruleset','Test rules','style','folkstyle',
   'periods','[120,120,120]'::jsonb,'original_periods','[120,120,120]'::jsonb,'breakSeconds',0,'takedown',3,
   'red_id',null,'other_id',null,'red_name','Test Athlete Red','other_name','Test Athlete Green','label','Recorder test · device only',
   'period',0,'phase','period','remainingMs',120000,'deadline',null,'ledger','[]'::jsonb,'status','live');
  return jsonb_build_object('id',rid,'data',d,'team_id',t);
 end if;
 if (select test_only from private.video_pilot_control where id) and p_action not in ('assignments','go_live') then raise exception 'Only the Test scorebook is enabled for this pilot'; end if;
 if p_action='permission' then
  if not private.tournament_guardian(t,a) then raise exception 'Linked parent required'; end if;
  insert into private.video_athlete_permissions values(t,a,u,coalesce((p_data->>'allowed')::boolean,false),now())
  on conflict(team_id,athlete_id,guardian_id) do update set recording_allowed=excluded.recording_allowed,updated_at=now();
  return jsonb_build_object('saved',true);
 end if;
 if p_action in ('event_settings','assign','manage') then
  if not public.is_team_staff(t) or not exists(select 1 from private.video_pilot_grants where team_id=t and user_id=u and expires_at>now() and revoked_at is null) then raise exception 'Approved pilot coach required'; end if;
  if p_action='manage' then
   return jsonb_build_object('members',(select coalesce(jsonb_agg(jsonb_build_object('id',q.user_id,'name',q.display_name,'role',q.role)),'[]') from (select distinct m.user_id,p.display_name,m.role from public.team_memberships m join public.profiles p on p.id=m.user_id where m.team_id=t and m.active and not exists(select 1 from private.team_logins l where l.user_id=m.user_id))q),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.title)),'[]') from public.team_events e join public.seasons s on s.id=e.season_id where e.team_id=t and e.event_type='tournament' and s.active),
    'athletes',(select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name)),'[]') from (select distinct a.id,concat_ws(' ',a.first_name,a.last_name) name from public.athletes a join public.roster_memberships r on r.athlete_id=a.id join public.seasons s on s.id=r.season_id where s.team_id=t and s.active and r.active)q));
  end if;
  if not exists(select 1 from public.team_events e join public.seasons s on s.id=e.season_id where e.id=ev and e.team_id=t and e.event_type='tournament' and s.active) then raise exception 'Active team tournament required'; end if;
  if p_action='event_settings' then
   rules=p_data->'rules';
   if not coalesce(rules->>'style' in ('folkstyle','freestyle','greco','beach'),false) or jsonb_typeof(rules->'periods') is distinct from 'array' then raise exception 'Valid scoring rules required'; end if;
   if jsonb_array_length(rules->'periods') not between 1 and 12 or exists(select 1 from jsonb_array_elements_text(rules->'periods') v where v::numeric not between 1 and 900) then raise exception 'Valid period lengths required'; end if;
   if not coalesce((rules->>'breakSeconds')::numeric between 0 and 900,false) or not coalesce((rules->>'takedown')::int between 1 and 5,false) then raise exception 'Valid scoring rules required'; end if;
   if rules->>'style'='beach' and (rules->'periods'<>'[180]'::jsonb or (rules->>'breakSeconds')::int<>0) then raise exception 'Beach requires one three minute period'; end if;
   insert into private.video_event_settings values(ev,t,coalesce((p_data->>'permitted')::boolean,false),rules,u,now())
   on conflict(event_id) do update set recording_permitted=excluded.recording_permitted,rules=excluded.rules,updated_by=u,updated_at=now();
  else
   if not private.tournament_athlete_access(t,a) or not exists(select 1 from public.team_memberships where team_id=t and user_id=(p_data->>'user_id')::uuid and active) then raise exception 'Active team athlete and recorder required'; end if;
   if coalesce((p_data->>'revoke')::boolean,false) then delete from private.video_recorder_assignments where event_id=ev and athlete_id=a and user_id=(p_data->>'user_id')::uuid;
   else insert into private.video_recorder_assignments values(t,ev,a,(p_data->>'user_id')::uuid,now()+interval '24 hours',u)
   on conflict(event_id,athlete_id,user_id) do update set expires_at=excluded.expires_at,assigned_by=u; end if;
  end if;
  return jsonb_build_object('saved',true);
 end if;
 if p_action in ('athlete','assignments') then
  if p_action='athlete' and not private.tournament_athlete_access(t,a) and not exists(select 1 from private.video_recorder_assignments r where r.team_id=t and r.athlete_id=a and r.user_id=u and private.video_can_record(t,a,r.event_id)) then raise exception 'Athlete video access required'; end if;
  select coalesce(jsonb_agg(q.item order by q.starts_at,q.rank,q.queue_order,q.bid),'[]') into items from (
   select e.starts_at,b.id bid,b.queue_order,array_position(array['on_mat','up_next','on_deck','in_hole','queued'],b.status) rank,
    jsonb_build_object('id',b.id,'athlete_id',en.athlete_id,'athlete_name',concat_ws(' ',at.first_name,at.last_name),'event_id',e.id,'event_name',e.title,'bout_number',b.bout_number,'mat',b.mat,'opponent',b.opponent,'division',en.division,'weight_class',en.weight_class,'updated_at',b.updated_at,'status',b.status) item
   from private.tournament_bouts b join private.tournament_entries en on en.id=b.entry_id join private.tournament_workspaces w on w.id=b.workspace_id
   join public.team_events e on e.id=w.event_id join public.seasons s on s.id=e.season_id join public.athletes at on at.id=en.athlete_id
   where w.team_id=t and s.active and (p_action='assignments' or en.athlete_id=a) and b.status in ('queued','in_hole','on_deck','up_next','on_mat')
   and private.video_can_record(t,en.athlete_id,e.id) and e.starts_at between now()-interval '24 hours' and now()+interval '36 hours'
  )q;
  return jsonb_build_object('bouts',items,
   'can_scorebook',coalesce((private.video_pilot_context(t)->>'allowed')::boolean,false) or (not (select test_only from private.video_pilot_control where id) and (public.is_team_staff(t) or exists(select 1 from public.team_memberships where team_id=t and user_id=u and active and role in ('athlete','manager')))),
   'can_manage_recorders',private.video_manage_recorders(t),'team_recorder',private.video_team_recorder(t),
   'can_record_test',coalesce((private.video_pilot_context(t)->>'allowed')::boolean,false),
   'can_manage',not (select test_only from private.video_pilot_control where id) and public.is_team_staff(t) and exists(select 1 from private.video_pilot_grants where team_id=t and user_id=u and expires_at>now() and revoked_at is null),'can_set_permission',private.tournament_guardian(t,a),'permission',(select recording_allowed from private.video_athlete_permissions where team_id=t and athlete_id=a and guardian_id=u),
   'recordings',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'label',m.data->>'label','opponent',m.data->>'other_name','bout_number',m.data->>'bout_number','created_at',v.created_at,'partial',v.partial,'duration_ms',v.duration_ms) order by v.created_at desc),'[]') from private.video_recordings v join private.video_scored_matches m on m.id=v.match_id where v.team_id=t and v.athlete_id=a and v.status='ready' and private.video_can_view(t,a)),
   'test_only',(select test_only from private.video_pilot_control where id),'cloud_enabled',(select cloud_enabled and not test_only from private.video_pilot_control where id),'live_available',false);
 end if;
 if p_action='begin' then
  select b.*,en.athlete_id,concat_ws(' ',at.first_name,at.last_name) athlete_name,en.division,en.weight_class,w.event_id,e.title,e.season_id into b
  from private.tournament_bouts b join private.tournament_entries en on en.id=b.entry_id join private.tournament_workspaces w on w.id=b.workspace_id
  join public.team_events e on e.id=w.event_id join public.seasons s on s.id=e.season_id join public.athletes at on at.id=en.athlete_id where b.id=bid and w.team_id=t and s.active;
  if not found or not private.video_can_record(t,b.athlete_id,b.event_id) then raise exception 'Recording permission or assignment is missing'; end if;
  if b.status not in ('queued','in_hole','on_deck','up_next','on_mat') then raise exception 'This bout is already finished'; end if;
  if coalesce(b.opponent,'')='' then raise exception 'Your coach needs to add the opponent to this bout first'; end if;
  perform pg_advisory_xact_lock(hashtextextended(bid::text,0));
  select * into m from private.video_scored_matches where bout_id=bid;
  if found then if m.recorder_id<>u then raise exception 'Another recorder already opened this bout'; end if;
  else
   select v.rules into rules from private.video_event_settings v where v.event_id=b.event_id;
   rid=gen_random_uuid(); d=jsonb_build_object('id',rid,'bout_id',bid,'event_id',b.event_id,'athlete_id',b.athlete_id,'bout_number',b.bout_number,'mat',b.mat,'division',b.division,'weight_class',b.weight_class,'source_revision',b.revision,'book_type','competition','flowVersion',1,'nfhs',false,'rules_authority','custom','ruleset','Coach-confirmed event rules','style',rules->>'style','periods',rules->'periods','original_periods',rules->'periods','breakSeconds',rules->'breakSeconds','takedown',rules->'takedown','red_id',b.athlete_id,'other_id',null,'red_name',b.athlete_name,'other_name',b.opponent,'label',b.title,'period',0,'phase','period','remainingMs',(rules->'periods'->>0)::int*1000,'deadline',null,'ledger','[]'::jsonb,'status','live');
   insert into private.video_scored_matches(id,team_id,bout_id,event_id,athlete_id,recorder_id,data) values(rid,t,bid,b.event_id,b.athlete_id,u,d) returning * into m;
  end if;
  return jsonb_build_object('id',m.id,'data',m.data,'revision',m.revision,'team_id',t,'season_id',b.season_id);
 end if;
 if p_action='save' then
  select * into m from private.video_scored_matches where id=rid and team_id=t for update;
  if not found or m.recorder_id<>u or not private.video_can_record(t,m.athlete_id,m.event_id) then raise exception 'Assigned recorder required'; end if;
  if m.revision is distinct from (p_data->>'revision')::int then raise exception 'Match changed. Reopen the saved bout'; end if;
  d=p_data->'data'; if octet_length(d::text)>262144 or jsonb_typeof(d->'ledger') is distinct from 'array' then raise exception 'Invalid score history'; end if;
  -- The client may edit scoring, never reassign athlete, event, opponent or bout identity.
  d=d||jsonb_build_object('id',m.id,'bout_id',m.bout_id,'event_id',m.event_id,'athlete_id',m.athlete_id,'red_id',m.athlete_id,'other_id',null,'red_name',m.data->'red_name','other_name',m.data->'other_name','label',m.data->'label','bout_number',m.data->'bout_number','deadline',null);
  update private.video_scored_matches set data=d,revision=revision+1 where id=rid returning * into m;
  return jsonb_build_object('revision',m.revision);
 end if;
 if p_action='prepare' then
  select * into m from private.video_scored_matches where id=(p_data->>'match_id')::uuid and team_id=t;
  if not found or m.recorder_id<>u or not private.video_can_record(t,m.athlete_id,m.event_id) then raise exception 'Assigned recorder required'; end if;
  if not (select cloud_enabled from private.video_pilot_control where id) then raise exception 'Cloud upload is not enabled yet. Your video stays on this device'; end if;
  perform pg_advisory_xact_lock(hashtextextended(t::text,1));
  select * into rec from private.video_recordings where id=rid;
  if found then
   if rec.recorder_id<>u or rec.match_id<>m.id or rec.bytes<>(p_data->>'bytes')::bigint or rec.timeline_bytes<>(p_data->>'timeline_bytes')::int or rec.status='removed' then raise exception 'Recording identity changed'; end if;
  else
   select coalesce(sum(bytes+timeline_bytes),0) into n from private.video_recordings where team_id=t;
   if n+(p_data->>'bytes')::bigint>53687091200 then raise exception 'Pilot storage limit reached. Keep the device copy and contact your coach'; end if;
   insert into private.video_recordings(id,team_id,match_id,athlete_id,recorder_id,video_path,timeline_path,bytes,timeline_bytes,mime,duration_ms,partial)
   values(rid,t,m.id,m.athlete_id,u,t::text||'/'||u::text||'/'||rid::text||'/original',t::text||'/'||u::text||'/'||rid::text||'/timeline.json',(p_data->>'bytes')::bigint,(p_data->>'timeline_bytes')::int,p_data->>'mime',(p_data->>'duration_ms')::int,coalesce((p_data->>'partial')::boolean,false)) returning * into rec;
  end if;
  return jsonb_build_object('id',rec.id,'status',rec.status,'bucket','match-video-pilot','video_path',rec.video_path,'timeline_path',rec.timeline_path,
   'video_uploaded',exists(select 1 from storage.objects where bucket_id='match-video-pilot' and name=rec.video_path and (metadata->>'size')::bigint=rec.bytes and metadata->>'mimetype'=rec.mime),
   'timeline_uploaded',exists(select 1 from storage.objects where bucket_id='match-video-pilot' and name=rec.timeline_path and (metadata->>'size')::bigint=rec.timeline_bytes and metadata->>'mimetype'='application/json'));
 end if;
 if p_action in ('complete','playback','remove') then
  select * into rec from private.video_recordings where id=rid and team_id=t for update;
  if not found or rec.status='removed' then raise exception 'Recording is unavailable'; end if;
  select * into m from private.video_scored_matches where id=rec.match_id;
  if p_action='complete' then
   if rec.recorder_id<>u or not private.video_can_record(t,rec.athlete_id,m.event_id) then raise exception 'Assigned recorder required'; end if;
   if not exists(select 1 from storage.objects where bucket_id='match-video-pilot' and name=rec.video_path and (metadata->>'size')::bigint=rec.bytes and metadata->>'mimetype'=rec.mime)
    or not exists(select 1 from storage.objects where bucket_id='match-video-pilot' and name=rec.timeline_path and (metadata->>'size')::bigint=rec.timeline_bytes and metadata->>'mimetype'='application/json') then raise exception 'Upload is not complete. Keep the device copy'; end if;
   update private.video_recordings set status='ready',ready_at=coalesce(ready_at,now()) where id=rid;
  elsif p_action='remove' then
   if not private.tournament_guardian(t,rec.athlete_id) and not public.is_team_staff(t) then raise exception 'Linked parent or coach required'; end if;
   update private.video_recordings set status='removed' where id=rid;
   return jsonb_build_object('removed',true,'purge_pending',true);
  elsif rec.status<>'ready' or not (private.video_can_view(t,rec.athlete_id) or (rec.recorder_id=u and private.video_can_record(t,rec.athlete_id,m.event_id))) then raise exception 'Family playback access required'; end if;
  return jsonb_build_object('id',rid,'status','ready','bucket','match-video-pilot','video_path',rec.video_path,'timeline_path',rec.timeline_path);
 end if;
 if p_action='go_live' then raise exception 'Live streaming is not connected yet. You can still record privately'; end if;
 raise exception 'Unknown video action';
end $$;
commit;
