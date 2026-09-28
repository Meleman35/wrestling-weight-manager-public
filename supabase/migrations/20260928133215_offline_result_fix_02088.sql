create or replace function private.offline_coach_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid=auth.uid(); t uuid=(p_data->>'team_id')::uuid; s uuid=(p_data->>'season_id')::uuid;
 cursor_id uuid=nullif(p_data->>'cursor','')::uuid; thread_id uuid=(p_data->>'thread_id')::uuid;
 op uuid=(p_data->>'operation_id')::uuid; kind text=p_data->>'kind';
 rows jsonb; answer jsonb; existing private.offline_operations%rowtype;
 e public.team_events%rowtype; a public.event_attendance%rowtype; athlete uuid=(p_data->>'athlete_id')::uuid;
 stamp timestamptz=nullif(p_data->>'expected','')::timestamptz; created boolean=false;
begin
 if u is null or t is null or not public.is_team_staff(t) or exists(select 1 from private.team_logins where user_id=u)
  or not exists(select 1 from public.seasons where id=s and team_id=t) then
  raise exception using errcode='42501',message='Current coach access to this team and season is required. Sign in again online.';
 end if;
 if p_action='manifest' then
  return jsonb_build_object('team',(select jsonb_build_object('id',id,'name',name) from public.teams where id=t),
   'season',(select jsonb_build_object('id',id,'name',name) from public.seasons where id=s),
   'user_id',u,'verified_at',clock_timestamp(),'expires_at',clock_timestamp()+interval '7 days','version',1);
 elsif p_action='roster' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.athlete_id),'[]') into rows from (
   select r.athlete_id,r.first_name,r.last_name,r.roster_status,r.latest_weight,r.current_lineup_class,r.latest_weigh_in_at
   from public.roster_dashboard r where r.season_id=s and (cursor_id is null or r.athlete_id>cursor_id)
   order by r.athlete_id limit 250) q;
 elsif p_action='events' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from (
   select * from public.team_events where team_id=t and season_id=s and (cursor_id is null or id>cursor_id) order by id limit 250) q;
 elsif p_action='attendance' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from (
   select att.id,att.event_id,att.athlete_id,att.status,att.excuse_status,att.updated_at
   from public.event_attendance att join public.team_events ev on ev.id=att.event_id
   where ev.team_id=t and ev.season_id=s and (cursor_id is null or att.id>cursor_id) order by att.id limit 250) q;
 elsif p_action='threads' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.thread_id),'[]') into rows from (
   select * from public.get_communication_inbox_v4(t,s) i where (cursor_id is null or i.thread_id>cursor_id)
   and i.title not like '🧪 TEST:%' order by i.thread_id limit 250) q;
 elsif p_action='messages' then
  if not exists(select 1 from public.communication_threads where id=thread_id and team_id=t and (season_id=s or season_id is null) and archived_at is null)
   or not public.can_view_communication_thread(thread_id) then raise exception using errcode='42501',message='Conversation access is no longer available';end if;
  select coalesce(jsonb_agg(jsonb_build_object('message_id',m.message_id,'sender_name',m.sender_name,'body',m.body,
   'created_at',m.created_at,'is_mine',m.is_mine,'has_attachment',m.has_attachment,'safety_level',m.safety_level) order by m.created_at,m.message_id),'[]') into rows
   from public.get_communication_messages_v4(thread_id,null,80) m;
 elsif p_action='apply' then
  if op is null or kind not in ('message','attendance','event') or octet_length(p_data::text)>24000 then raise exception 'Invalid offline operation';end if;
  -- Unique insert blocks a concurrent retry until its transaction has finished.
  insert into private.offline_operations(user_id,operation_id,team_id,request) values(u,op,t,p_data) on conflict do nothing;
  select * into existing from private.offline_operations where user_id=u and operation_id=op for update;
  if existing.request is distinct from p_data then raise exception 'Operation ID was reused with different changes';end if;
  if existing.result is not null then return existing.result;end if;
  begin
   if kind='message' then
    if not exists(select 1 from public.communication_threads where id=thread_id and team_id=t and (season_id=s or season_id is null) and archived_at is null)
     or not public.can_view_communication_thread(thread_id) then raise exception 'Conversation access is no longer available';end if;
    answer:=jsonb_build_object('status','applied','value',private.communication_send_message(thread_id,p_data->>'body','text'));
   else
    select * into e from public.team_events where id=(p_data->>'event_id')::uuid and team_id=t and season_id=s for update;
    if e.id is null then raise exception 'This event is no longer available';end if;
    if kind='event' then
     if e.updated_at is distinct from stamp then answer:=jsonb_build_object('status','conflict','message','Another coach changed this event. Review both versions.','value',to_jsonb(e));
     else answer:=jsonb_build_object('status','applied','value',public.edit_team_event(e.id,stamp,p_data->'values'));end if;
    else
     if not exists(select 1 from public.roster_memberships where season_id=s and athlete_id=athlete and active and roster_status not in ('standby','removed','inactive')) then
      raise exception 'Attendance is only available for active wrestlers in this season';end if;
     if p_data->>'status' is null or p_data->>'status' not in ('expected','present','late','absent','modified') then raise exception 'Invalid attendance status';end if;
     select * into a from public.event_attendance where event_id=e.id and athlete_id=athlete for update;
     if a.id is null and stamp is null then
      -- Reserve missing row, including against legacy online writers using the same unique constraint.
      insert into public.event_attendance(event_id,athlete_id,status,excuse_status) values(e.id,athlete,'expected','none') on conflict do nothing returning * into a;
      created:=found;
      if not created then select * into a from public.event_attendance where event_id=e.id and athlete_id=athlete for update;end if;
     end if;
     if not created and a.updated_at is distinct from stamp then
      answer:=jsonb_build_object('status','conflict','message','Another coach changed this attendance. Review both versions.','value',case when a.id is null then null else jsonb_build_object('id',a.id,'event_id',a.event_id,'athlete_id',a.athlete_id,'status',a.status,'excuse_status',a.excuse_status,'updated_at',a.updated_at) end);
     else
      a:=public.mark_event_attendance(e.id,athlete,p_data->>'status');
      answer:=jsonb_build_object('status','applied','value',jsonb_build_object('id',a.id,'event_id',a.event_id,'athlete_id',a.athlete_id,'status',a.status,'excuse_status',a.excuse_status,'updated_at',a.updated_at));
     end if;
    end if;
   end if;
  exception when others then
   if sqlerrm ilike '%pause before sending%' then
    delete from private.offline_operations where user_id=u and operation_id=op;
    return jsonb_build_object('status','retry','message',sqlerrm);
   end if;
   answer:=jsonb_build_object('status','blocked','message',sqlerrm);
  end;
  update private.offline_operations set result=answer where user_id=u and operation_id=op;
  return answer;
 else raise exception 'Unknown offline action';end if;
 return rows;
end $$;
