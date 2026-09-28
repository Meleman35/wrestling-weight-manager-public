-- One parent hub over existing policies. No defaults or existing preferences change.
create function private.parent_controls_request(p_action text, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid=auth.uid(); t uuid; a uuid; pid uuid; teams jsonb; children jsonb; result jsonb;
 w private.wrestling_profiles%rowtype; prefs public.communication_preferences%rowtype;
 section text; current_value jsonb; v jsonb; k text; minor_athlete boolean; can_profile boolean;
begin
 if u is null or exists(select 1 from private.team_logins where user_id=u) then raise exception 'Use your personal parent account';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'Invalid parent settings';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name) order by q.name,q.id),'[]') into teams from (
  select distinct tm.team_id id,tt.name from public.team_memberships tm join public.teams tt on tt.id=tm.team_id
  join public.athlete_guardians g on g.athlete_id=tm.athlete_id and g.guardian_user_id=tm.user_id
  where tm.user_id=u and tm.role='parent_guardian' and tm.active
 ) q;
 t:=nullif(p_data->>'team_id','')::uuid;
 if t is null then t:=(teams->0->>'id')::uuid;end if;
 if t is null and p_action='context' then return jsonb_build_object('teams',teams,'children','[]'::jsonb);end if;
 if t is null or not exists(select 1 from jsonb_array_elements(teams) x where x->>'id'=t::text) then raise exception 'A current parent link on this team is required';end if;
 perform private.wrestling_profiles_request('mine','{}');
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'profile_id',q.profile_id) order by q.name,q.id),'[]') into children from (
  select distinct at.id,concat_ws(' ',at.first_name,at.last_name) name,wp.id profile_id
  from public.athletes at join public.athlete_guardians g on g.athlete_id=at.id and g.guardian_user_id=u
  join public.team_memberships tm on tm.athlete_id=at.id and tm.team_id=t and tm.user_id=u and tm.role='parent_guardian' and tm.active
  left join private.wrestling_profiles wp on wp.athlete_profile_id=at.profile_id
 ) q;
 a:=nullif(p_data->>'athlete_id','')::uuid;if a is null then a:=(children->0->>'id')::uuid;end if;
 if a is null or not exists(select 1 from jsonb_array_elements(children) x where x->>'id'=a::text) then raise exception 'Choose your currently linked athlete';end if;
 select wp.* into w from public.athletes at join private.wrestling_profiles wp on wp.athlete_profile_id=at.profile_id where at.id=a;
 pid:=w.id;can_profile:=coalesce(private.profile_approval_guardian(pid),false);
 select coalesce(i.birth_date,at.birth_date) is null or coalesce(i.birth_date,at.birth_date)>current_date-interval '18 years'
 into minor_athlete from public.athletes at left join public.athlete_private_identity i on i.athlete_id=at.id where at.id=a;
 if p_action<>'context' then
  section:=case p_action when 'save_profile' then 'profile' when 'save_privacy' then 'privacy' when 'save_chat' then 'chat' when 'save_notifications' then 'notifications' when 'save_tournament' then 'tournament' when 'save_goals' then 'goals' when 'save_video' then 'video' end;
  if section is null then raise exception 'Unknown parent setting';end if;
  -- Serialize hub saves and compare the exact section the parent saw, including legacy edits.
  perform 1 from public.teams where id=t for update;
  perform 1 from public.athletes where id=a for update;
  perform 1 from private.wrestling_profiles where id=pid for update;
  perform 1 from public.communication_preferences where team_id=t and user_id=u for update;
  current_value:=private.parent_controls_request('context',jsonb_build_object('team_id',t,'athlete_id',a))->section;
  if current_value is null or current_value is distinct from p_data->'expected' then raise exception 'These settings changed. Reload this section before saving';end if;
  v:=p_data->'values';if jsonb_typeof(v) is distinct from 'object' then raise exception 'Choose your settings';end if;
  if section in ('profile','privacy','chat') and not minor_athlete then raise exception 'Adult athletes manage their own profile and communications';end if;
  if section='profile' then
   if not can_profile then raise exception 'A linked parent of this minor athlete is required';end if;
   perform private.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',v->'auto_approve','review_photos',v->'review_photos'));
   if jsonb_typeof(v->'discoverable') is distinct from 'boolean' or jsonb_typeof(v->'sharing') is distinct from 'object' then raise exception 'Choose profile visibility';end if;
   if exists(select 1 from jsonb_each(v->'sharing') where jsonb_typeof(value)<>'boolean' or key<>all(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url','photo','corner','follow','outgoing_follow'])) then raise exception 'Invalid profile sharing choice';end if;
   update private.wrestling_profiles set discoverable=(v->>'discoverable')::boolean,sharing=sharing||(v->'sharing'),updated_at=now() where id=pid;
  elsif section='privacy' then
   foreach k in array array['share_email_with_coaches','share_phone_with_coaches','share_birth_date_with_coaches','sms_opt_in','disclose_medical_to_coaches'] loop
    if jsonb_typeof(v->k) is distinct from 'boolean' then raise exception 'Choose every contact privacy setting';end if;
   end loop;
   insert into public.athlete_private_contact(athlete_id,share_email_with_coaches,share_phone_with_coaches,sms_opt_in)
    values(a,(v->>'share_email_with_coaches')::boolean,(v->>'share_phone_with_coaches')::boolean,(v->>'sms_opt_in')::boolean)
    on conflict(athlete_id) do update set share_email_with_coaches=excluded.share_email_with_coaches,share_phone_with_coaches=excluded.share_phone_with_coaches,sms_opt_in=excluded.sms_opt_in,updated_at=now();
   insert into public.athlete_private_identity(athlete_id,birth_date,share_birth_date_with_coaches)
    select a,at.birth_date,(v->>'share_birth_date_with_coaches')::boolean from public.athletes at where at.id=a
    on conflict(athlete_id) do update set share_birth_date_with_coaches=excluded.share_birth_date_with_coaches,updated_at=now();
   insert into public.athlete_medical_private(athlete_id,disclose_to_coaches) values(a,(v->>'disclose_medical_to_coaches')::boolean)
    on conflict(athlete_id) do update set disclose_to_coaches=excluded.disclose_to_coaches,updated_at=now();
  elsif section='chat' then
   foreach k in array array['team_chat','group_chat','peer_to_peer','coach_to_athlete','media_view','media_send_group','media_send_direct'] loop
    if jsonb_typeof(v->k) is distinct from 'boolean' then raise exception 'Choose every chat and media setting';end if;
   end loop;
   perform public.set_athlete_chat_permissions_v2(t,a,(v->>'team_chat')::boolean,(v->>'group_chat')::boolean,(v->>'peer_to_peer')::boolean,(v->>'coach_to_athlete')::boolean,(v->>'media_view')::boolean,(v->>'media_send_group')::boolean,(v->>'media_send_direct')::boolean);
  elsif section='notifications' then
   foreach k in array array['push_messages','sms_message_fallback','email_messages','push_announcements','sms_announcements','email_announcements','push_weigh_ins','guardian_alerts_only'] loop
    if jsonb_typeof(v->k) is distinct from 'boolean' then raise exception 'Choose every notification setting';end if;
   end loop;
   if nullif(v->>'quiet_start','') is null or nullif(v->>'quiet_end','') is null or nullif(v->>'time_zone','') is null then raise exception 'Choose quiet hours and a time zone';end if;
   perform public.set_communication_preferences(t,(v->>'push_messages')::boolean,(v->>'sms_message_fallback')::boolean,(v->>'email_messages')::boolean,(v->>'push_announcements')::boolean,(v->>'sms_announcements')::boolean,(v->>'email_announcements')::boolean,(v->>'quiet_start')::time,(v->>'quiet_end')::time,v->>'time_zone');
   perform public.set_weigh_in_push_preference(t,(v->>'push_weigh_ins')::boolean);
   perform public.set_guardian_alert_preference(t,(v->>'guardian_alerts_only')::boolean);
  elsif section='tournament' then
   perform private.tournament_request('visibility',jsonb_build_object('team_id',t,'athlete_id',a,'level',v->>'level','revision',current_value->'revision'));
  elsif section='goals' then
   if not private.team_goal_access(t,a) or jsonb_typeof(v->'enabled') is distinct from 'boolean' then raise exception 'Active athlete and goal-sharing choice required';end if;
   -- Also permits revoking sharing while the coach has goals switched off.
   insert into private.athlete_goal_profile_sharing(team_id,athlete_id,enabled,approved_by) values(t,a,(v->>'enabled')::boolean,u)
    on conflict(team_id,athlete_id) do update set enabled=excluded.enabled,approved_by=u,revision=private.athlete_goal_profile_sharing.revision+1,updated_at=now();
  elsif section='video' then
   if jsonb_typeof(v->'allowed') is distinct from 'boolean' then raise exception 'Choose recording permission';end if;
   perform private.video_match_request('permission',jsonb_build_object('team_id',t,'athlete_id',a,'allowed',v->'allowed'));
  end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(u,'parent_controls_save','athlete',a,jsonb_build_object('team_id',t,'section',section));
  return private.parent_controls_request('context',jsonb_build_object('team_id',t,'athlete_id',a));
 end if;
 prefs:=public.get_communication_preferences(t);
 result:=jsonb_build_object('teams',teams,'children',children,'team_id',t,'athlete_id',a,'profile_id',pid,'is_minor',minor_athlete,
  'profile',case when can_profile then jsonb_build_object('auto_approve',private.profile_approval_policy(pid)->'auto_approve','review_photos',private.profile_approval_policy(pid)->'review_photos','sharing',w.sharing,'discoverable',w.discoverable) else null end,
  'pending_reviews',case when can_profile then (select count(*) from private.profile_approval_requests where profile_id=pid and status='pending') else 0 end,
  'privacy',case when minor_athlete then (select jsonb_build_object('share_email_with_coaches',coalesce(c.share_email_with_coaches,false),'share_phone_with_coaches',coalesce(c.share_phone_with_coaches,false),'sms_opt_in',coalesce(c.sms_opt_in,false),'share_birth_date_with_coaches',coalesce(i.share_birth_date_with_coaches,false),'disclose_medical_to_coaches',coalesce(m.disclose_to_coaches,false)) from public.athletes at left join public.athlete_private_contact c on c.athlete_id=at.id left join public.athlete_private_identity i on i.athlete_id=at.id left join public.athlete_medical_private m on m.athlete_id=at.id where at.id=a) else null end,
  'chat',(select to_jsonb(cp)-'athlete_id'-'athlete_name'-'is_minor' from public.get_my_athlete_chat_permissions_v2(t) cp where cp.athlete_id=a and minor_athlete),
  'notifications',to_jsonb(prefs)-'user_id'-'team_id'-'updated_at'-'in_app_messages'-'in_app_announcements',
  'tournament',case when private.tournament_athlete_access(t,a) then jsonb_build_object('level',coalesce((select level from private.tournament_visibility where athlete_id=a),'upcoming'),'revision',coalesce((select revision from private.tournament_visibility where athlete_id=a),0)) else null end,
  'goals',case when private.team_goal_access(t,a) then jsonb_build_object('enabled',coalesce((select enabled from private.athlete_goal_profile_sharing where team_id=t and athlete_id=a),false),'revision',coalesce((select revision from private.athlete_goal_profile_sharing where team_id=t and athlete_id=a),0),'team_enabled',coalesce((select enabled from private.team_goal_settings where team_id=t),false)) else null end,
  'video',jsonb_build_object('available',coalesce(private.video_team_enabled(t) and (select not test_only from private.video_pilot_control where id),false),'allowed',coalesce((select recording_allowed from private.video_athlete_permissions where team_id=t and athlete_id=a and guardian_id=u),false),'live_available',false));
 return result;
end $$;
revoke all on function private.parent_controls_request(text,jsonb) from public,anon;
grant execute on function private.parent_controls_request(text,jsonb) to authenticated;
create function public.parent_controls_request(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.parent_controls_request(p_action,p_data); $$;
revoke all on function public.parent_controls_request(text,jsonb) from public,anon;
grant execute on function public.parent_controls_request(text,jsonb) to authenticated;
