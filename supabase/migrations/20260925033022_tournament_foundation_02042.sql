-- Manual tournament workspaces. Provider data is not connected in this release.
-- Raw rows are private; a fresh, viewer-specific projection is the only read API.
begin;
create table private.tournament_workspaces (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null unique references public.team_events(id) on delete cascade,
 team_id uuid not null references public.teams(id) on delete cascade,
 source text not null default 'manual' check(source='manual'),
 timezone text not null default 'America/Denver',
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now()
);
create index tournament_workspace_team_idx on private.tournament_workspaces(team_id);
create table private.tournament_entries (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references private.tournament_workspaces(id) on delete cascade,
 athlete_id uuid not null references public.athletes(id) on delete cascade,
 division text not null check(length(division) between 1 and 80),
 weight_class text not null check(length(weight_class) between 1 and 40),
 unique(workspace_id,athlete_id,division,weight_class),unique(id,workspace_id)
);
create index tournament_entry_athlete_idx on private.tournament_entries(athlete_id);
create table private.tournament_bouts (
 id uuid primary key,
 workspace_id uuid not null references private.tournament_workspaces(id) on delete cascade,
 entry_id uuid not null,
 bout_number text not null check(length(bout_number) between 1 and 40),
 mat text not null default '' check(length(mat)<=40),
 opponent text not null default '' check(length(opponent)<=160),
 status text not null default 'queued' check(status in ('queued','in_hole','on_deck','up_next','on_mat','complete','bye','scratched','forfeit')),
 queue_order integer not null default 0 check(queue_order between 0 and 1000000),
 estimated_start timestamptz,
 result text not null default '' check(length(result)<=240),
 bracket_url text not null default '' check(bracket_url='' or (bracket_url ~ '^https://[^[:space:]]+$' and length(bracket_url)<=1000)),
 revision integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id) on delete set null,
 foreign key(entry_id,workspace_id) references private.tournament_entries(id,workspace_id) on delete cascade
);
create index tournament_bout_entry_idx on private.tournament_bouts(entry_id,workspace_id);
create index tournament_bout_workspace_idx on private.tournament_bouts(workspace_id,queue_order,id);
-- Visibility follows an athlete between their teams, so a second team cannot weaken it.
create table private.tournament_visibility (
 athlete_id uuid primary key references public.athletes(id) on delete cascade,
 level text not null check(level in ('full','upcoming','mat_only')),
 revision integer not null default 1,
 updated_by uuid references public.profiles(id) on delete set null,
 updated_at timestamptz not null default now()
);
alter table private.tournament_workspaces enable row level security;
alter table private.tournament_entries enable row level security;
alter table private.tournament_bouts enable row level security;
alter table private.tournament_visibility enable row level security;
revoke all on private.tournament_workspaces,private.tournament_entries,private.tournament_bouts,private.tournament_visibility from public,anon,authenticated;

create function private.tournament_guardian(t uuid,a uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.athlete_guardians g join public.team_memberships m on m.user_id=g.guardian_user_id and m.athlete_id=g.athlete_id and m.team_id=t and m.role='parent_guardian' and m.active where g.athlete_id=a and g.guardian_user_id=auth.uid());
$$;
create function private.tournament_athlete_access(t uuid,a uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where r.athlete_id=a and r.active and s.active and s.team_id=t)
 and (public.is_team_staff(t) or private.tournament_guardian(t,a) or exists(select 1 from public.team_memberships m where m.team_id=t and m.athlete_id=a and m.user_id=auth.uid() and m.role='athlete' and m.active));
$$;
revoke all on function private.tournament_guardian(uuid,uuid),private.tournament_athlete_access(uuid,uuid) from public,anon,authenticated;

