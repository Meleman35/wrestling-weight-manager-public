-- 0.20.40: saved accomplishments, replacement goals and parent-approved profile projection.
create table private.athlete_goal_accomplishments (
 id uuid primary key default gen_random_uuid(),team_id uuid not null references public.teams(id) on delete cascade,
 athlete_id uuid not null references public.athletes(id) on delete cascade,goal_key text not null,
 goal_text text not null check(length(trim(goal_text)) between 1 and 600),category text not null,
 completed_at timestamptz,completed_by uuid references public.profiles(id) on delete set null,
 recorded_at timestamptz not null default now(),retracted_at timestamptz
);
create index athlete_goal_accomplishments_owner on private.athlete_goal_accomplishments(team_id,athlete_id,recorded_at desc) where retracted_at is null;
create table private.athlete_goal_profile_sharing (
 team_id uuid not null references public.teams(id) on delete cascade,athlete_id uuid not null references public.athletes(id) on delete cascade,
 enabled boolean not null default false,approved_by uuid references public.profiles(id) on delete set null,
 revision int not null default 1,updated_at timestamptz not null default now(),primary key(team_id,athlete_id)
);
alter table private.athlete_goal_accomplishments enable row level security;
alter table private.athlete_goal_profile_sharing enable row level security;
revoke all on private.athlete_goal_accomplishments,private.athlete_goal_profile_sharing from public,anon,authenticated;

-- Only a parent-approved, current template projection enters a shared profile.
-- Team/family access remains independent of this opt-in. No archived/history text
-- or private athlete details are included in this broader projection.
create function private.goals040_profile(pid uuid) returns jsonb language sql stable set search_path='' as $$
 select coalesce((select jsonb_agg(jsonb_build_object('team',t.name,'goals',q.goals) order by t.name,t.id,a.id)
 from private.wrestling_profiles p join public.athletes a on a.profile_id=p.athlete_profile_id
 join private.athlete_goal_profile_sharing sh on sh.athlete_id=a.id and sh.enabled
 join public.teams t on t.id=sh.team_id
 join private.team_goal_settings cfg on cfg.team_id=t.id and cfg.enabled
 join private.athlete_team_goals g on g.team_id=t.id and g.athlete_id=a.id
 cross join lateral (select coalesce(jsonb_agg(jsonb_build_object('category',c->>'label','text',e.value->>'text','complete',e.value->'complete') order by ord,split_part(e.key,':',2)::int),'[]'::jsonb) goals
  from jsonb_array_elements(cfg.categories) with ordinality cc(c,ord) cross join lateral jsonb_each(g.entries) e
  where split_part(e.key,':',1)=c->>'id' and split_part(e.key,':',2) ~ '^[0-9]+$' and split_part(e.key,':',2)::int between 1 and (c->>'count')::int and length(trim(coalesce(e.value->>'text','')))>0) q
 where p.id=pid and p.discoverable and private.wrestling_profile_visible(pid)
 and auth.uid() is not null and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and exists(select 1 from public.roster_memberships rm join public.seasons ss on ss.id=rm.season_id where rm.athlete_id=a.id and rm.active and ss.active and ss.team_id=t.id)
 and exists(select 1 from public.athlete_guardians ag join public.team_memberships tm on tm.user_id=ag.guardian_user_id and tm.athlete_id=ag.athlete_id and tm.role='parent_guardian' and tm.active where ag.athlete_id=a.id and ag.guardian_user_id=sh.approved_by)
 and not exists(select 1 from private.team_logins where user_id=sh.approved_by)
 and jsonb_array_length(q.goals)>0),'[]'::jsonb);
