-- Dated competition/practice restrictions. Existing manual restrictions remain intact.
alter table private.roster_eligibility
 add column practice_allowed boolean not null default true,
 add column restricted_from date,
 add column restricted_through date,
 add column timezone text not null default 'UTC',
 add constraint eligibility_date_order check (restricted_through is null or (restricted_from is not null and restricted_through>=restricted_from));

create or replace function private.roster_eligibility_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid;s uuid=(p_data->>'season_id')::uuid;a uuid=(p_data->>'athlete_id')::uuid;r private.roster_eligibility%rowtype;
 v boolean;practice boolean;starts date;ends date;tz text;today date;in_period boolean;
begin
 select team_id into t from public.seasons where id=s;
 if auth.uid() is null or t is null or not public.is_team_staff(t) or exists(select 1 from private.team_logins where user_id=auth.uid()) then raise exception 'Coach personal account required';end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(jsonb_build_object(
   'athlete_id',rm.athlete_id,'photo_path',ath.photo_path,'rules_version',2,
   'eligible',coalesce(e.eligible,true) or (e.restricted_from is not null and (now() at time zone e.timezone)::date<e.restricted_from) or (e.restricted_through is not null and (now() at time zone e.timezone)::date>e.restricted_through),
   'competition_allowed',coalesce(e.eligible,true),'practice_allowed',coalesce(e.practice_allowed,true),
   'restricted_from',e.restricted_from,'restricted_through',e.restricted_through,'timezone',e.timezone,'revision',coalesce(e.revision,0)))
   from public.roster_memberships rm join public.athletes ath on ath.id=rm.athlete_id left join private.roster_eligibility e using(season_id,athlete_id) where rm.season_id=s),'[]');
 elsif p_action='save' then
  if jsonb_typeof(p_data->'eligible') is distinct from 'boolean' or a is null then raise exception 'Choose Eligible or Ineligible';end if;
  perform 1 from public.roster_memberships where season_id=s and athlete_id=a for update;
  if not found then raise exception 'Athlete is not on this season roster';end if;
  select * into r from private.roster_eligibility where season_id=s and athlete_id=a;
  if coalesce(r.revision,0) is distinct from (p_data->>'revision')::int then raise exception 'Eligibility changed. Reopen Roster before saving';end if;
  v:=(p_data->>'eligible')::boolean;
  -- Old clients may restore eligibility, but cannot silently erase a dated/practice rule.
  if p_data->>'rules_version' is distinct from '2' and not v and (r.restricted_from is not null or not coalesce(r.practice_allowed,true)) then raise exception 'Update the app to edit this eligibility restriction';end if;
  if p_data->>'rules_version'='2' then
   if jsonb_typeof(p_data->'practice_allowed') is distinct from 'boolean' then raise exception 'Choose the practice eligibility';end if;
   practice:=(p_data->>'practice_allowed')::boolean;
   starts:=nullif(p_data->>'restricted_from','')::date;ends:=nullif(p_data->>'restricted_through','')::date;tz:=p_data->>'timezone';
   if tz is null or not exists(select 1 from pg_catalog.pg_timezone_names where name=tz) then raise exception 'Choose a valid time zone';end if;
   if (not v or not practice) and starts is null then raise exception 'Choose the restriction start date';end if;
   if ends is not null and (starts is null or ends<starts) then raise exception 'The last restricted day must be on or after the start';end if;
  else practice:=true;tz:='UTC';end if;
  if v and practice then starts:=null;ends:=null;end if;
  insert into private.roster_eligibility(season_id,athlete_id,eligible,practice_allowed,restricted_from,restricted_through,timezone,changed_by)
  values(s,a,v,practice,starts,ends,tz,auth.uid())
  on conflict(season_id,athlete_id) do update set eligible=excluded.eligible,practice_allowed=excluded.practice_allowed,restricted_from=excluded.restricted_from,restricted_through=excluded.restricted_through,timezone=excluded.timezone,revision=private.roster_eligibility.revision+1,changed_by=auth.uid(),changed_at=clock_timestamp() returning * into r;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'competition_eligibility_changed','athlete',a,jsonb_build_object('team_id',t,'season_id',s));
  today:=(now() at time zone tz)::date;in_period:=(starts is null or today>=starts) and (ends is null or today<=ends);
  return jsonb_build_object('athlete_id',a,'eligible',v or not in_period,'competition_allowed',v,'practice_allowed',practice,'restricted_from',starts,'restricted_through',ends,'timezone',tz,'revision',r.revision,'rules_version',2);
 end if;
 raise exception 'Unknown eligibility action';
end $$;

-- Preserve attendance records; hide inactive memberships from current attendance views.
create or replace function private.attendance_summary_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if a is not null and not exists(select 1 from public.roster_memberships where season_id=s and athlete_id=a and active and roster_status not in ('standby','removed','inactive')) then raise exception 'Attendance is shown for active wrestlers only. This athlete is on standby or removed; their saved history is preserved';end if;
 select coalesce(jsonb_agg(jsonb_build_object('athlete_id',r.athlete_id,'name',concat_ws(' ',x.first_name,x.last_name),'active',r.active,'roster_status',r.roster_status) order by x.last_name,x.first_name),'[]') into athletes from public.roster_memberships r join public.athletes x on x.id=r.athlete_id where r.season_id=s and r.active and r.roster_status not in ('standby','removed','inactive') and (coach or r.athlete_id=a);
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
