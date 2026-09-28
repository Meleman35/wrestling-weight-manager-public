set local role authenticated;
do $$
declare q jsonb;t uuid=current_setting('ra.t')::uuid;s uuid=current_setting('ra.s')::uuid;a uuid=current_setting('ra.a')::uuid;e public.team_events%rowtype;r jsonb;prev jsonb;sibling uuid;cid uuid=gen_random_uuid();start_at timestamp=((now() at time zone 'America/Denver')::date+7)::timestamp+interval '18 hours';
begin
 perform set_config('request.jwt.claim.sub',current_setting('ra.c'),true);
 r:=public.saved_locations_request('save',jsonb_build_object('team_id',t,'name','Wrestling Room','address','100 School St'));
 perform pg_temp.check(jsonb_array_length(r)=1,'saved location');perform public.saved_locations_request('save',jsonb_build_object('team_id',t,'name','Wrestling Room','address','100 School St'));perform pg_temp.check(jsonb_array_length(public.saved_locations_request('list',jsonb_build_object('team_id',t)))=1,'favorite deduplication');
 insert into public.team_events(team_id,season_id,event_type,title,starts_at,ends_at,created_by) values(t,s,'open_mat','Original open mat',start_at at time zone 'America/Denver',(start_at+interval '90 minutes') at time zone 'America/Denver',auth.uid()) returning * into e;
 insert into public.event_attendance(event_id,athlete_id,status) values(e.id,a,'present');
 q:=jsonb_build_object('client_id',cid,'event_id',e.id,'expected',e.updated_at,'values',to_jsonb(e),'repeat',jsonb_build_object('frequency','daily','start_local',start_at,'end_local',start_at+interval '90 minutes','until',start_at::date+2,'weekdays','[]'::jsonb,'timezone','America/Denver'));
 prev:=public.edit_event_recurrence('preview',q);q:=q||jsonb_build_object('fingerprint',prev->>'fingerprint');r:=public.edit_event_recurrence('save',q);
 perform pg_temp.check(r->>'id'=e.id::text,'original event ID preserved');perform pg_temp.check(exists(select 1 from public.event_attendance where event_id=e.id and status='present'),'original attendance preserved');perform pg_temp.check((select count(*)=3 from public.team_events where repeat_batch_id=cid),'repeat creates exactly three dates');
 perform pg_temp.check(public.edit_event_recurrence('save',q)=r,'repeat save retry returns same result');
 select * into e from public.team_events where id=e.id;
 q:=q||jsonb_build_object('client_id',gen_random_uuid(),'expected',e.updated_at,'values',to_jsonb(e),'repeat',(q->'repeat')||jsonb_build_object('frequency','none'));
 select id into sibling from public.team_events where repeat_batch_id=cid and id<>e.id order by starts_at limit 1;
 insert into public.event_attendance(event_id,athlete_id,status) values(sibling,a,'expected');
 prev:=public.edit_event_recurrence('preview',q);perform pg_temp.check(prev->>'blocked_count'='1','saved child record blocks destructive series replace');
 perform pg_temp.denied(format('select public.edit_event_recurrence(''save'',%L)',q||jsonb_build_object('fingerprint',prev->>'fingerprint')),'saved records');
 perform set_config('request.jwt.claim.sub',current_setting('ra.x'),true);perform pg_temp.denied(format('select public.edit_event_recurrence(''preview'',%L)',q),'Coach access');perform pg_temp.denied(format('select public.saved_locations_request(''list'',%L)',jsonb_build_object('team_id',t)),'Coach personal');
end $$;
reset role;
-- Remove only our synthetic blocking row, then verify stopping an untouched series preserves the anchor.
do $$
declare e public.team_events%rowtype;q jsonb;prev jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('ra.c'),true);
 delete from public.event_attendance where status='expected' and athlete_id=current_setting('ra.a')::uuid;
 select * into e from public.team_events where team_id=current_setting('ra.t')::uuid and title='Original open mat' order by starts_at limit 1;
 q:=jsonb_build_object('client_id',gen_random_uuid(),'event_id',e.id,'expected',e.updated_at,'values',to_jsonb(e),'repeat',jsonb_build_object('frequency','none','start_local',e.starts_at at time zone 'America/Denver','timezone','America/Denver'));
 prev:=public.edit_event_recurrence('preview',q);perform public.edit_event_recurrence('save',q||jsonb_build_object('fingerprint',prev->>'fingerprint'));
 perform pg_temp.check((select count(*)=1 from public.team_events where team_id=e.team_id and title=e.title),'stop removes only untouched future siblings');
 perform pg_temp.check(exists(select 1 from public.event_attendance where event_id=e.id),'stop keeps anchor attendance');
end $$;
select 'PASS: team favorites, repeat existing event, original ID/history, idempotent retry, record protection, private access and stop future recurrence' result;
