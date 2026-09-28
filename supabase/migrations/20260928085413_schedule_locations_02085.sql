-- Edit the original record, including past events. Attendance and RSVP foreign keys remain intact.
create or replace function public.edit_team_event(p_id uuid,p_expected timestamptz,p_values jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.team_events%rowtype;s timestamptz;f timestamptz;
begin
 if auth.uid() is null or exists(select 1 from private.team_logins where user_id=auth.uid()) then raise exception 'Use a coach personal account';end if;
 select * into e from public.team_events where id=p_id for update;
 if e.id is null or not public.is_team_staff(e.team_id) then raise exception 'Coach access to this event is required';end if;
 if e.updated_at is distinct from p_expected then raise exception 'This event changed. Reopen it before saving';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or octet_length(p_values::text)>18000 then raise exception 'Invalid event changes';end if;
 s:=(p_values->>'starts_at')::timestamptz;f:=nullif(p_values->>'ends_at','')::timestamptz;
 if s is null or (f is not null and f<=s) then raise exception 'Choose a start and a later end';end if;
 if length(trim(coalesce(p_values->>'title',''))) not between 1 and 200 or length(coalesce(p_values->>'description',''))>10000 then raise exception 'Add a short event title and notes';end if;
 if e.generated_from_series and e.practice_series_id is not null then
  insert into public.practice_series_exceptions(series_id,occurrence_date,created_by) values(e.practice_series_id,e.recurring_occurrence_date,auth.uid()) on conflict do nothing;
 end if;
 update public.team_events set title=trim(p_values->>'title'),description=nullif(p_values->>'description',''),
  location_name=nullif(p_values->>'location_name',''),location_address=nullif(p_values->>'location_address',''),starts_at=s,ends_at=f,
  arrival_at=nullif(p_values->>'arrival_at','')::timestamptz,weigh_in_at=nullif(p_values->>'weigh_in_at','')::timestamptz,
  attendance_required=coalesce((p_values->>'attendance_required')::boolean,e.attendance_required),rsvp_enabled=coalesce((p_values->>'rsvp_enabled')::boolean,e.rsvp_enabled),
  checkout_enabled=coalesce((p_values->>'checkout_enabled')::boolean,e.checkout_enabled),counts_toward_season_attendance=coalesce((p_values->>'counts_toward_season_attendance')::boolean,e.counts_toward_season_attendance),
  generated_from_series=false,repeat_batch_id=null,updated_at=clock_timestamp() where id=p_id returning * into e;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'edit_team_event','team_event',e.id,jsonb_build_object('team_id',e.team_id));
 return to_jsonb(e);
end $$;
revoke all on function public.edit_team_event(uuid,timestamptz,jsonb) from public,anon;
grant execute on function public.edit_team_event(uuid,timestamptz,jsonb) to authenticated;

create table private.team_saved_locations(id uuid primary key default gen_random_uuid(),team_id uuid not null references public.teams(id),name text not null,address text not null default '',created_by uuid not null references auth.users(id),unique(team_id,name,address));
alter table private.team_saved_locations enable row level security;
revoke all on private.team_saved_locations from public,anon,authenticated;
create function private.saved_locations_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid=(p_data->>'team_id')::uuid;n text=trim(p_data->>'name');a text=trim(coalesce(p_data->>'address',''));
begin
 if auth.uid() is null or not public.is_team_staff(t) or exists(select 1 from private.team_logins where user_id=auth.uid()) then raise exception 'Coach personal account required';end if;
 if p_action='save' then
  if n is null or length(n) not between 1 and 200 or length(a)>1000 then raise exception 'Add a location name and a short address';end if;
  perform 1 from public.teams where id=t for update;
  if (select count(*) from private.team_saved_locations where team_id=t)>=100 then raise exception 'Remove an unused favorite first (100 maximum)';end if;
  insert into private.team_saved_locations(team_id,name,address,created_by) values(t,n,a,auth.uid()) on conflict(team_id,name,address) do nothing;
 elsif p_action='remove' then delete from private.team_saved_locations where id=(p_data->>'id')::uuid and team_id=t;
 elsif p_action<>'list' then raise exception 'Unknown location action';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'address',address) order by name) from private.team_saved_locations where team_id=t),'[]');
