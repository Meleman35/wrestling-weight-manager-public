-- Edit the original record, including past events. Attendance and RSVP foreign keys remain intact.
create function public.edit_team_event(p_id uuid,p_expected timestamptz,p_values jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  generated_from_series=false,updated_at=clock_timestamp() where id=p_id returning * into e;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'edit_team_event','team_event',e.id,jsonb_build_object('team_id',e.team_id));
 return to_jsonb(e);
end $$;
revoke all on function public.edit_team_event(uuid,timestamptz,jsonb) from public,anon;
grant execute on function public.edit_team_event(uuid,timestamptz,jsonb) to authenticated;
