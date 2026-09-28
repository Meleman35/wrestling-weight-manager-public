-- Repeating event creation is atomic and retry-safe. Wall clock times stay fixed across DST.
create table private.event_repeat_batches(id uuid primary key,team_id uuid not null references public.teams(id),created_by uuid not null references public.profiles(id),request jsonb not null,result jsonb,created_at timestamptz not null default now());
create index event_repeat_batches_team on private.event_repeat_batches(team_id);
alter table private.event_repeat_batches enable row level security;
revoke all on private.event_repeat_batches from public,anon,authenticated;
alter table public.team_events add column repeat_batch_id uuid references private.event_repeat_batches(id);
create index team_events_repeat_batch on public.team_events(repeat_batch_id) where repeat_batch_id is not null;
create function public.create_repeating_events(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();t uuid=(p_data->>'team_id')::uuid;s uuid=(p_data->>'season_id')::uuid;bid uuid=(p_data->>'client_id')::uuid;
 b private.event_repeat_batches%rowtype;v jsonb=p_data->'event';mode text=p_data->>'frequency';zone text=p_data->>'timezone';first_at timestamp=(p_data->>'start_local')::timestamp;end_at timestamp=nullif(p_data->>'end_local','')::timestamp;last_on date=(p_data->>'until')::date;day date;at_local timestamp;offset_day interval;days int[];n int=0;ids jsonb='[]';eid uuid;
begin
 if u is null or exists(select 1 from private.team_logins where user_id=u) or not public.is_team_staff(t) then raise exception 'A coach using a personal account must create events';end if;
 if not exists(select 1 from public.seasons where id=s and team_id=t) then raise exception 'Choose a season for this team';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>25000 or bid is null then raise exception 'Invalid repeating event';end if;
 perform pg_advisory_xact_lock(hashtextextended(bid::text,80));
 select * into b from private.event_repeat_batches where id=bid;
 if b.id is not null then
  if b.created_by<>u or b.team_id<>t or b.request<>p_data then raise exception 'This saved series differs. Reopen the event form to start another';end if;return b.result;
 end if;
 if mode not in ('daily','weekly','monthly') or mode is null or first_at is null or last_on is null or last_on<first_at::date or last_on>first_at::date+366 then raise exception 'Choose repeat dates within one year';end if;
 if zone is null or not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Choose a valid time zone';end if;
 if end_at is not null and (end_at<=first_at or end_at>first_at+interval '7 days') then raise exception 'End must be after the start and within seven days';end if;
 if v is null or jsonb_typeof(v)<>'object' or length(trim(coalesce(v->>'title',''))) not between 1 and 200 or length(coalesce(v->>'description',''))>10000 or length(coalesce(v->>'location_name',''))>500 or length(coalesce(v->>'location_address',''))>1000 then raise exception 'Add a short title and location';end if;
 if coalesce(v->>'event_type','') not in ('practice','open_mat','dual','tournament','camp','travel','meeting','weigh_in','wrestle_off','other') then raise exception 'Choose an event type';end if;
 select array_agg(value::int) into days from jsonb_array_elements_text(coalesce(p_data->'weekdays','[]'));
 if mode='weekly' and (coalesce(cardinality(days),0)=0 or exists(select 1 from unnest(days) x where x not between 1 and 7)) then raise exception 'Choose at least one weekday';end if;
 if (select count(*) from private.event_repeat_batches where created_by=u and created_at>now()-interval '1 hour')>=20 then raise exception 'Please pause before creating more series';end if;
 insert into private.event_repeat_batches(id,team_id,created_by,request) values(bid,t,u,p_data);
 for day in select d::date from generate_series(first_at::date::timestamp,last_on::timestamp,interval '1 day') d loop
  if mode='weekly' and not(extract(isodow from day)::int=any(days)) then continue;end if;
  if mode='monthly' and extract(day from day)<>extract(day from first_at) then continue;end if;
  offset_day:=(day-first_at::date)*interval '1 day';at_local:=first_at+offset_day;
  insert into public.team_events(team_id,season_id,event_type,title,description,starts_at,ends_at,arrival_at,weigh_in_at,location_name,location_address,attendance_required,rsvp_enabled,checkout_enabled,counts_toward_season_attendance,created_by,practice_groups,pre_weigh_cutoff_at,post_weigh_start_at,repeat_batch_id)
  values(t,s,v->>'event_type',trim(v->>'title'),nullif(v->>'description',''),at_local at time zone zone,(end_at+offset_day) at time zone zone,(nullif(p_data->>'arrival_local','')::timestamp+offset_day) at time zone zone,(nullif(p_data->>'weigh_in_local','')::timestamp+offset_day) at time zone zone,nullif(v->>'location_name',''),nullif(v->>'location_address',''),coalesce((v->>'attendance_required')::boolean,true),coalesce((v->>'rsvp_enabled')::boolean,true),coalesce((v->>'checkout_enabled')::boolean,false),coalesce((v->>'counts_toward_season_attendance')::boolean,true),u,coalesce(v->'practice_groups','{}'),case when v->>'event_type'='practice' then (nullif(p_data->>'pre_local','')::timestamp+offset_day) at time zone zone end,case when v->>'event_type'='practice' then (nullif(p_data->>'post_local','')::timestamp+offset_day) at time zone zone end,bid) returning id into eid;
  n:=n+1;ids:=ids||jsonb_build_array(eid);
 end loop;
 if n=0 then raise exception 'No selected days fall within these dates';end if;
 if v->>'event_type' in ('dual','tournament') then perform public.sync_recurring_practices_for_season(s);end if;
 if v->>'event_type'='practice' then perform public.reclassify_practice_weights_for_season(s);end if;
 update private.event_repeat_batches set result=jsonb_build_object('id',bid,'count',n,'event_ids',ids) where id=bid returning result into v;
 return v;
end $$;
revoke all on function public.create_repeating_events(jsonb) from public,anon;
grant execute on function public.create_repeating_events(jsonb) to authenticated;