$$;
revoke all on function private.goals040_profile(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.team_goals_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 uid uuid=auth.uid(); tid uuid; aid uuid; cfg private.team_goal_settings%rowtype;
 g private.athlete_team_goals%rowtype; c jsonb; e jsonb; item record; k text;
 ids text[]='{}'; keys text[]='{}'; n integer; editable boolean; result jsonb;
 active_entries jsonb='{}'; archived jsonb='{}'; normalized jsonb='{}'; previous jsonb; medal uuid; completed timestamptz; share private.athlete_goal_profile_sharing%rowtype;
 defaults jsonb='[{"id":"academic","label":"Academic","count":5,"prompt":""},{"id":"wrestling","label":"Wrestling","count":5,"prompt":""}]';
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal account required';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>65536 then raise exception 'Invalid goal request';end if;
 if p_action='profile' then
  -- Resolve only goal-authorized teams, independent of public profile discovery.
  select coalesce(jsonb_agg(jsonb_build_object('team_id',q.team_id,'team_name',q.team_name,'athlete_id',q.athlete_id,'name',q.name) order by q.team_name),'[]') into result
  from (select distinct t.id team_id,t.name team_name,a.id athlete_id,a.first_name||' '||a.last_name name
    from private.wrestling_profiles p join public.athletes a on a.profile_id=p.athlete_profile_id
    join public.roster_memberships r on r.athlete_id=a.id join public.seasons s on s.id=r.season_id join public.teams t on t.id=s.team_id
    join private.team_goal_settings gs on gs.team_id=t.id and gs.enabled
    where p.id=(p_data->>'profile_id')::uuid and r.active and s.active and private.team_goal_access(t.id,a.id)) q;
  return result;
 end if;
 tid:=(p_data->>'team_id')::uuid;
 if tid is null or not private.team_goal_access(tid) then raise exception 'Active team or linked parent access required';end if;
 select * into cfg from private.team_goal_settings where team_id=tid;
 if not found then cfg.team_id:=tid;cfg.enabled:=false;cfg.instructions:='';cfg.categories:=defaults;cfg.revision:=0;end if;
 if p_action='settings_save' then
  if not public.is_team_staff(tid) then raise exception 'Coach or team administrator required';end if;
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'categories') is distinct from 'array' or jsonb_array_length(p_data->'categories') not between 1 and 6 then raise exception 'Choose one to six goal categories';end if;
  if jsonb_typeof(p_data->'instructions') is distinct from 'string' or length(p_data->>'instructions')>1200 then raise exception 'Instructions can contain up to 1200 characters';end if;
  result:='[]';
  for c in select value from jsonb_array_elements(p_data->'categories') loop
   if jsonb_typeof(c)<>'object' or coalesce(c->>'id','') !~ '^[a-z][a-z0-9_-]{0,49}$' or (c->>'id')=any(ids)
     or jsonb_typeof(c->'label') is distinct from 'string' or length(trim(c->>'label')) not between 1 and 50
     or jsonb_typeof(c->'count') is distinct from 'number' or coalesce(c->>'count','') !~ '^(10|[1-9])$'
     or jsonb_typeof(c->'prompt') is distinct from 'string' or length(c->>'prompt')>240 then raise exception 'Each category needs a unique key, a name and 1–10 goals';end if;
   ids:=array_append(ids,c->>'id');
   result:=result||jsonb_build_array(jsonb_build_object('id',c->>'id','label',trim(c->>'label'),'count',(c->>'count')::int,'prompt',trim(c->>'prompt')));
  end loop;
  -- Team row serializes first creation as well as concurrent settings edits.
  perform 1 from public.teams where id=tid for update;
  select * into cfg from private.team_goal_settings where team_id=tid for update;
  if coalesce(cfg.revision,0) is distinct from (p_data->>'revision')::integer then raise exception 'Goal settings changed. Reload before saving.';end if;
  insert into private.team_goal_settings(team_id,enabled,instructions,categories) values(tid,(p_data->>'enabled')::boolean,trim(p_data->>'instructions'),result)
  on conflict(team_id) do update set enabled=excluded.enabled,instructions=excluded.instructions,categories=excluded.categories,revision=private.team_goal_settings.revision+1,updated_at=now();
  return private.team_goals_request('context',jsonb_build_object('team_id',tid));
 end if;
 if p_action='context' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'editable',private.team_goal_access(tid,q.id,true)) order by q.name),'[]') into result
  from (select distinct a.id,a.first_name||' '||a.last_name name from public.athletes a join public.roster_memberships r on r.athlete_id=a.id join public.seasons s on s.id=r.season_id where cfg.enabled and r.active and s.active and s.team_id=tid and private.team_goal_access(tid,a.id)) q;
  return jsonb_build_object('team_id',tid,'team_name',(select name from public.teams where id=tid),'enabled',cfg.enabled,'categories',cfg.categories,'instructions',cfg.instructions,'revision',cfg.revision,'can_configure',public.is_team_staff(tid),'athletes',result);
 end if;
 aid:=(p_data->>'athlete_id')::uuid;
 if aid is null or not private.team_goal_access(tid,aid) then raise exception 'This athlete is not available on your active team';end if;
 select * into share from private.athlete_goal_profile_sharing where team_id=tid and athlete_id=aid;
 if p_action='profile_sharing' then
  if not public.is_guardian_for_athlete(aid) then raise exception 'Only a linked parent or guardian can change goal profile sharing';end if;
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'Choose whether to share these goals';end if;
  perform 1 from public.teams where id=tid for update;
  select * into share from private.athlete_goal_profile_sharing where team_id=tid and athlete_id=aid for update;
  if coalesce(share.revision,0) is distinct from (p_data->>'revision')::int then raise exception 'Profile sharing changed. Reload before saving.';end if;
  insert into private.athlete_goal_profile_sharing(team_id,athlete_id,enabled,approved_by) values(tid,aid,(p_data->>'enabled')::boolean,uid)
  on conflict(team_id,athlete_id) do update set enabled=excluded.enabled,approved_by=uid,revision=private.athlete_goal_profile_sharing.revision+1,updated_at=now();
  return private.team_goals_request('view',jsonb_build_object('team_id',tid,'athlete_id',aid));
 end if;
 if not cfg.enabled then raise exception 'Team goals are switched off by the coach';end if;
 editable:=private.team_goal_access(tid,aid,true);
 if p_action in ('save','replace') then
  if not editable then raise exception 'Only this athlete or their linked parent can edit these goals';end if;
  -- Serializes writes and prevents a stale form from replacing newer goal settings.
  select * into cfg from private.team_goal_settings where team_id=tid for update;
  if not cfg.enabled or cfg.revision is distinct from (p_data->>'settings_revision')::integer then raise exception 'Goal settings changed. Reload before saving.';end if;
 end if;
 for c in select value from jsonb_array_elements(cfg.categories) loop
  for n in 1..(c->>'count')::integer loop keys:=array_append(keys,(c->>'id')||':'||n);end loop;
 end loop;
 select * into g from private.athlete_team_goals where team_id=tid and athlete_id=aid;
 if p_action in ('save','replace') then
  if coalesce(g.revision,0) is distinct from (p_data->>'revision')::integer then raise exception 'Goals changed on another device. Reload before saving.';end if;
  if jsonb_typeof(p_data->'entries') is distinct from 'object' then raise exception 'Invalid goals';end if;
  if p_action='replace' then
   k:=p_data->>'goal_key';
   if k is null or not k=any(keys) or coalesce(g.entries->k->>'complete','false')<>'true' or trim(coalesce(g.entries->k->>'text',''))='' then raise exception 'Complete and save this goal before setting a new one';end if;
   -- Preserve a completion made by an earlier app without inventing its date.
   if nullif(g.entries->k->>'achievement_id','') is null then
    insert into private.athlete_goal_accomplishments(team_id,athlete_id,goal_key,goal_text,category,completed_at,completed_by)
    values(tid,aid,k,g.entries->k->>'text',g.entries->k->>'label',null,null);
   end if;
   p_data:=jsonb_set(p_data,array['entries',k],jsonb_build_object('text','','complete',false));
  end if;
  if (select count(*) from jsonb_each(p_data->'entries'))<>cardinality(keys) then raise exception 'Fill the current goal slots or leave them blank';end if;
  for item in select * from jsonb_each(p_data->'entries') loop
   if not item.key=any(keys) then raise exception 'Unknown goal slot';end if;
   e:=item.value;
   if jsonb_typeof(e)<>'object' or jsonb_typeof(e->'text') is distinct from 'string' or length(e->>'text')>600 or jsonb_typeof(e->'complete') is distinct from 'boolean' then raise exception 'Each goal needs text (up to 600 characters) and a completion choice';end if;
   if (e->>'complete')::boolean and trim(e->>'text')='' then raise exception 'Write a goal before marking it complete';end if;
   select value into c from jsonb_array_elements(cfg.categories) where value->>'id'=split_part(item.key,':',1);
   previous:=coalesce(g.entries->item.key,'{}');medal:=null;completed:=null;
   if (e->>'complete')::boolean then
    if previous->>'complete'='true' and previous->>'text' is distinct from trim(e->>'text') then raise exception 'Use Set a new goal to replace an accomplished goal, or uncheck completion to correct it';end if;
    if previous->>'complete'='true' and nullif(previous->>'achievement_id','') is not null then
     medal:=(previous->>'achievement_id')::uuid;completed:=(previous->>'completed_at')::timestamptz;
    else
     completed:=case when previous->>'complete'='true' then null else now() end;
     insert into private.athlete_goal_accomplishments(team_id,athlete_id,goal_key,goal_text,category,completed_at,completed_by)
     values(tid,aid,item.key,trim(e->>'text'),c->>'label',completed,case when completed is null then null else uid end) returning id into medal;
    end if;
   elsif previous->>'complete'='true' and not (p_action='replace' and item.key=k) then
    update private.athlete_goal_accomplishments set retracted_at=now() where id=nullif(previous->>'achievement_id','')::uuid and team_id=tid and athlete_id=aid and retracted_at is null;
   end if;
   normalized:=normalized||jsonb_build_object(item.key,jsonb_build_object('text',trim(e->>'text'),'complete',(e->>'complete')::boolean,'label',c->>'label','slot',split_part(item.key,':',2)::integer,'achievement_id',medal,'completed_at',completed));
  end loop;
  insert into private.athlete_team_goals(team_id,athlete_id,entries) values(tid,aid,normalized)
  on conflict(team_id,athlete_id) do update set entries=private.athlete_team_goals.entries||excluded.entries,revision=private.athlete_team_goals.revision+1,updated_at=now();
  return private.team_goals_request('view',jsonb_build_object('team_id',tid,'athlete_id',aid));
 end if;
 if p_action<>'view' then raise exception 'Unknown goal action';end if;
 for item in select * from jsonb_each(coalesce(g.entries,'{}')) loop
  if item.key=any(keys) then active_entries:=active_entries||jsonb_build_object(item.key,item.value);
  elsif editable and trim(item.value->>'text')<>'' then archived:=archived||jsonb_build_object(item.key,item.value);end if;
 end loop;
 return jsonb_build_object('team_id',tid,'team_name',(select name from public.teams where id=tid),'athlete_id',aid,'name',(select first_name||' '||last_name from public.athletes where id=aid),'categories',cfg.categories,'instructions',cfg.instructions,'settings_revision',cfg.revision,'revision',coalesce(g.revision,0),'entries',active_entries,'archived',archived,'editable',editable,
 'profile_sharing',jsonb_build_object('enabled',coalesce(share.enabled,false),'revision',coalesce(share.revision,0),'can_change',public.is_guardian_for_athlete(aid)),
 'accomplishments',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'text',h.goal_text,'category',h.category,'completed_at',h.completed_at) order by h.recorded_at desc,h.id) from private.athlete_goal_accomplishments h where h.team_id=tid and h.athlete_id=aid and h.retracted_at is null and (editable or h.goal_key=any(keys))),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION private.wrestling_profiles_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); pid uuid; sid uuid; tid uuid; p private.wrestling_profiles%rowtype; d jsonb; sh jsonb; r record; result jsonb; member uuid; pos integer=0;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal account required'; end if;
 if octet_length(p_data::text)>30000 then raise exception 'Profile is too large'; end if;
 if p_action like 'spouse_%' then return private.wrestling_spouse_request(p_action,p_data);end if;
 if p_action='mine' then
 -- A minor athlete login uses its athlete profile, never a second adult identity.
 if not exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=uid and m.role='athlete' and m.active and (coalesce((select ai.birth_date from public.athlete_private_identity ai where ai.athlete_id=a.id),a.birth_date) is null or coalesce((select ai.birth_date from public.athlete_private_identity ai where ai.athlete_id=a.id),a.birth_date)>current_date-interval '18 years')) then
 insert into private.wrestling_profiles(user_id,name) select id,coalesce(nullif(display_name,''),'My profile') from public.profiles where id=uid on conflict(user_id) do nothing;
 end if;
 for r in select distinct on(a.profile_id) a.profile_id,a.first_name,a.last_name from public.athletes a where a.profile_id is not null and (public.is_guardian_for_athlete(a.id) or exists(select 1 from public.team_memberships m where m.athlete_id=a.id and m.user_id=uid and m.role='athlete' and m.active)) order by a.profile_id,a.created_at loop
 insert into private.wrestling_profiles(athlete_profile_id,name,details) values(r.profile_id,left(r.first_name||' '||r.last_name,120),'{"roles":"Athlete"}') on conflict(athlete_profile_id) do nothing;
 end loop;
 select coalesce(jsonb_agg(private.wrestling_profile_card(id) order by name),'[]') into result from private.wrestling_profiles where private.wrestling_profile_manager(id) or private.wrestling_profile_self(id);return result;
 end if;

 if p_action='browse' then
 select jsonb_build_object('rows',coalesce(jsonb_agg(card order by name,id) filter(where n<=30),'[]'::jsonb),'more',count(*)>30) into result
 from (select q.id,q.name,private.wrestling_profile_card(q.id,true) card,row_number() over(order by q.name,q.id)-greatest(0,least(10000,coalesce((p_data->>'offset')::int,0))) n
 from private.wrestling_profiles q where q.discoverable and private.wrestling_profile_visible(q.id)
 order by q.name,q.id limit 31 offset greatest(0,least(10000,coalesce((p_data->>'offset')::int,0)))) listing;
 return result;
 end if;

 if p_action='search' then
 if length(trim(p_data->>'query'))<2 then return '[]'; end if;
 select coalesce(jsonb_agg(private.wrestling_profile_card(id)),'[]') into result from (select id from private.wrestling_profiles where discoverable and name ilike '%'||left(p_data->>'query',80)||'%' and private.wrestling_profile_visible(id) order by name limit 30) s;return result;
 end if;

 if p_action='affiliation' then
 if length(trim(coalesce(p_data->>'name',''))) not between 2 and 160 then return '{"rows":[],"more":false}';end if;
 select jsonb_build_object('rows',coalesce(jsonb_agg(card order by name,id) filter(where rn<=greatest(0,least(10000,coalesce((p_data->>'offset')::integer,0)))+30),'[]'::jsonb),'more',count(*)>30) into result
 from (
 select q.id,q.name,private.wrestling_profile_card(q.id,true) card,row_number() over(order by q.name,q.id) rn
 from private.wrestling_profiles q
 where q.discoverable and q.sharing->>'affiliation'='true' and private.wrestling_profile_visible(q.id)
 and exists(select 1 from regexp_split_to_table(coalesce(q.details->>'affiliation',''),'[,;]') part where lower(trim(part))=lower(trim(p_data->>'name')))
 order by q.name,q.id limit 31 offset greatest(0,least(10000,coalesce((p_data->>'offset')::integer,0)))
 ) listing;
 return result;
 end if;

 pid:=nullif(p_data->>'id','')::uuid;
 if p_action='view' then
 result:=private.wrestling_profile_card(pid,coalesce((p_data->>'preview')::boolean,false));if result is null then raise exception 'Profile is private or unavailable';end if;
 select coalesce(jsonb_agg(private.wrestling_profile_card(c.member_id,true) order by c.position),'[]') into d from private.wrestling_corners c join private.wrestling_profiles m on m.id=c.member_id where c.profile_id=pid and private.wrestling_profile_teammates(pid,c.member_id) and m.discoverable and private.wrestling_profile_visible(c.member_id) and exists(select 1 from private.wrestling_follows f where f.source_id=pid and f.target_id=c.member_id and f.status='approved') and exists(select 1 from private.wrestling_follows f where f.target_id=pid and f.source_id=c.member_id and f.status='approved');
 select * into p from private.wrestling_profiles where id=pid;
 if coalesce((p_data->>'preview')::boolean,false) and not p.discoverable then
 return jsonb_build_object('id',pid,'discoverable',false,'unavailable',true,'details','{}'::jsonb,'corner','[]'::jsonb);
 end if;
 -- Parent family pins are returned only to their owner, never in the outside preview.
 if not coalesce((p_data->>'preview')::boolean,false) then
   select coalesce(jsonb_agg(private.wrestling_profile_card(c.member_id) order by c.position),'[]'::jsonb) into sh
   from private.wrestling_corners c join private.wrestling_profiles m on m.id=c.member_id
   where c.profile_id=pid and private.wrestling_profile_linked_child(pid,c.member_id);
   if p.user_id=uid and private.wrestling_profile_manager(pid) then result:=result||jsonb_build_object('family_corner',sh);end if;
   select parent.id into sid from private.wrestling_profiles parent
   where parent.user_id=uid and private.wrestling_profile_linked_child(parent.id,pid);
   if sid is not null then result:=result||jsonb_build_object('parent_connection',jsonb_build_object('profile_id',sid,'in_corner',exists(select 1 from private.wrestling_corners where profile_id=sid and member_id=pid)));end if;
 end if;
 return result||jsonb_build_object('shared_goals',private.goals040_profile(pid))||jsonb_build_object('corner',case when p.sharing->>'corner'='true' or (private.wrestling_profile_manager(pid) and not coalesce((p_data->>'preview')::boolean,false)) then d else '[]'::jsonb end);
 end if;
 if p_action='family_corner' then
 sid:=pid;tid:=nullif(p_data->>'target','')::uuid;
 if not private.wrestling_profile_linked_child(sid,tid) then raise exception 'An active linked parent/guardian is required';end if;
 if jsonb_typeof(p_data->'show') is distinct from 'boolean' then raise exception 'Choose whether to show this child';end if;
 perform 1 from private.wrestling_profiles where id=sid for update;
 if (p_data->>'show')::boolean then
   if not exists(select 1 from private.wrestling_corners where profile_id=sid and member_id=tid) then
     select n into pos from generate_series(1,8) n where not exists(select 1 from private.wrestling_corners where profile_id=sid and position=n) order by n limit 1;
     if pos is null then raise exception 'My Corner is full. Remove someone before adding another person (up to eight).';end if;
     insert into private.wrestling_corners(profile_id,member_id,position) values(sid,tid,pos);
   end if;
 else delete from private.wrestling_corners where profile_id=sid and member_id=tid;
 end if;
 return jsonb_build_object('ok',true,'in_corner',(p_data->>'show')::boolean);
 end if;
 if p_action='save' then
 if not private.wrestling_profile_manager(pid) then raise exception 'Linked parent/guardian or adult profile owner required';end if;
 select * into p from private.wrestling_profiles where id=pid for update;
 d:=coalesce(p_data->'details','{}');sh:=coalesce(p_data->'sharing','{}');
 if jsonb_typeof(d)<>'object' or jsonb_typeof(sh)<>'object' then raise exception 'Invalid profile';end if;
 if length(trim(p_data->>'name')) not between 1 and 120 then raise exception 'Name required (120 characters maximum)';end if;
 if length(coalesce(d->>'bio',''))>1200 or length(coalesce(d->>'roles',''))>160 or length(coalesce(d->>'affiliation',''))>160 then raise exception 'Please shorten the profile text';end if;
 if coalesce(d->>'music_url','')<>'' and d->>'music_url' !~ '^https://(music[.]apple[.]com|open[.]spotify[.]com)/[^[:space:]]+$' then raise exception 'Use an Apple Music or Spotify HTTPS link';end if;
 if coalesce(d->>'music_url','')<>'' and (p_data->>'music_approved') is distinct from 'true' then raise exception 'Confirm the song is clean and approved';end if;
 if d ? 'results' and (jsonb_typeof(d->'results')<>'array' or jsonb_array_length(d->'results')>30) then raise exception 'Use up to 30 tournament results';end if;
 if p.athlete_profile_id is not null then d:=d||'{"roles":"Athlete"}';end if;
 -- Only explicit, allow-listed fields enter this shareable record.
 select coalesce(jsonb_object_agg(key,value),'{}') into d from jsonb_each(d) where key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url']);
 select coalesce(jsonb_object_agg(key,value),'{}') into sh from jsonb_each(sh) where value in ('true'::jsonb,'false'::jsonb) and key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url','photo','corner','follow','outgoing_follow']);
 update private.wrestling_profiles set name=trim(p_data->>'name'),details=d,sharing=sh,discoverable=coalesce((p_data->>'discoverable')::boolean,false),updated_at=now() where id=pid;
 return private.wrestling_profile_card(pid);
 end if;
 if p_action='photo' then raise exception 'Refresh Wrestling Manager before changing your profile picture';end if;
 if p_action in ('follow','unfollow','links','corner') then
 sid:=pid;
 if not private.wrestling_profile_manager(sid) and not(private.wrestling_profile_self(sid) and exists(select 1 from private.wrestling_profiles where id=sid and sharing->>'outgoing_follow'='true')) then raise exception 'Parent approval is required to follow or manage My Corner';end if;
 if p_action='links' then
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'status',q.status,'family',q.family,'profile',q.card,
 'can_corner',q.family or (q.status='approved' and private.wrestling_profile_teammates(sid,q.id) and exists(select 1 from private.wrestling_follows f where f.source_id=q.id and f.target_id=sid and f.status='approved')),
 'in_corner',c.member_id is not null) order by c.position nulls last,q.family desc,q.name,q.id),'[]'::jsonb) into result
 from (
 select child.id,'approved'::text status,true family,child.name,private.wrestling_profile_card(child.id) card
 from private.wrestling_profiles child where private.wrestling_profile_linked_child(sid,child.id)
 union all
 select f.target_id,f.status,false,m.name,private.wrestling_profile_card(f.target_id,true)
 from private.wrestling_follows f join private.wrestling_profiles m on m.id=f.target_id
 where f.source_id=sid and not private.wrestling_profile_linked_child(sid,f.target_id)
 ) q left join private.wrestling_corners c on c.profile_id=sid and c.member_id=q.id;
 return result;
 end if;
 tid:=nullif(p_data->>'target','')::uuid;
 if p_action='unfollow' and private.wrestling_profile_linked_child(sid,tid) then raise exception 'Your linked child is followed automatically. Turn off Show in My Corner to hide their tile.';end if;
 if p_action='unfollow' then delete from private.wrestling_follows where source_id=sid and target_id=tid and status<>'blocked';return '{"ok":true}';end if;
 if p_action='follow' then
 if private.wrestling_profile_linked_child(sid,tid) then return '{"ok":true,"automatic":true}';end if;
 if not private.wrestling_profile_visible(tid) or not exists(select 1 from private.wrestling_profiles where id=tid and discoverable and sharing->>'follow'='true') then raise exception 'This profile is not accepting followers';end if;
 if exists(select 1 from private.wrestling_follows where ((source_id=sid and target_id=tid) or (source_id=tid and target_id=sid)) and status in ('blocked','denied')) then raise exception 'This connection is unavailable';end if;
 insert into private.wrestling_follows(source_id,target_id,status) values(sid,tid,'pending') on conflict(source_id,target_id) do nothing;return '{"ok":true}';
 end if;
 if p_action='corner' then
 if jsonb_typeof(p_data->'members') is distinct from 'array' then raise exception 'Choose your corner members';end if;
 if jsonb_array_length(p_data->'members')>8 then raise exception 'Choose up to eight people for My Corner';end if;
 perform 1 from private.wrestling_profiles where id=sid for update;
 delete from private.wrestling_corners where profile_id=sid;
 for member in select value::uuid from jsonb_array_elements_text(p_data->'members') loop
 if not private.wrestling_profile_linked_child(sid,member) and (not private.wrestling_profile_teammates(sid,member) or not exists(select 1 from private.wrestling_follows where source_id=sid and target_id=member and status='approved') or not exists(select 1 from private.wrestling_follows where source_id=member and target_id=sid and status='approved')) then raise exception 'Choose a linked child or mutual approved teammate for My Corner';end if;
 pos:=pos+1;insert into private.wrestling_corners values(sid,member,pos);
 end loop;return '{"ok":true}';
 end if;
 end if;
 if p_action='requests' then
 if not private.wrestling_profile_manager(pid) then raise exception 'Parent/owner permission required';end if;
 select coalesce(jsonb_agg(jsonb_build_object('source',f.source_id,'name',s.name,'status',f.status) order by f.created_at desc),'[]') into result from private.wrestling_follows f join private.wrestling_profiles s on s.id=f.source_id where f.target_id=pid;return result;
 end if;
 if p_action='review' then
 if not private.wrestling_profile_manager(pid) then raise exception 'Parent/owner permission required';end if;
 if p_data->>'status' not in ('approved','denied','blocked') then raise exception 'Invalid decision';end if;
 update private.wrestling_follows set status=p_data->>'status' where source_id=(p_data->>'source')::uuid and target_id=pid;
 return '{"ok":true}';
 end if;
 raise exception 'Unknown profile action';
end $function$
;
