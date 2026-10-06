begin;
-- Reject pre-existing schema drift before extending the reviewed shared plan.
do $$begin
 if not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'PRACTICE_REVIEW_SCHEMA_REVIEW_REQUIRED';end if;
 perform set_config('wm.practice_review_prior_hash',private.scoped_deletion_schema_hash(),true);
end $$;
alter table private.practice_plans add column athlete_visible boolean not null default false;
create or replace function private.practice_blocks_valid(blocks jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare b jsonb; seen uuid[]='{}'; bid uuid; total integer=0; minutes integer;
begin
 if blocks is null or jsonb_typeof(blocks)<>'array' or jsonb_array_length(blocks)>40 then return false;end if;
 for b in select value from jsonb_array_elements(blocks) loop
  if jsonb_typeof(b)<>'object' or not(b ?& array['id','category','label','minutes','notes'])
   or exists(select 1 from jsonb_object_keys(b) k where k<>all(array['id','category','label','minutes','notes','completed','review_next','review_note'])) then return false;end if;
  if jsonb_typeof(b->'id')<>'string' or jsonb_typeof(b->'category')<>'string'
   or jsonb_typeof(b->'label')<>'string' or jsonb_typeof(b->'notes')<>'string'
   or jsonb_typeof(b->'minutes')<>'number' or (b->>'minutes')!~'^[0-9]+$' then return false;end if;
  if (b ? 'completed' and jsonb_typeof(b->'completed')<>'boolean')
   or (b ? 'review_next' and jsonb_typeof(b->'review_next')<>'boolean')
   or (b ? 'review_note' and (jsonb_typeof(b->'review_note')<>'string' or length(b->>'review_note')>1500)) then return false;end if;
  bid:=(b->>'id')::uuid;minutes:=(b->>'minutes')::integer;
  if bid=any(seen) or minutes not between 1 and 240 or length(btrim(b->>'label')) not between 1 and 120
   or length(b->>'notes')>1500 or (b->>'category') not in ('warmup','technique','drills','live','conditioning','cooldown','break','other') then return false;end if;
  seen:=array_append(seen,bid);total:=total+minutes;
 end loop;
 return total<=720;
exception when others then return false;
end $$;
revoke all on function private.practice_blocks_valid(jsonb) from public,anon,authenticated;

do $$declare source text;begin
 source:=pg_get_functiondef('private.practice_plans_request(text,jsonb)'::regprocedure);
 if position($old$array['team_id','id','event_id','revision','request_id','plan_date','start_time','target_minutes','title','focus','notes','blocks']$old$ in source)=0 then raise exception 'PRACTICE_REVIEW_SOURCE_REVIEW_REQUIRED';end if;
 source:=replace(source,$old$array['team_id','id','event_id','revision','request_id','plan_date','start_time','target_minutes','title','focus','notes','blocks']$old$,$new$array['team_id','id','event_id','revision','request_id','plan_date','start_time','target_minutes','title','focus','notes','blocks','athlete_visible']$new$);
 if position($old$title,revision,updated_at,jsonb_array_length(blocks)$old$ in source)=0 then raise exception 'PRACTICE_REVIEW_SOURCE_REVIEW_REQUIRED';end if;
 source:=replace(source,$old$title,revision,updated_at,jsonb_array_length(blocks)$old$,$new$title,revision,updated_at,athlete_visible,jsonb_array_length(blocks)$new$);
 if position($old$if not(p_data ?& allowed)$old$ in source)=0 then raise exception 'PRACTICE_REVIEW_SOURCE_REVIEW_REQUIRED';end if;
 source:=replace(source,$old$if not(p_data ?& allowed)$old$,$new$if (p_data ? 'athlete_visible' and jsonb_typeof(p_data->'athlete_visible')<>'boolean') or not(p_data ?& array_remove(allowed,'athlete_visible'))$new$);
 if position($old$notes,blocks,created_by,updated_by,last_request_id,last_payload_hash)$old$ in source)=0 then raise exception 'PRACTICE_REVIEW_SOURCE_REVIEW_REQUIRED';end if;
 source:=replace(source,$old$notes,blocks,created_by,updated_by,last_request_id,last_payload_hash)$old$,$new$notes,blocks,athlete_visible,created_by,updated_by,last_request_id,last_payload_hash)$new$);
 if position($old$p_data->'blocks',u,u,req,hash_value)$old$ in source)=0 then raise exception 'PRACTICE_REVIEW_SOURCE_REVIEW_REQUIRED';end if;
 source:=replace(source,$old$p_data->'blocks',u,u,req,hash_value)$old$,$new$p_data->'blocks',coalesce((p_data->>'athlete_visible')::boolean,false),u,u,req,hash_value)$new$);
 if position($old$focus=p_data->>'focus',notes=p_data->>'notes',blocks=p_data->'blocks',updated_by=u$old$ in source)=0 then raise exception 'PRACTICE_REVIEW_SOURCE_REVIEW_REQUIRED';end if;
 source:=replace(source,$old$focus=p_data->>'focus',notes=p_data->>'notes',blocks=p_data->'blocks',updated_by=u$old$,$new$focus=p_data->>'focus',notes=p_data->>'notes',blocks=p_data->'blocks',athlete_visible=coalesce((p_data->>'athlete_visible')::boolean,d.athlete_visible),updated_by=u$new$);
 execute source;
