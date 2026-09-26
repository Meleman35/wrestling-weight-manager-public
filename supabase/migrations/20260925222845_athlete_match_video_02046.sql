-- Held TestFlight draft. No grants, consent, provider, or production activation seeded.
begin;
alter table private.video_pilot_control add column cloud_enabled boolean not null default false,
 add column test_only boolean not null default true;
create table private.video_event_settings (
 event_id uuid primary key references public.team_events(id) on delete cascade,
 team_id uuid not null references public.teams(id), recording_permitted boolean not null default false,
 rules jsonb not null default '{}', updated_by uuid not null references public.profiles(id), updated_at timestamptz not null default now()
);
create table private.video_athlete_permissions (
 team_id uuid not null references public.teams(id), athlete_id uuid not null references public.athletes(id),
 guardian_id uuid not null references public.profiles(id), recording_allowed boolean not null default false,
 updated_at timestamptz not null default now(), primary key(team_id,athlete_id,guardian_id)
);
create table private.video_recorder_assignments (
 team_id uuid not null references public.teams(id), event_id uuid not null references public.team_events(id),
 athlete_id uuid not null references public.athletes(id), user_id uuid not null references public.profiles(id),
 expires_at timestamptz not null, assigned_by uuid not null references public.profiles(id),
 primary key(event_id,athlete_id,user_id)
);
create table private.video_scored_matches (
 id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id),
 bout_id uuid not null unique references private.tournament_bouts(id), event_id uuid not null references public.team_events(id),
 athlete_id uuid not null references public.athletes(id), recorder_id uuid not null references public.profiles(id),
 data jsonb not null, revision integer not null default 1, created_at timestamptz not null default now()
);
create table private.video_recordings (
 id uuid primary key, team_id uuid not null references public.teams(id), match_id uuid not null references private.video_scored_matches(id),
 athlete_id uuid not null references public.athletes(id), recorder_id uuid not null references public.profiles(id),
 status text not null default 'uploading' check(status in ('uploading','ready','removed')),
 video_path text not null unique, timeline_path text not null unique,
 bytes bigint not null check(bytes between 1 and 1073741824), timeline_bytes integer not null check(timeline_bytes between 1 and 16777216),
 mime text not null check(mime in ('video/mp4','video/webm','video/quicktime')),
 duration_ms integer not null check(duration_ms between 1 and 1205000), partial boolean not null default false,
 created_at timestamptz not null default now(), ready_at timestamptz
);
create index video_recordings_athlete on private.video_recordings(team_id,athlete_id,created_at desc);
create index video_recorder_user on private.video_recorder_assignments(team_id,user_id,expires_at);
alter table private.video_event_settings enable row level security;
alter table private.video_athlete_permissions enable row level security;
alter table private.video_recorder_assignments enable row level security;
alter table private.video_scored_matches enable row level security;
alter table private.video_recordings enable row level security;
revoke all on private.video_event_settings,private.video_athlete_permissions,private.video_recorder_assignments,private.video_scored_matches,private.video_recordings from public,anon,authenticated;

