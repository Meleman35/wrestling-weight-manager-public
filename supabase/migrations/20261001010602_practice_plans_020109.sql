begin;
-- Fail before any change if the existing deletion/merge schema has drifted.
do $$begin
 if private.scoped_deletion_schema_hash()<>'77511a6731a00bdd44ab3767a9581c873cb8e69f97f54cbbb51547f8276568d0'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Practice plans needs a fresh schema compatibility review';end if;
end $$;
-- Shared coaching plans. Athlete/parent/managed logins have no plan access.
-- Billing is not connected. Use the same closed Team Pro coverage adapter as
-- paid wrestler statistics; roles and video pilot grants never prove payment.
-- The verified entitlement service must cover paid Team Pro/College Pro teams
-- and eligible active full-feature trials before enabling real plans.
create function private.practice_plans_covered(p_team uuid) returns boolean
language sql stable set search_path='' as $$select private.wrestler_statistics_covered(p_team)$$;
revoke all on function private.practice_plans_covered(uuid) from public,anon,authenticated;

create function private.practice_blocks_valid(blocks jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare b jsonb; seen uuid[]='{}'; bid uuid; total integer=0; minutes integer;
begin
 if blocks is null or jsonb_typeof(blocks)<>'array' or jsonb_array_length(blocks)>40 then return false;end if;
 for b in select value from jsonb_array_elements(blocks) loop
  if jsonb_typeof(b)<>'object' or not(b ?& array['id','category','label','minutes','notes'])
   or exists(select 1 from jsonb_object_keys(b) k where k<>all(array['id','category','label','minutes','notes'])) then return false;end if;
  if jsonb_typeof(b->'id')<>'string' or jsonb_typeof(b->'category')<>'string'
   or jsonb_typeof(b->'label')<>'string' or jsonb_typeof(b->'notes')<>'string'
   or jsonb_typeof(b->'minutes')<>'number' or (b->>'minutes')!~'^[0-9]+$' then return false;end if;
  bid:=(b->>'id')::uuid;minutes:=(b->>'minutes')::integer;
  if bid=any(seen) or minutes not between 1 and 240 or length(btrim(b->>'label')) not between 1 and 120
   or length(b->>'notes')>1500 or (b->>'category') not in ('warmup','technique','drills','live','conditioning','cooldown','break','other') then return false;end if;
  seen:=array_append(seen,bid);total:=total+minutes;
 end loop;
 return total<=720;
exception when others then return false;
end $$;
revoke all on function private.practice_blocks_valid(jsonb) from public,anon,authenticated;

create table private.practice_plans (
 id uuid primary key,
 team_id uuid not null references public.teams(id) on delete cascade,
 event_id uuid unique references public.team_events(id) on delete set null,
 plan_date date not null check(plan_date between date '2000-01-01' and date '2100-12-31'),
 start_time time without time zone,
 target_minutes integer check(target_minutes between 1 and 720),
 title text not null check(length(btrim(title)) between 1 and 160),
 focus text not null default '' check(length(focus)<=2000),
 notes text not null default '' check(length(notes)<=4000),
 blocks jsonb not null default '[]' check(private.practice_blocks_valid(blocks)),
 revision integer not null default 1 check(revision>0),
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 last_request_id uuid not null,
 last_payload_hash text not null
);
create index practice_plans_team_date on private.practice_plans(team_id,plan_date desc);
create index practice_plans_created_by on private.practice_plans(created_by);
create index practice_plans_updated_by on private.practice_plans(updated_by);
alter table private.practice_plans enable row level security;
revoke all on private.practice_plans from public,anon,authenticated;
create trigger scoped_deletion_freeze before insert or update or delete on private.practice_plans for each row execute function private.scoped_deletion_freeze();

create function private.practice_plans_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();team uuid; pid uuid; eid uuid; req uuid; expected integer;
 zone text; team_name text; allowed text[]; d private.practice_plans%rowtype;
 ev public.team_events%rowtype; event_info jsonb; plans jsonb; first_day date;
 day_value date; time_value time; target integer; title_value text; hash_value text;
begin
 if u is null or not exists(select 1 from auth.users a join auth.sessions s on s.user_id=a.id
   and s.id::text=auth.jwt()->>'session_id' where a.id=u and a.deleted_at is null and a.email_confirmed_at is not null
   and (a.banned_until is null or a.banned_until<=now()) and (s.not_after is null or s.not_after>now()))
  or exists(select 1 from private.team_logins where user_id=u) or not private.scoped_deletion_access_ok()
 then raise sqlstate '42501' using message='Sign in with an authorized personal coaching account.';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>300000 then raise exception 'Invalid practice plan request';end if;
 team:=(p_data->>'team_id')::uuid;
 if team is null or not public.is_team_staff(team) then raise sqlstate '42501' using message='Practice plans are available to this team’s coaches and administrators.';end if;
 select name,coalesce(nullif(timezone,''),'UTC') into team_name,zone from public.teams where id=team;
 if not found then raise sqlstate '42501' using message='Team access is unavailable';end if;
 allowed:=case p_action
  when 'context' then array['team_id']
  when 'list' then array['team_id','month'] when 'read' then array['team_id','id']
  when 'event' then array['team_id','event_id'] when 'delete' then array['team_id','id','revision']
  when 'save' then array['team_id','id','event_id','revision','request_id','plan_date','start_time','target_minutes','title','focus','notes','blocks']
  else null end;
 if allowed is null or exists(select 1 from jsonb_object_keys(p_data) k where not(k=any(allowed))) then raise exception 'Unexpected practice plan action or field';end if;
 if p_action='context' then return jsonb_build_object('covered',private.practice_plans_covered(team),'required_plan','team_pro','team_name',team_name,'timezone',zone);end if;
 if not private.practice_plans_covered(team) then raise sqlstate 'PT402' using message='Practice Plans require active Team Pro access for this team.';end if;
 if p_action='list' then
  if coalesce(p_data->>'month','')!~'^[0-9]{4}-[0-9]{2}$' then raise exception 'Choose a month';end if;
  first_day:=((p_data->>'month')||'-01')::date;
  select coalesce(jsonb_agg(x order by x.plan_date desc,x.start_time),'[]') into plans from
   (select id,event_id,plan_date,start_time,title,revision,updated_at,jsonb_array_length(blocks) block_count,
     (select coalesce(sum((b->>'minutes')::integer),0) from jsonb_array_elements(blocks) b) total_minutes
    from private.practice_plans where team_id=team and plan_date>=first_day and plan_date<first_day+interval '1 month'
    order by plan_date desc,start_time limit 500) x;
  return jsonb_build_object('plans',plans,'team_name',team_name,'timezone',zone);
 end if;
 pid:=(p_data->>'id')::uuid;
 if p_action='event' then
  eid:=(p_data->>'event_id')::uuid;
  select * into ev from public.team_events where id=eid and team_id=team and event_type='practice';
  if not found then raise exception 'This practice is no longer available on this team';end if;
  select * into d from private.practice_plans where team_id=team and event_id=eid;
 else
  if pid is null then raise exception 'Choose a practice plan';end if;
  -- Serialize create/retry/update, including two coaches saving the same new ID.
  perform pg_advisory_xact_lock(hashtextextended(pid::text,0));
  select * into d from private.practice_plans where id=pid and team_id=team for update;
  if p_action='read' and not found then raise exception 'This practice plan is no longer available';end if;
 end if;
 if p_action='delete' then
  if d.id is null then return jsonb_build_object('deleted',true);end if;
  if (p_data->>'revision')::integer is distinct from d.revision then raise exception 'Another coach changed this plan. Reopen it before deleting.';end if;
  delete from private.practice_plans where id=d.id and team_id=team;
  return jsonb_build_object('deleted',true);
 elsif p_action='save' then
  if not(p_data ?& allowed) or jsonb_typeof(p_data->'title')<>'string' or jsonb_typeof(p_data->'focus')<>'string'
   or jsonb_typeof(p_data->'notes')<>'string' or not private.practice_blocks_valid(p_data->'blocks')
   or jsonb_typeof(p_data->'revision')<>'number' or (p_data->>'revision')!~'^[0-9]+$'
   or coalesce(p_data->>'plan_date','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or (p_data->>'start_time' is not null and (p_data->>'start_time')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$')
   or (p_data->>'target_minutes' is not null and (jsonb_typeof(p_data->'target_minutes')<>'number' or (p_data->>'target_minutes')!~'^[0-9]+$'))
  then raise exception 'Check the plan and blocks: use whole minutes, up to 40 blocks and 12 hours total.';end if;
  req:=(p_data->>'request_id')::uuid;expected:=(p_data->>'revision')::integer;eid:=(p_data->>'event_id')::uuid;
  day_value:=(p_data->>'plan_date')::date;time_value:=(p_data->>'start_time')::time;
  target:=(p_data->>'target_minutes')::integer;title_value:=btrim(p_data->>'title');
  if req is null or expected is null or day_value not between date '2000-01-01' and date '2100-12-31'
   or length(title_value) not between 1 and 160 or length(p_data->>'focus')>2000 or length(p_data->>'notes')>4000
   or (target is not null and target not between 1 and 720) then raise exception 'Check the title, date, notes and target length.';end if;
  hash_value:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  if d.id is not null and d.last_request_id=req then
   if d.last_payload_hash<>hash_value then raise exception 'This save request has different details. Reopen the plan.';end if;
   return jsonb_build_object('plan',to_jsonb(d)-array['last_request_id','last_payload_hash','created_by','updated_by'],'saved',true);
  end if;
  if (d.id is null and expected<>0) or (d.id is not null and expected<>d.revision)
   then raise exception 'Another coach changed this plan. Your draft is still here; reopen the saved plan to review their changes.';end if;
  if eid is not null then
   select * into ev from public.team_events where id=eid and team_id=team and event_type='practice' for share;
   if not found then raise exception 'The linked practice is no longer available. Unlink it before saving.';end if;
   if day_value<>(ev.starts_at at time zone zone)::date then raise exception 'The practice date has changed. Match the plan date to the scheduled practice, or unlink it.';end if;
  end if;
  if d.id is null then
   insert into private.practice_plans(id,team_id,event_id,plan_date,start_time,target_minutes,title,focus,notes,blocks,created_by,updated_by,last_request_id,last_payload_hash)
    values(pid,team,eid,day_value,time_value,target,title_value,p_data->>'focus',p_data->>'notes',p_data->'blocks',u,u,req,hash_value) returning * into d;
  else
   update private.practice_plans set event_id=eid,plan_date=day_value,start_time=time_value,target_minutes=target,title=title_value,
    focus=p_data->>'focus',notes=p_data->>'notes',blocks=p_data->'blocks',updated_by=u,updated_at=now(),revision=revision+1,last_request_id=req,last_payload_hash=hash_value
    where id=pid and team_id=team returning * into d;
  end if;
 end if;
 if d.event_id is not null then select * into ev from public.team_events where id=d.event_id and team_id=team;end if;
 if ev.id is not null then
  event_info:=jsonb_build_object('id',ev.id,'title',ev.title,'plan_date',to_char(ev.starts_at at time zone zone,'YYYY-MM-DD'),
   'start_time',to_char(ev.starts_at at time zone zone,'HH24:MI'),
   'target_minutes',case when ev.ends_at>ev.starts_at and ev.ends_at<=ev.starts_at+interval '12 hours' then floor(extract(epoch from ev.ends_at-ev.starts_at)/60)::integer else null end);
 end if;
 return jsonb_build_object('plan',case when d.id is not null then to_jsonb(d)-array['last_request_id','last_payload_hash','created_by','updated_by'] else null end,
  'event',event_info,'team_name',team_name,'timezone',zone,'saved',p_action='save');
exception when unique_violation then raise exception 'A plan already exists for this practice. Open it from the schedule to continue.';
end $$;
revoke all on function private.practice_plans_request(text,jsonb) from public,anon;
grant execute on function private.practice_plans_request(text,jsonb) to authenticated;
create function public.practice_plans_request(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.practice_plans_request(p_action,p_data)$$;
revoke all on function public.practice_plans_request(text,jsonb) from public,anon;
grant execute on function public.practice_plans_request(text,jsonb) to authenticated;

-- Register the full reviewed catalog and keep both drift guards exact.
do $$declare snapshot jsonb; expected_hash text; source text;begin
 select jsonb_build_object(
  'tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'columns',
   (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull) order by a.attnum)
    from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) order by n.nspname,c.relname),'[]')
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%'),
  'constraints',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',k.conname,'type',k.contype,
   'columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.conkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=c.oid and a.attnum=z.num),
   'ref_schema',rn.nspname,'ref_table',rc.relname,
   'ref_columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.confkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=rc.oid and a.attnum=z.num),
   'delete_action',k.confdeltype) order by n.nspname,c.relname,k.conname),'[]')
   from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
   left join pg_class rc on rc.oid=k.confrelid left join pg_namespace rn on rn.oid=rc.relnamespace
   where n.nspname in ('public','private') and c.relname not like 'scoped_deletion_%')
 ) into snapshot;
 expected_hash:=private.scoped_deletion_schema_hash();
 update private.scoped_deletion_config set catalog=snapshot,catalog_hash=expected_hash where id;
 -- Refresh only the reviewed old fingerprint in the existing merge router.
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if position('77511a6731a00bdd44ab3767a9581c873cb8e69f97f54cbbb51547f8276568d0' in source)=0 then raise exception 'Unexpected athlete merge version; review compatibility first';end if;
 execute replace(source,'77511a6731a00bdd44ab3767a9581c873cb8e69f97f54cbbb51547f8276568d0',expected_hash);
end $$;

commit;