create function private.tournament_request(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid=auth.uid(); tid uuid; eid uuid; aid uuid; bid uuid; entryid uuid; can_manage boolean;
 ws private.tournament_workspaces%rowtype; existing_bout private.tournament_bouts%rowtype; visibility_row private.tournament_visibility%rowtype;
 result jsonb; people jsonb; events jsonb; rows jsonb; item record; level text; alevel text; ev public.team_events%rowtype;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal account required';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16384 then raise exception 'Invalid tournament request';end if;
 tid:=(p_data->>'team_id')::uuid;
 can_manage:=public.is_team_staff(tid);
 if tid is null or not(can_manage or exists(select 1 from public.athletes a where private.tournament_athlete_access(tid,a.id))) then raise exception 'Active team or linked family access required';end if;
 if p_action='visibility' then
  aid:=(p_data->>'athlete_id')::uuid;
  if not private.tournament_athlete_access(tid,aid) or not private.tournament_guardian(tid,aid) then raise exception 'Only this athlete''s linked parent can change tournament visibility';end if;
  if coalesce(p_data->>'level','') not in ('full','upcoming','mat_only') then raise exception 'Choose a tournament visibility level';end if;
  perform 1 from public.athletes where id=aid for update;
  select * into visibility_row from private.tournament_visibility where athlete_id=aid;
  if coalesce(visibility_row.revision,0) is distinct from (p_data->>'revision')::int then raise exception 'Visibility changed. Reload before saving.';end if;
  insert into private.tournament_visibility(athlete_id,level,updated_by) values(aid,p_data->>'level',uid)
  on conflict(athlete_id) do update set level=excluded.level,revision=private.tournament_visibility.revision+1,updated_by=uid,updated_at=now();
  return private.tournament_request('context',jsonb_build_object('team_id',tid));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.first_name||' '||a.last_name,'visibility',coalesce(v.level,'upcoming'),'visibility_revision',coalesce(v.revision,0),'can_set_visibility',private.tournament_guardian(tid,a.id)) order by a.last_name,a.first_name,a.id),'[]') into people
 from public.athletes a left join private.tournament_visibility v on v.athlete_id=a.id where private.tournament_athlete_access(tid,a.id);
 if p_action='context' then
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,'starts_at',e.starts_at,'ready',ew.id is not null) order by e.starts_at desc,e.id),'[]') into events
  from public.team_events e left join private.tournament_workspaces ew on ew.event_id=e.id where e.team_id=tid and e.event_type='tournament' and exists(select 1 from public.seasons s where s.id=e.season_id and s.active and s.team_id=tid);
  return jsonb_build_object('can_manage',can_manage,'athletes',people,'events',events,'provider_connected',false);
 end if;
 eid:=(p_data->>'event_id')::uuid;
 select * into ev from public.team_events where id=eid and team_id=tid and event_type='tournament';
 if not found or not exists(select 1 from public.seasons s where s.id=ev.season_id and s.team_id=tid and s.active) then raise exception 'Tournament event is not on the active team season';end if;
 select * into ws from private.tournament_workspaces where event_id=eid and team_id=tid;
 if p_action='setup' then
  if not can_manage then raise exception 'Coach or team administrator required';end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_data->>'timezone') then raise exception 'Choose a valid event timezone';end if;
  insert into private.tournament_workspaces(event_id,team_id,timezone,created_by) values(eid,tid,p_data->>'timezone',uid) on conflict(event_id) do nothing;
  return private.tournament_request('board',jsonb_build_object('team_id',tid,'event_id',eid));
 end if;
 if p_action='save_bout' then
  if not can_manage or ws.id is null then raise exception 'Open a manual tournament workspace as a coach first';end if;
  aid:=(p_data->>'athlete_id')::uuid;bid:=(p_data->>'id')::uuid;
  if bid is null or not private.tournament_athlete_access(tid,aid) then raise exception 'Select an athlete on the active roster';end if;
  if length(trim(coalesce(p_data->>'division',''))) not between 1 and 80 or length(trim(coalesce(p_data->>'weight_class',''))) not between 1 and 40 or length(trim(coalesce(p_data->>'bout_number',''))) not between 1 and 40 then raise exception 'Division, weight class and bout number are required';end if;
  if coalesce(p_data->>'status','') not in ('queued','in_hole','on_deck','up_next','on_mat','complete','bye','scratched','forfeit') then raise exception 'Choose a valid bout status';end if;
  -- Serialize edits and duplicate retries; optimistic revision protects another device's save.
  perform 1 from private.tournament_workspaces where id=ws.id for update;
  select * into existing_bout from private.tournament_bouts where id=bid;
  if found and existing_bout.workspace_id<>ws.id then raise exception 'Bout belongs to another tournament';end if;
  if coalesce(existing_bout.revision,0) is distinct from (p_data->>'revision')::int then raise exception 'Bout changed. Reload before saving.';end if;
  insert into private.tournament_entries(workspace_id,athlete_id,division,weight_class) values(ws.id,aid,trim(p_data->>'division'),trim(p_data->>'weight_class'))
  on conflict(workspace_id,athlete_id,division,weight_class) do update set athlete_id=excluded.athlete_id returning id into entryid;
  insert into private.tournament_bouts(id,workspace_id,entry_id,bout_number,mat,opponent,status,queue_order,estimated_start,result,bracket_url,updated_by)
  values(bid,ws.id,entryid,trim(p_data->>'bout_number'),trim(coalesce(p_data->>'mat','')),trim(coalesce(p_data->>'opponent','')),p_data->>'status',coalesce((p_data->>'queue_order')::int,0),nullif(p_data->>'estimated_start','')::timestamptz,trim(coalesce(p_data->>'result','')),trim(coalesce(p_data->>'bracket_url','')),uid)
  on conflict(id) do update set entry_id=excluded.entry_id,bout_number=excluded.bout_number,mat=excluded.mat,opponent=excluded.opponent,status=excluded.status,queue_order=excluded.queue_order,estimated_start=excluded.estimated_start,result=excluded.result,bracket_url=excluded.bracket_url,revision=private.tournament_bouts.revision+1,updated_at=now(),updated_by=uid;
  return private.tournament_request('board',jsonb_build_object('team_id',tid,'event_id',eid));
 end if;
 if p_action<>'board' then raise exception 'Unknown tournament action';end if;
 rows:='[]';
 for item in
  select b.*,e.athlete_id,e.division,e.weight_class,a.first_name||' '||a.last_name athlete_name,
   coalesce(v.level,'upcoming') athlete_level,
   row_number() over(partition by e.athlete_id order by case b.status when 'on_mat' then 0 when 'up_next' then 1 when 'on_deck' then 2 when 'in_hole' then 3 when 'queued' then 4 else 5 end,b.queue_order,b.estimated_start nulls last,b.id) next_rank
  from private.tournament_bouts b join private.tournament_entries e on e.id=b.entry_id join public.athletes a on a.id=e.athlete_id left join private.tournament_visibility v on v.athlete_id=a.id
  where b.workspace_id=ws.id and private.tournament_athlete_access(tid,e.athlete_id)
  order by b.queue_order,b.estimated_start nulls last,b.id
 loop
  alevel:=item.athlete_level;
  level:=case when can_manage or private.tournament_guardian(tid,item.athlete_id) then 'full' else alevel end;
  if level<>'full' and (item.next_rank<>1 or item.status in ('complete','bye','scratched','forfeit')) then continue;end if;
  result:=jsonb_build_object('id',item.id,'athlete_id',item.athlete_id,'athlete_name',item.athlete_name,'mat',item.mat,'bout_number',item.bout_number,'visibility',level,'updated_at',item.updated_at,'stale',item.updated_at<now()-interval '10 minutes','source','manual');
  if level<>'mat_only' then result:=result||jsonb_build_object('division',item.division,'weight_class',item.weight_class,'status',item.status,'estimated_start',item.estimated_start,'queue_order',item.queue_order);end if;
  if level='full' then result:=result||jsonb_build_object('opponent',item.opponent,'result',item.result,'bracket_url',item.bracket_url);end if;
  if can_manage then result:=result||jsonb_build_object('revision',item.revision);end if;
  rows:=rows||jsonb_build_array(result);
 end loop;
 return jsonb_build_object('event_id',eid,'title',ev.title,'starts_at',ev.starts_at,'timezone',ws.timezone,'workspace_id',ws.id,'source','manual','can_manage',can_manage,'athletes',people,'bouts',rows,'provider_connected',false,'server_time',now());
end;
$$;
revoke all on function private.tournament_request(text,jsonb) from public,anon,authenticated;
grant execute on function private.tournament_request(text,jsonb) to authenticated;
create function public.tournament_request(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.tournament_request(p_action,p_data);$$;
revoke all on function public.tournament_request(text,jsonb) from public,anon,authenticated;
grant execute on function public.tournament_request(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
