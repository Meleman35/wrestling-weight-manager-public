CREATE OR REPLACE FUNCTION private.team_goal_access(t uuid, a uuid DEFAULT NULL::uuid, editing boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null
 and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and (a is null or exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where s.team_id=t and s.active and r.active and r.athlete_id=a))
 and case when editing then
   public.is_guardian_for_athlete(a) or exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=auth.uid() and m.active and m.role='athlete' and m.athlete_id=a)
 else
   public.is_team_staff(t)
   or exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=auth.uid() and m.active and m.role='manager' and m.permissions->>'staff_role'='team_leader')
   or exists(select 1 from public.team_memberships m join public.roster_memberships r on r.athlete_id=m.athlete_id join public.seasons s on s.id=r.season_id where m.team_id=t and m.user_id=auth.uid() and m.active and m.role='athlete' and r.active and s.active and s.team_id=t)
   or (a is not null and public.is_guardian_for_athlete(a))
   or (a is null and exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id where s.team_id=t and s.active and r.active and public.is_guardian_for_athlete(r.athlete_id)))
 end;
$function$
;
CREATE OR REPLACE FUNCTION public.team_goals_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.team_goals_request(p_action,p_data) $function$
;
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
 active_entries jsonb='{}'; archived jsonb='{}'; normalized jsonb='{}';
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
 if not cfg.enabled then raise exception 'Team goals are switched off by the coach';end if;
 editable:=private.team_goal_access(tid,aid,true);
 if p_action='save' then
  if not editable then raise exception 'Only this athlete or their linked parent can edit these goals';end if;
  -- Serializes writes and prevents a stale form from replacing newer goal settings.
  select * into cfg from private.team_goal_settings where team_id=tid for update;
  if not cfg.enabled or cfg.revision is distinct from (p_data->>'settings_revision')::integer then raise exception 'Goal settings changed. Reload before saving.';end if;
 end if;
 for c in select value from jsonb_array_elements(cfg.categories) loop
  for n in 1..(c->>'count')::integer loop keys:=array_append(keys,(c->>'id')||':'||n);end loop;
 end loop;
 select * into g from private.athlete_team_goals where team_id=tid and athlete_id=aid;
 if p_action='save' then
  if coalesce(g.revision,0) is distinct from (p_data->>'revision')::integer then raise exception 'Goals changed on another device. Reload before saving.';end if;
  if jsonb_typeof(p_data->'entries') is distinct from 'object' then raise exception 'Invalid goals';end if;
  if (select count(*) from jsonb_each(p_data->'entries'))<>cardinality(keys) then raise exception 'Fill the current goal slots or leave them blank';end if;
  for item in select * from jsonb_each(p_data->'entries') loop
   if not item.key=any(keys) then raise exception 'Unknown goal slot';end if;
   e:=item.value;
   if jsonb_typeof(e)<>'object' or jsonb_typeof(e->'text') is distinct from 'string' or length(e->>'text')>600 or jsonb_typeof(e->'complete') is distinct from 'boolean' then raise exception 'Each goal needs text (up to 600 characters) and a completion choice';end if;
   if (e->>'complete')::boolean and trim(e->>'text')='' then raise exception 'Write a goal before marking it complete';end if;
   select value into c from jsonb_array_elements(cfg.categories) where value->>'id'=split_part(item.key,':',1);
   normalized:=normalized||jsonb_build_object(item.key,jsonb_build_object('text',trim(e->>'text'),'complete',(e->>'complete')::boolean,'label',c->>'label','slot',split_part(item.key,':',2)::integer));
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
 return jsonb_build_object('team_id',tid,'team_name',(select name from public.teams where id=tid),'athlete_id',aid,'name',(select first_name||' '||last_name from public.athletes where id=aid),'categories',cfg.categories,'instructions',cfg.instructions,'settings_revision',cfg.revision,'revision',coalesce(g.revision,0),'entries',active_entries,'archived',archived,'editable',editable);
end $function$
;