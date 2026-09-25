-- Preparation only: no cron registration, inbox insertion, delivery queue or network call.
begin;
create table private.tournament_alert_preferences (
 team_id uuid not null references public.teams(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 countdown_minutes integer[] not null default '{}'
   check(countdown_minutes <@ array[60,30,15,10,5] and array_position(countdown_minutes,null) is null and cardinality(countdown_minutes)<=5),
 readiness boolean not null default false,
 changes boolean not null default false,
 revision integer not null default 1,
 updated_at timestamptz not null default now(),
 next_check_at timestamptz not null default now(),
 primary key(team_id,user_id)
);
create index tournament_alert_preferences_due_idx on private.tournament_alert_preferences(next_check_at,team_id,user_id);
create table private.tournament_alert_state (
 team_id uuid not null,
 user_id uuid not null,
 bout_id uuid not null references private.tournament_bouts(id) on delete cascade,
 seen_minutes integer[] not null default '{}',
 seen_statuses text[] not null default '{}',
 revision integer not null default 0,
 updated_at timestamptz not null,
 mat text not null,
 estimated_start timestamptz,
 primary key(team_id,user_id,bout_id),
 foreign key(team_id,user_id) references private.tournament_alert_preferences(team_id,user_id) on delete cascade
);
create index tournament_alert_state_bout_idx on private.tournament_alert_state(bout_id);
create table private.tournament_alert_drafts (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null,
 user_id uuid not null,
 bout_id uuid not null references private.tournament_bouts(id) on delete cascade,
 athlete_id uuid not null references public.athletes(id) on delete cascade,
 event_key text not null,
 kind text not null check(kind in ('countdown','readiness','assignment','reschedule')),
 source_revision integer not null,
 payload jsonb not null,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 unique(team_id,user_id,bout_id,event_key),
 foreign key(team_id,user_id) references private.tournament_alert_preferences(team_id,user_id) on delete cascade
);
create index tournament_alert_drafts_bout_idx on private.tournament_alert_drafts(bout_id);
create index tournament_alert_drafts_athlete_idx on private.tournament_alert_drafts(athlete_id);
create index tournament_alert_drafts_expiry_idx on private.tournament_alert_drafts(expires_at);
alter table private.tournament_alert_preferences enable row level security;
alter table private.tournament_alert_state enable row level security;
alter table private.tournament_alert_drafts enable row level security;
revoke all on private.tournament_alert_preferences,private.tournament_alert_state,private.tournament_alert_drafts from public,anon,authenticated;

create function private.tournament_alert_preferences_request(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid=auth.uid();tid uuid;pref private.tournament_alert_preferences%rowtype;minutes integer[];
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>2048 then raise exception 'Invalid alert preference request';end if;
 tid:=(p_data->>'team_id')::uuid;
 -- Reuse the complete tournament access boundary, including managed-login denial.
 perform private.tournament_request('context',jsonb_build_object('team_id',tid));
 if p_action not in ('get','save') or p_action is null then raise exception 'Unknown alert preference action';end if;
 if p_action='save' then
  if jsonb_typeof(p_data->'countdown_minutes') is distinct from 'array'
   or jsonb_typeof(p_data->'readiness') is distinct from 'boolean'
   or jsonb_typeof(p_data->'changes') is distinct from 'boolean'
   or jsonb_typeof(p_data->'revision') is distinct from 'number' then raise exception 'Choose valid tournament alert settings';end if;
  if jsonb_array_length(p_data->'countdown_minutes')>5 or exists(select 1 from jsonb_array_elements(p_data->'countdown_minutes') x where x not in ('5'::jsonb,'10'::jsonb,'15'::jsonb,'30'::jsonb,'60'::jsonb)) then raise exception 'Choose supported reminder times';end if;
  select coalesce(array_agg(distinct value::int order by value::int desc),'{}') into minutes from jsonb_array_elements_text(p_data->'countdown_minutes');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('tournament-alert-pref:'||tid::text||':'||uid::text,0));
  select * into pref from private.tournament_alert_preferences where team_id=tid and user_id=uid for update;
  if coalesce(pref.revision,0) is distinct from (p_data->>'revision')::integer then raise exception 'Alert choices changed on another device. Reload saved choices before saving.';end if;
  insert into private.tournament_alert_preferences(team_id,user_id,countdown_minutes,readiness,changes)
  values(tid,uid,minutes,(p_data->>'readiness')::boolean,(p_data->>'changes')::boolean)
  on conflict(team_id,user_id) do update set countdown_minutes=excluded.countdown_minutes,readiness=excluded.readiness,changes=excluded.changes,revision=private.tournament_alert_preferences.revision+1,updated_at=now(),next_check_at=now();
  -- Choices can only narrow pending work. A future delivery stage must recheck again.
  delete from private.tournament_alert_drafts where team_id=tid and user_id=uid;
 end if;
 select * into pref from private.tournament_alert_preferences where team_id=tid and user_id=uid;
 return jsonb_build_object('countdown_minutes',coalesce(pref.countdown_minutes,'{}'::int[]),'readiness',coalesce(pref.readiness,false),'changes',coalesce(pref.changes,false),'revision',coalesce(pref.revision,0),'delivery_active',false);
end;
$$;
revoke all on function private.tournament_alert_preferences_request(text,jsonb) from public,anon,authenticated;
grant execute on function private.tournament_alert_preferences_request(text,jsonb) to authenticated;
create function public.tournament_alert_preferences(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.tournament_alert_preferences_request(p_action,p_data);$$;
revoke all on function public.tournament_alert_preferences(text,jsonb) from public,anon,authenticated;
grant execute on function public.tournament_alert_preferences(text,jsonb) to authenticated;

-- Explicit recipient authorization: no JWT impersonation in the background worker.
-- Staff roles match public.is_team_staff; guardian access requires this exact team.
create function private.tournament_alert_viewer_level(t uuid,a uuid,u uuid) returns text
language sql stable set search_path='' as $$
 select case
 when u is null or exists(select 1 from private.team_logins where user_id=u) then null
 when not exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where r.athlete_id=a and r.active and s.active and s.team_id=t) then null
 when exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=u and m.active and m.notifications_paused) then null
 when exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=u and m.active and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and coalesce((m.permissions->>'team_admin')::boolean,false))))
  or exists(select 1 from public.teams tm join public.organization_memberships o on o.organization_id=tm.organization_id where tm.id=t and o.user_id=u and o.role='organization_admin') then 'full'
 when exists(select 1 from public.athlete_guardians g join public.team_memberships m on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id and m.team_id=t and m.role='parent_guardian' and m.active where g.athlete_id=a and g.guardian_user_id=u) then 'full'
 when exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=u and m.athlete_id=a and m.role='athlete' and m.active) then coalesce((select level from private.tournament_visibility where athlete_id=a),'upcoming')
 else null end;
