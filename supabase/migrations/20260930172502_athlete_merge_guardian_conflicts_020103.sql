-- Preserve separate guardian approvals and invitation states.
create or replace function private.athlete_merge_plan(s uuid,k uuid) returns jsonb
language plpgsql set search_path='' as $$
declare a public.athletes%rowtype;b public.athletes%rowtype;r record;ix record;cnt bigint;digest text;finger text='';counts jsonb='[]';blockers jsonb='[]';aj jsonb;bj jsonb;cols text;pred text;collision boolean;sp uuid;kp uuid;source_birth date;keep_birth date;
begin
 select * into a from public.athletes where id=s;select * into b from public.athletes where id=k;
 if a.id is null or b.id is null or s=k then raise exception 'Choose two different existing athletes';end if;
 finger:=to_jsonb(a)::text||to_jsonb(b)::text;
 if a.organization_id is distinct from b.organization_id then blockers:=blockers||jsonb_build_array('These profiles belong to different organizations. Cross-organization identity merges require a separate review.');end if;
 if a.profile_id<>b.profile_id and exists(select 1 from public.athletes where profile_id=a.profile_id and id<>s) then blockers:=blockers||jsonb_build_array('The duplicate already shares an identity with other team profiles. Those linked profiles need a coordinated review.');end if;
 if exists(select 1 from public.athletes x join public.roster_memberships rm on rm.athlete_id=x.id join public.seasons ss on ss.id=rm.season_id where x.profile_id in(a.profile_id,b.profile_id) and not public.is_team_admin(ss.team_id)) then blockers:=blockers||jsonb_build_array('You must administer every team connected to these athlete profiles.');end if;
 if (select count(distinct user_id) from public.team_memberships where athlete_id in(s,k) and role='athlete')>1 then blockers:=blockers||jsonb_build_array('Two different athlete sign-in accounts are linked. Verify account ownership before merging.');end if;
 if exists(select 1 from private.team_logins where athlete_id in(s,k)) then blockers:=blockers||jsonb_build_array('A team device or managed login is linked. Remove that assignment before merging.');end if;
 if exists(select 1 from private.weight_test_athletes where athlete_id in(s,k)) then blockers:=blockers||jsonb_build_array('Test athletes cannot be merged with athlete profiles.');end if;
 if exists(select 1 from public.athlete_guardians src join public.athlete_guardians dst on dst.athlete_id=k and ((src.guardian_user_id is not null and src.guardian_user_id=dst.guardian_user_id) or (nullif(lower(trim(src.email)),'') is not null and lower(trim(src.email))=lower(trim(dst.email)))) where src.athlete_id=s) then blockers:=blockers||jsonb_build_array('Both profiles list the same parent or guardian. Review those family links and invitation states before merging.');end if;
 if jsonb_array_length(blockers)>0 then
  return jsonb_build_object('keep',jsonb_build_object('id',k,'name',b.first_name||' '||b.last_name,'created_at',b.created_at),'duplicate',jsonb_build_object('id',s,'name',a.first_name||' '||a.last_name,'created_at',a.created_at),'records','[]'::jsonb,'blockers',blockers,'version',encode(sha256(convert_to(finger,'UTF8')),'hex'));
 end if;
 for r in select unnest(array['birth_date','email','phone','graduation_year','photo_path']) as col loop
  aj:=to_jsonb(a)->r.col;bj:=to_jsonb(b)->r.col;
  if aj not in ('null','""') and bj not in ('null','""') and aj<>bj then blockers:=blockers||jsonb_build_array('Different '||replace(r.col,'_',' ')||' values need review.');end if;
 end loop;
 select coalesce((select birth_date from public.athlete_private_identity where athlete_id=s),a.birth_date) into source_birth;
 select coalesce((select birth_date from public.athlete_private_identity where athlete_id=k),b.birth_date) into keep_birth;
 if source_birth is not null and keep_birth is not null and source_birth<>keep_birth then blockers:=blockers||jsonb_build_array('Birth dates do not match. Verify these are the same athlete.');end if;
 -- Existing social/family conversations are never dropped to force a merge.
 select id into sp from private.wrestling_profiles where athlete_profile_id=a.profile_id;
 select id into kp from private.wrestling_profiles where athlete_profile_id=b.profile_id;
 if exists(select 1 from private.profile_approval_requests where profile_id in(sp,kp) and status='pending') then blockers:=blockers||jsonb_build_array('A parent profile approval is pending. Finish that review before merging.');end if;
 if sp is not null and kp is not null and sp<>kp then
  for r in select distinct n.nspname ns,c.relname tbl,at.attname col from pg_constraint f join pg_class c on c.oid=f.conrelid join pg_namespace n on n.oid=c.relnamespace join pg_attribute at on at.attrelid=c.oid and at.attnum=f.conkey[1] where f.contype='f' and f.confrelid='private.wrestling_profiles'::regclass loop
   execute format('select exists(select 1 from %I.%I where %I=$1)',r.ns,r.tbl,r.col) into collision using sp;
   if collision then blockers:=blockers||jsonb_build_array('The duplicate has separate social or family records. Keep that established profile, or request a coordinated identity review.');exit;end if;
  end loop;
  if exists(select 1 from private.wrestling_profiles where id=sp and (details<>'{}' or photo_path is not null)) then blockers:=blockers||jsonb_build_array('The duplicate has its own public profile content. Preserve or reconcile that content before merging.');end if;
 end if;
 for r in select * from private.athlete_merge_refs() loop
  execute format('select count(*),coalesce(string_agg(md5(to_jsonb(x)::text),%L order by to_jsonb(x)::text),%L) from %I.%I x where %I in($1,$2)',',','',r.ns,r.tbl,r.col) into cnt,digest using s,k;
  finger:=finger||r.ns||r.tbl||r.col||digest;
  execute format('select count(*) from %I.%I where %I=$1',r.ns,r.tbl,r.col) into cnt using s;
  if cnt>0 then counts:=counts||jsonb_build_array(jsonb_build_object('table',r.tbl,'count',cnt));end if;
  if r.ns='public' and r.tbl in ('athlete_private_identity','athlete_private_contact','athlete_profile_details','athlete_medical_private') then
   execute format('select to_jsonb(x) from public.%I x where athlete_id=$1',r.tbl) into aj using k;
   execute format('select to_jsonb(x) from public.%I x where athlete_id=$1',r.tbl) into bj using s;
   if aj is not null and bj is not null and private.athlete_merge_values(aj,bj) is null then blockers:=blockers||jsonb_build_array('Conflicting '||replace(r.tbl,'_',' ')||' values need review.');end if;
  elsif r.tbl<>'roster_memberships' then
   for ix in select i.*,c.oid rel from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace join pg_attribute at on at.attrelid=c.oid and at.attname=r.col where n.nspname=r.ns and c.relname=r.tbl and i.indisunique and at.attnum=any(i.indkey) loop
    select string_agg(format('src.%1$I is not distinct from dst.%1$I',at.attname),' and ') into cols from unnest(ix.indkey::smallint[]) ak join pg_attribute at on at.attrelid=ix.rel and at.attnum=ak where at.attname<>r.col;
    pred:=coalesce(pg_get_expr(ix.indpred,ix.rel),'true');
    execute format('select exists(select 1 from (select * from %1$I.%2$I where %3$I=$1 and (%4$s)) src join (select * from %1$I.%2$I where %3$I=$2 and (%4$s)) dst on %5$s)',r.ns,r.tbl,r.col,pred,coalesce(cols,'true')) into collision using s,k;
    if collision then blockers:=blockers||jsonb_build_array('Both profiles have separate '||replace(r.tbl,'_',' ')||' records for the same item. Review them before merging.');exit;end if;
   end loop;
  end if;
 end loop;
 for r in select * from private.athlete_merge_json_refs() loop
  execute format('select coalesce(string_agg(md5(to_jsonb(x)::text),%L order by to_jsonb(x)::text),%L) from %I.%I x where %I::text like $1',',','',r.ns,r.tbl,r.col) into digest using '%'||s::text||'%';finger:=finger||r.ns||r.tbl||r.col||digest;
  execute format('select count(*) from %I.%I where %I::text like $1',r.ns,r.tbl,r.col) into cnt using '%'||s::text||'%';if cnt>0 then counts:=counts||jsonb_build_array(jsonb_build_object('table',r.tbl||' saved references','count',cnt));end if;
 end loop;
 if exists(select 1 from private.match_books where data->>'red_id' in(s::text,k::text) and data->>'other_id' in(s::text,k::text)) or exists(select 1 from private.video_scored_matches where data->>'red_id' in(s::text,k::text) and data->>'other_id' in(s::text,k::text)) then blockers:=blockers||jsonb_build_array('These athletes appear as opponents in a saved match. Confirm their identities first.');end if;
 return jsonb_build_object('keep',jsonb_build_object('id',k,'name',b.first_name||' '||b.last_name,'created_at',b.created_at),'duplicate',jsonb_build_object('id',s,'name',a.first_name||' '||a.last_name,'created_at',a.created_at),'records',counts,'blockers',(select coalesce(jsonb_agg(distinct value),'[]') from jsonb_array_elements(blockers)),'version',encode(sha256(convert_to(finger,'UTF8')),'hex'));
end $$;
revoke all on function private.athlete_merge_plan(uuid,uuid) from public,anon,authenticated;