end $$;

-- A separate read-only endpoint: team membership is checked on every request;
-- coach-only notes, review fields, authorship and unpublished plans never leave it.
create function private.practice_plans_view_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();team uuid;zone text;team_name text;plans jsonb;first_day date;d private.practice_plans%rowtype;allowed text[];
begin
 if u is null or not exists(select 1 from auth.users a join auth.sessions s on s.user_id=a.id
  and s.id::text=auth.jwt()->>'session_id' where a.id=u and a.deleted_at is null and a.email_confirmed_at is not null
  and (a.banned_until is null or a.banned_until<=now()) and (s.not_after is null or s.not_after>now()))
  or exists(select 1 from private.team_logins where user_id=u) or not private.scoped_deletion_access_ok()
 then raise sqlstate '42501' using message='Sign in with an authorized personal athlete account.';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4096 then raise exception 'Invalid plan request';end if;
 team:=(p_data->>'team_id')::uuid;
 if team is null or not exists(select 1 from public.team_memberships m where m.team_id=team and m.user_id=u and m.active and m.role='athlete')
 then raise sqlstate '42501' using message='Shared plans are available to active athletes on this team.';end if;
 allowed:=case p_action when 'context' then array['team_id'] when 'list' then array['team_id','month'] when 'read' then array['team_id','id'] else null end;
 if allowed is null or exists(select 1 from jsonb_object_keys(p_data) k where not(k=any(allowed))) then raise exception 'Unexpected plan action or field';end if;
 select name,coalesce(nullif(timezone,''),'UTC') into team_name,zone from public.teams where id=team;
 if p_action='context' then return jsonb_build_object('covered',private.practice_plans_covered(team),'team_name',team_name,'timezone',zone);end if;
 if not private.practice_plans_covered(team) then raise sqlstate 'PT402' using message='Shared practice plans are unavailable.';end if;
 if p_action='list' then
  if coalesce(p_data->>'month','')!~'^[0-9]{4}-[0-9]{2}$' then raise exception 'Choose a month';end if;
  first_day:=((p_data->>'month')||'-01')::date;
  select coalesce(jsonb_agg(x order by x.plan_date desc,x.start_time),'[]') into plans from
   (select id,plan_date,start_time,title,jsonb_array_length(blocks) block_count,
     (select coalesce(sum((b->>'minutes')::integer),0) from jsonb_array_elements(blocks) b) total_minutes
    from private.practice_plans where team_id=team and athlete_visible and plan_date>=first_day and plan_date<first_day+interval '1 month'
    order by plan_date desc,start_time limit 500) x;
  return jsonb_build_object('plans',plans,'team_name',team_name,'timezone',zone);
 end if;
 select * into d from private.practice_plans where id=(p_data->>'id')::uuid and team_id=team and athlete_visible;
 if not found then raise sqlstate '42501' using message='This practice plan is not shared with athletes.';end if;
 return jsonb_build_object('plan',jsonb_build_object('id',d.id,'plan_date',d.plan_date,'start_time',d.start_time,'target_minutes',d.target_minutes,
  'title',d.title,'focus',d.focus,'blocks',(select coalesce(jsonb_agg(jsonb_build_object('id',b->'id','category',b->'category','label',b->'label','minutes',b->'minutes','notes',b->'notes') order by ord),'[]') from jsonb_array_elements(d.blocks) with ordinality as x(b,ord))),
  'team_name',team_name,'timezone',zone);
end $$;
revoke all on function private.practice_plans_view_request(text,jsonb) from public,anon;
grant execute on function private.practice_plans_view_request(text,jsonb) to authenticated;
create function public.practice_plans_view_request(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.practice_plans_view_request(p_action,p_data)$$;
revoke all on function public.practice_plans_view_request(text,jsonb) from public,anon;
grant execute on function public.practice_plans_view_request(text,jsonb) to authenticated;
-- Register the full reviewed catalog and keep both drift guards exact.
do $$declare snapshot jsonb; expected_hash text; source text; prior_hash text=current_setting('wm.practice_review_prior_hash');begin
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
 if position(prior_hash in source)=0 then raise exception 'Unexpected athlete merge version; review compatibility first';end if;
 execute replace(source,prior_hash,expected_hash);
end $$;

commit;