$$;
revoke all on function private.tournament_alert_viewer_level(uuid,uuid,uuid) from public,anon,authenticated;

-- Private staging function for a future database cron job. NOT scheduled in this release.
-- All state and draft writes commit together; row locks serialize concurrent workers.
-- Drafts are never delivery authorization and have no public read API.
create function private.prepare_tournament_alert_drafts(p_now timestamptz default now(),p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 pref private.tournament_alert_preferences%rowtype;s private.tournament_alert_state%rowtype;
 b record;old_exists boolean;fresh boolean;minutes numeric;threshold integer;n integer;
 seen_minutes integer[];seen_statuses text[];events jsonb;event jsonb;base jsonb;
 processed integer=0;prepared integer=0;inserted integer;
begin
 if p_now is null or p_limit is null or p_limit not between 1 and 1000 then raise exception 'Invalid preparation batch';end if;
 delete from private.tournament_alert_drafts where expires_at<=p_now;
 for pref in select * from private.tournament_alert_preferences where next_check_at<=p_now order by next_check_at,team_id,user_id limit p_limit for update skip locked loop
  processed:=processed+1;
  -- Revalidate existing drafts without exposing their content to the client.
  delete from private.tournament_alert_drafts d where d.team_id=pref.team_id and d.user_id=pref.user_id and (
   private.tournament_alert_viewer_level(d.team_id,d.athlete_id,d.user_id) is null
   or (private.tournament_alert_viewer_level(d.team_id,d.athlete_id,d.user_id)='mat_only' and d.kind<>'assignment')
   or (d.kind='readiness' and not pref.readiness) or (d.kind in ('assignment','reschedule') and not pref.changes)
   or (d.kind='countdown' and not ((d.payload->>'threshold_minutes')::int=any(pref.countdown_minutes)))
   or d.bout_id is distinct from (select x.id from private.tournament_bouts x join private.tournament_entries en on en.id=x.entry_id
    where x.workspace_id=(select workspace_id from private.tournament_bouts where id=d.bout_id) and en.athlete_id=d.athlete_id and x.status in ('queued','in_hole','on_deck','up_next','on_mat')
    order by case x.status when 'on_mat' then 0 when 'up_next' then 1 when 'on_deck' then 2 when 'in_hole' then 3 else 4 end,x.queue_order,x.estimated_start nulls last,x.id limit 1)
   or not exists(select 1 from private.tournament_bouts x join private.tournament_workspaces w on w.id=x.workspace_id join public.team_events e on e.id=w.event_id join public.seasons se on se.id=e.season_id
    where x.id=d.bout_id and x.revision=d.source_revision and x.status in ('queued','in_hole','on_deck','up_next','on_mat') and x.updated_at>=p_now-interval '10 minutes' and x.updated_at<=p_now+interval '1 minute' and se.active and se.team_id=d.team_id and e.team_id=d.team_id and e.event_type='tournament')
  );
  for b in
   select ranked.* from (
    select x.*,en.athlete_id,private.tournament_alert_viewer_level(w.team_id,en.athlete_id,pref.user_id) viewer_level,
     row_number() over(partition by w.id,en.athlete_id order by case x.status when 'on_mat' then 0 when 'up_next' then 1 when 'on_deck' then 2 when 'in_hole' then 3 else 4 end,x.queue_order,x.estimated_start nulls last,x.id) next_rank
    from private.tournament_bouts x join private.tournament_entries en on en.id=x.entry_id join private.tournament_workspaces w on w.id=x.workspace_id
     join public.team_events e on e.id=w.event_id join public.seasons se on se.id=e.season_id
    where w.team_id=pref.team_id and e.team_id=pref.team_id and se.team_id=pref.team_id and se.active and e.event_type='tournament' and x.status in ('queued','in_hole','on_deck','up_next','on_mat')
   ) ranked where ranked.next_rank=1 and ranked.viewer_level is not null
  loop
   select * into s from private.tournament_alert_state where team_id=pref.team_id and user_id=pref.user_id and bout_id=b.id;
   old_exists:=found;
   if old_exists and (b.revision<s.revision or b.updated_at<s.updated_at) then continue;end if;
   seen_minutes:=coalesce(s.seen_minutes,'{}');seen_statuses:=coalesce(s.seen_statuses,'{}');events:='[]';
   base:=jsonb_build_object('bout_number',b.bout_number,'mat',b.mat);
   fresh:=b.updated_at>=p_now-interval '10 minutes' and b.updated_at<=p_now+interval '1 minute';
   if fresh then
    if old_exists and b.mat<>s.mat and pref.changes then events:=events||jsonb_build_array(jsonb_build_object('key','mat:'||b.revision||':'||extract(epoch from b.updated_at),'kind','assignment','payload',base));end if;
    if b.viewer_level<>'mat_only' then
     if b.status in ('in_hole','on_deck','up_next','on_mat') and not(b.status=any(seen_statuses)) then
      seen_statuses:=array_append(seen_statuses,b.status);
      if pref.readiness then events:=events||jsonb_build_array(jsonb_build_object('key','status:'||b.status,'kind','readiness','payload',base||jsonb_build_object('status',b.status)));end if;
     end if;
     if old_exists and b.estimated_start is not null and s.estimated_start is not null and abs(extract(epoch from b.estimated_start-s.estimated_start))>=120 and pref.changes then
      events:=events||jsonb_build_array(jsonb_build_object('key','reschedule:'||b.revision||':'||extract(epoch from b.updated_at),'kind','reschedule','payload',base||jsonb_build_object('estimated_start',b.estimated_start)));
     end if;
     minutes:=extract(epoch from b.estimated_start-p_now)/60;
     if b.status<>'on_mat' and minutes>=0 then
      select min(t) into threshold from unnest(pref.countdown_minutes) t where minutes<=t;
      if threshold is not null and not(threshold=any(seen_minutes)) then events:=events||jsonb_build_array(jsonb_build_object('key','minutes:'||threshold,'kind','countdown','payload',base||jsonb_build_object('threshold_minutes',threshold,'estimated_start',b.estimated_start)));end if;
      foreach n in array array[5,10,15,30,60] loop
       if n>=minutes and not(n=any(seen_minutes)) then seen_minutes:=array_append(seen_minutes,n);end if;
      end loop;
     end if;
    end if;
   end if;
   insert into private.tournament_alert_state(team_id,user_id,bout_id,seen_minutes,seen_statuses,revision,updated_at,mat,estimated_start)
    values(pref.team_id,pref.user_id,b.id,seen_minutes,seen_statuses,b.revision,b.updated_at,b.mat,case when b.viewer_level='mat_only' then null else b.estimated_start end)
    on conflict(team_id,user_id,bout_id) do update set seen_minutes=excluded.seen_minutes,seen_statuses=excluded.seen_statuses,revision=excluded.revision,updated_at=excluded.updated_at,mat=excluded.mat,estimated_start=excluded.estimated_start;
   for event in select value from jsonb_array_elements(events) loop
    insert into private.tournament_alert_drafts(team_id,user_id,bout_id,athlete_id,event_key,kind,source_revision,payload,created_at,expires_at)
    values(pref.team_id,pref.user_id,b.id,b.athlete_id,event->>'key',event->>'kind',b.revision,event->'payload',p_now,case when event->>'kind'='countdown' then least(p_now+interval '2 minutes',b.estimated_start) else p_now+interval '2 minutes' end) on conflict(team_id,user_id,bout_id,event_key) do nothing;
    get diagnostics inserted=row_count;prepared:=prepared+inserted;
   end loop;
  end loop;
  update private.tournament_alert_preferences set next_check_at=p_now+interval '1 minute' where team_id=pref.team_id and user_id=pref.user_id;
 end loop;
 return jsonb_build_object('processed',processed,'prepared',prepared,'delivery_active',false);
end;
$$;
revoke all on function private.prepare_tournament_alert_drafts(timestamptz,integer) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