end $$;
revoke all on function private.saved_locations_request(text,jsonb) from public,anon;
grant execute on function private.saved_locations_request(text,jsonb) to authenticated;
create function public.saved_locations_request(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.saved_locations_request(p_action,p_data)$$;
revoke all on function public.saved_locations_request(text,jsonb) from public,anon;
grant execute on function public.saved_locations_request(text,jsonb) to authenticated;

-- Repeating edits preserve the original record. Only untouched future siblings may be replaced.
-- All existing FK children are inspected; a saved RSVP, attendance, video, weight or post blocks bulk replacement.
create function private.event_has_records(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare fk record;used boolean;
begin
 for fk in select n.nspname,c.relname,a.attname from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=con.conrelid and a.attnum=con.conkey[1] where con.contype='f' and con.confrelid='public.team_events'::regclass loop
  execute format('select exists(select 1 from %I.%I where %I=$1)',fk.nspname,fk.relname,fk.attname) into used using p_id;
  if used then return true;end if;
 end loop;
 return false;
end $$;
revoke all on function private.event_has_records(uuid) from public,anon,authenticated;
create table private.event_series_edits(id uuid primary key,actor uuid not null references auth.users(id),request jsonb not null,result jsonb not null);
alter table private.event_series_edits enable row level security;
revoke all on private.event_series_edits from public,anon,authenticated;
create function private.edit_event_recurrence(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.team_events%rowtype;other public.team_events%rowtype;u uuid=auth.uid();ids uuid[];fingerprint text;blocked int=0;batch jsonb;q jsonb;v jsonb=p_data->'values';rec jsonb=p_data->'repeat';cid uuid=(p_data->>'client_id')::uuid;zone text;old private.event_series_edits%rowtype;result jsonb;first_at timestamp;generated uuid;
begin
 if u is null or exists(select 1 from private.team_logins where user_id=u) then raise exception 'Coach personal account required';end if;
 select * into e from public.team_events where id=(p_data->>'event_id')::uuid for update;
 if e.id is null or not public.is_team_staff(e.team_id) then raise exception 'Coach access to this event required';end if;
 if p_action not in ('preview','save') or cid is null or p_data is null or octet_length(p_data::text)>30000 then raise exception 'Invalid recurrence request';end if;
 perform pg_advisory_xact_lock(hashtextextended(e.team_id::text,85));
 select * into old from private.event_series_edits where id=cid;
 if old.id is not null then
  if old.actor<>u or old.request<>p_data then raise exception 'This repeat request changed. Reopen the event';end if;return old.result;
 end if;
 if e.updated_at is distinct from (p_data->>'expected')::timestamptz then raise exception 'Event changed. Reopen it before changing repeats';end if;
 zone:=rec->>'timezone';first_at:=(rec->>'start_local')::timestamp;
 if zone is null or not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Choose a valid time zone';end if;
 if e.starts_at<=now() or first_at at time zone zone<=now() then raise exception 'Repeat changes start with an upcoming event. Edit a past occurrence individually';end if;
 if rec->>'frequency' not in ('none','daily','weekly','monthly') or rec->>'frequency' is null then raise exception 'Choose repeat frequency';end if;
 if e.practice_series_id is not null then perform 1 from public.practice_series where id=e.practice_series_id for update;end if;
 ids:=array[]::uuid[];
 for other in select * from public.team_events x where x.id<>e.id and x.starts_at>=e.starts_at and ((e.repeat_batch_id is not null and x.repeat_batch_id=e.repeat_batch_id) or (e.practice_series_id is not null and x.practice_series_id=e.practice_series_id and x.generated_from_series)) order by x.id for update loop
  ids:=array_append(ids,other.id);
  if private.event_has_records(other.id) then blocked:=blocked+1;end if;
 end loop;
 select md5(coalesce(string_agg(id::text||updated_at::text,',' order by id),'')) into fingerprint from public.team_events where id=any(ids);
 if p_action='preview' then return jsonb_build_object('replace_count',cardinality(ids),'blocked_count',blocked,'fingerprint',fingerprint);end if;
 if fingerprint is distinct from p_data->>'fingerprint' then raise exception 'Repeating schedule changed. Preview again';end if;
 if blocked>0 then raise exception 'Some future events already have saved records. Edit those occurrences individually; no events were changed';end if;
 -- Stop the old weekly generator before cutting over; past events and manual exceptions are retained.
 if e.practice_series_id is not null then
  update public.practice_series set active=case when first_on>=e.recurring_occurrence_date then false else active end,last_on=greatest(first_on,least(last_on,e.recurring_occurrence_date-1)),updated_at=clock_timestamp() where id=e.practice_series_id;
 end if;
 perform public.edit_team_event(e.id,e.updated_at,v);
 update public.team_events set practice_series_id=null,recurring_occurrence_date=null,generated_from_series=false,repeat_batch_id=null where id=e.id;
 delete from public.team_events where id=any(ids);
 if rec->>'frequency'<>'none' then
  q:=rec||jsonb_build_object('client_id',cid,'team_id',e.team_id,'season_id',e.season_id,'event',to_jsonb(e)||v);
  batch:=public.create_repeating_events(q);
  -- The original event occupies the first date and keeps its existing attendance/RSVPs.
  select id into generated from public.team_events where repeat_batch_id=cid and starts_at=first_at at time zone zone;
  if generated is null then raise exception 'Include the start day in the repeating weekdays';end if;
  if private.event_has_records(generated) then raise exception 'Generated event acquired records. Reopen and try again';end if;
  delete from public.team_events where id=generated;
  update public.team_events set repeat_batch_id=cid where id=e.id;
  update private.event_repeat_batches b set result=jsonb_set(b.result,'{event_ids}',(select jsonb_agg(id order by starts_at) from public.team_events where repeat_batch_id=cid)) where id=cid;
 end if;
 select to_jsonb(x) into result from public.team_events x where id=e.id;
 insert into private.event_series_edits(id,actor,request,result) values(cid,u,p_data,result);
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(u,'edit_event_recurrence','team_event',e.id,jsonb_build_object('team_id',e.team_id,'replaced',cardinality(ids)));
 return result;
end $$;
revoke all on function private.edit_event_recurrence(text,jsonb) from public,anon;
grant execute on function private.edit_event_recurrence(text,jsonb) to authenticated;
create function public.edit_event_recurrence(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.edit_event_recurrence(p_action,p_data)$$;
revoke all on function public.edit_event_recurrence(text,jsonb) from public,anon;
grant execute on function public.edit_event_recurrence(text,jsonb) to authenticated;