create function private.video_team_enabled(t uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and exists(select 1 from private.video_pilot_control where id and enabled)
 and exists(select 1 from private.video_pilot_grants g where g.team_id=t and g.revoked_at is null and g.expires_at>now())
$$;
create function private.video_consent(t uuid,a uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.video_athlete_permissions p join public.athlete_guardians g on g.athlete_id=p.athlete_id and g.guardian_user_id=p.guardian_id
 join public.team_memberships m on m.team_id=p.team_id and m.user_id=p.guardian_id and m.athlete_id=p.athlete_id and m.role='parent_guardian' and m.active
 where p.team_id=t and p.athlete_id=a and p.recording_allowed)
 and not exists(select 1 from private.video_athlete_permissions p join public.athlete_guardians g on g.athlete_id=p.athlete_id and g.guardian_user_id=p.guardian_id
 join public.team_memberships m on m.team_id=p.team_id and m.user_id=p.guardian_id and m.athlete_id=p.athlete_id and m.role='parent_guardian' and m.active
 where p.team_id=t and p.athlete_id=a and not p.recording_allowed)
$$;
create function private.video_can_record(t uuid,a uuid,ev uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.video_team_enabled(t) and not (select test_only from private.video_pilot_control where id) and private.video_consent(t,a)
 and exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where r.athlete_id=a and r.active and s.active and s.team_id=t)
 and exists(select 1 from private.video_event_settings v where v.team_id=t and v.event_id=ev and v.recording_permitted)
 and ( (public.is_team_staff(t) and exists(select 1 from private.video_pilot_grants g where g.team_id=t and g.user_id=auth.uid() and g.expires_at>now() and g.revoked_at is null))
 or exists(select 1 from private.video_recorder_assignments r join public.team_memberships m on m.team_id=t and m.user_id=r.user_id and m.active
 where r.team_id=t and r.event_id=ev and r.athlete_id=a and r.user_id=auth.uid() and r.expires_at>now()) )
 -- A teammate shortcut must not reveal opponent details hidden by guardian visibility.
 and (public.is_team_staff(t) or private.tournament_guardian(t,a) or coalesce((select level from private.tournament_visibility where athlete_id=a),'upcoming')='full')
$$;
create function private.video_can_view(t uuid,a uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.video_team_enabled(t) and private.video_consent(t,a) and private.tournament_athlete_access(t,a)
$$;

-- Keep the original staff-only local practice pilot; add exact event/athlete recorder leases.
create or replace function private.video_pilot_context(p_team_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare uid uuid=auth.uid(); expiry timestamptz; people jsonb; staff boolean=public.is_team_staff(p_team_id);
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal coach or assigned recorder account required'; end if;
 if not private.video_team_enabled(p_team_id) then return jsonb_build_object('allowed',false); end if;
 if staff or ((select test_only from private.video_pilot_control where id) and exists(select 1 from public.team_memberships where team_id=p_team_id and user_id=uid and active and role in ('athlete','manager'))) then select expires_at into expiry from private.video_pilot_grants where team_id=p_team_id and user_id=uid and revoked_at is null and expires_at>now(); end if;
 if expiry is not null then
  select coalesce(jsonb_agg(distinct r.athlete_id),'[]') into people from public.roster_memberships r join public.seasons s on s.id=r.season_id where s.team_id=p_team_id and s.active and r.active;
 else
  select max(r.expires_at),coalesce(jsonb_agg(distinct r.athlete_id),'[]') into expiry,people from private.video_recorder_assignments r
  where r.team_id=p_team_id and r.user_id=uid and private.video_can_record(r.team_id,r.athlete_id,r.event_id);
 end if;
 if expiry is null then return jsonb_build_object('allowed',false); end if;
 if (select test_only from private.video_pilot_control where id) then people='[]'::jsonb; end if;
 return jsonb_build_object('allowed',true,'user_id',uid,'team_id',p_team_id,'lease_seconds',greatest(0,least(7200,extract(epoch from expiry-now())::int)),
 'athlete_ids',people,'test_only',(select test_only from private.video_pilot_control where id),'cloud_upload',(select cloud_enabled and not test_only from private.video_pilot_control where id),'live',false,'billing',false);
end $$;

create function private.video_match_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
 u uuid=auth.uid(); t uuid=(p_data->>'team_id')::uuid; a uuid=(p_data->>'athlete_id')::uuid;
 ev uuid=(p_data->>'event_id')::uuid; bid uuid=(p_data->>'bout_id')::uuid; rid uuid=(p_data->>'id')::uuid;
 b record; m private.video_scored_matches; rec private.video_recordings; rules jsonb; d jsonb; items jsonb; n bigint; settings jsonb;
begin
 if u is null or exists(select 1 from private.team_logins where user_id=u) then raise exception 'Personal account required'; end if;
 if not private.video_team_enabled(t) then raise exception 'Video pilot is not enabled for this team'; end if;
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

-- Private object policies: immutable upload paths; no client overwrite/delete grants.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('match-video-pilot','match-video-pilot',false,1073741824,array['video/mp4','video/webm','video/quicktime','application/json']);
create function private.video_object_access(path text,writing boolean) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.video_recordings r join private.video_scored_matches m on m.id=r.match_id
 where path in (r.video_path,r.timeline_path) and private.video_team_enabled(r.team_id) and (select cloud_enabled and not test_only from private.video_pilot_control where id)
 and case when writing then r.status='uploading' and r.recorder_id=auth.uid() and private.video_can_record(r.team_id,r.athlete_id,m.event_id)
 else (r.status='ready' and private.video_can_view(r.team_id,r.athlete_id)) or (r.status in ('uploading','ready') and r.recorder_id=auth.uid() and private.video_can_record(r.team_id,r.athlete_id,m.event_id)) end)
$$;
create policy video_pilot_insert on storage.objects for insert to authenticated with check(bucket_id='match-video-pilot' and private.video_object_access(name,true));
create policy video_pilot_select on storage.objects for select to authenticated using(bucket_id='match-video-pilot' and private.video_object_access(name,false));
revoke all on function private.video_team_enabled(uuid),private.video_consent(uuid,uuid),private.video_can_record(uuid,uuid,uuid),private.video_can_view(uuid,uuid),private.video_object_access(text,boolean),private.video_match_request(text,jsonb) from public,anon,authenticated;
grant execute on function private.video_object_access(text,boolean),private.video_match_request(text,jsonb) to authenticated;
create function public.video_match_request(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.video_match_request(p_action,p_data)$$;
revoke all on function public.video_match_request(text,jsonb) from public,anon;
grant execute on function public.video_match_request(text,jsonb) to authenticated;
commit;
