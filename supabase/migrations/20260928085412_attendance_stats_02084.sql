-- Percentages use completed Schedule events and recorded attendance, never RSVPs.
create table private.attendance_preferences (
 team_id uuid primary key references public.teams(id), event_types text[] not null default array['practice','dual','tournament'],
 excused_counts boolean not null default false, modified_counts boolean not null default true,
 revision integer not null default 1, updated_at timestamptz not null default now()
);
alter table private.attendance_preferences enable row level security;
revoke all on private.attendance_preferences from public,anon,authenticated;
create function private.attendance_summary_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid=(p_data->>'season_id')::uuid;t uuid;a uuid=(p_data->>'athlete_id')::uuid;
 pref private.attendance_preferences%rowtype;coach boolean;types text[];events jsonb;athletes jsonb;
begin
 select team_id into t from public.seasons where id=s;
 if auth.uid() is null or t is null or exists(select 1 from private.team_logins where user_id=auth.uid()) then raise exception 'Use a personal account and select a season';end if;
 coach:=public.is_team_staff(t) and not coalesce((p_data->>'view_as_parent')::boolean,false);
 if not coach and not (a is not null and exists(select 1 from public.roster_memberships where season_id=s and athlete_id=a) and (public.is_self_athlete(a) or public.is_guardian_for_athlete(a))) then raise exception 'Attendance is private to this athlete, linked guardians and coaches';end if;
 select * into pref from private.attendance_preferences where team_id=t;
 pref.event_types:=coalesce(pref.event_types,array['practice','dual','tournament']);pref.excused_counts:=coalesce(pref.excused_counts,false);pref.modified_counts:=coalesce(pref.modified_counts,true);pref.revision:=coalesce(pref.revision,0);
 if p_action='settings' then
  if not coach then raise exception 'Coach access required';end if;
  perform 1 from public.teams where id=t for update;
  if coalesce((select revision from private.attendance_preferences where team_id=t),0) is distinct from (p_data->>'revision')::int then raise exception 'Attendance settings changed. Reopen Attendance';end if;
  if jsonb_typeof(p_data->'event_types') is distinct from 'array' or jsonb_array_length(p_data->'event_types')>10 or jsonb_typeof(p_data->'excused_counts') is distinct from 'boolean' or jsonb_typeof(p_data->'modified_counts') is distinct from 'boolean' then raise exception 'Invalid attendance settings';end if;
  select array_agg(distinct value) into types from jsonb_array_elements_text(p_data->'event_types');
  if coalesce(cardinality(types),0)=0 or exists(select 1 from unnest(types) v where v not in ('practice','dual','tournament','open_mat','camp','travel','meeting','weigh_in','wrestle_off','other')) then raise exception 'Choose at least one valid event type';end if;
  insert into private.attendance_preferences(team_id,event_types,excused_counts,modified_counts) values(t,types,(p_data->>'excused_counts')::boolean,(p_data->>'modified_counts')::boolean)
  on conflict(team_id) do update set event_types=excluded.event_types,excused_counts=excluded.excused_counts,modified_counts=excluded.modified_counts,revision=private.attendance_preferences.revision+1,updated_at=clock_timestamp() returning * into pref;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'attendance_settings_changed','team',t,'{}');
 elsif p_action<>'read' then raise exception 'Unknown attendance action';end if;
 if a is not null and not exists(select 1 from public.roster_memberships where season_id=s and athlete_id=a) then raise exception 'Athlete is not on this season roster';end if;
 select coalesce(jsonb_agg(jsonb_build_object('athlete_id',r.athlete_id,'name',concat_ws(' ',x.first_name,x.last_name),'active',r.active) order by x.last_name,x.first_name),'[]') into athletes from public.roster_memberships r join public.athletes x on x.id=r.athlete_id where r.season_id=s and (coach or r.athlete_id=a);
 if a is not null then
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,'starts_at',e.starts_at,'event_type',e.event_type,'status',coalesce(att.status,'expected'),'excused',coalesce(att.excuse_status='excused',false)) order by e.starts_at desc),'[]') into events
  from public.team_events e join public.roster_memberships rm on rm.season_id=s and rm.athlete_id=a
  left join public.event_attendance att on att.event_id=e.id and att.athlete_id=a
  where e.team_id=t and e.season_id=s and e.attendance_required and e.counts_toward_season_attendance
   and e.event_type=any(pref.event_types) and coalesce(e.ends_at,e.starts_at)<=now()
   and (att.id is not null or (e.starts_at>=rm.created_at and e.practice_groups='{}'::jsonb));
 end if;
 return jsonb_build_object('team_id',t,'season_id',s,'athlete_id',a,'can_manage',coach,'athletes',athletes,'events',coalesce(events,'[]'),'settings',jsonb_build_object('event_types',pref.event_types,'excused_counts',pref.excused_counts,'modified_counts',pref.modified_counts,'revision',pref.revision));
end $$;
revoke all on function private.attendance_summary_request(text,jsonb) from public,anon;
grant execute on function private.attendance_summary_request(text,jsonb) to authenticated;
create function public.attendance_summary_request(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.attendance_summary_request(p_action,p_data)$$;
revoke all on function public.attendance_summary_request(text,jsonb) from public,anon;
grant execute on function public.attendance_summary_request(text,jsonb) to authenticated;
