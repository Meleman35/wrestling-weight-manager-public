-- A reviewed contact choice never changes authentication credentials or relaxes consent.
-- Return conflict field names only; private contact values never leave the API.
create function private.athlete_merge_contact_values(a jsonb,b jsonb,contact_resolution text) returns jsonb
language plpgsql immutable set search_path='' as $$
declare field text;
begin
 if contact_resolution is not null and contact_resolution<>'keep' then raise exception 'Invalid contact resolution';end if;
 if contact_resolution='keep' then
  foreach field in array array['email','phone'] loop
   if a->field not in ('null','""') and b->field not in ('null','""') and a->field<>b->field then b:=b-field;end if;
  end loop;
 end if;
 return private.athlete_merge_values(a,b);
end $$;
revoke all on function private.athlete_merge_contact_values(jsonb,jsonb,text) from public,anon,authenticated;

-- Preserve separate guardian approvals and invitation states.
create or replace function private.athlete_merge_plan(s uuid,k uuid,contact_resolution text) returns jsonb
language plpgsql set search_path='' as $$
declare a public.athletes%rowtype;b public.athletes%rowtype;r record;ix record;cnt bigint;digest text;finger text='';counts jsonb='[]';blockers jsonb='[]';aj jsonb;bj jsonb;cols text;pred text;collision boolean;sp uuid;kp uuid;source_birth date;keep_birth date;field text;contact_conflicts jsonb='[]';
begin
 if contact_resolution is not null and contact_resolution<>'keep' then raise exception 'Choose the kept profile contact details or review the profiles again';end if;
 select * into a from public.athletes where id=s;select * into b from public.athletes where id=k;
 if a.id is null or b.id is null or s=k then raise exception 'Choose two different existing athletes';end if;
 finger:=coalesce(contact_resolution,'unresolved')||to_jsonb(a)::text||to_jsonb(b)::text;
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
  if aj not in ('null','""') and bj not in ('null','""') and aj<>bj then
   if r.col in ('email','phone') then
    contact_conflicts:=contact_conflicts||jsonb_build_array(r.col);
    if contact_resolution is distinct from 'keep' then blockers:=blockers||jsonb_build_array('Different contact details need your selection.');end if;
   else blockers:=blockers||jsonb_build_array('Different '||replace(r.col,'_',' ')||' values need review.');end if;
  end if;
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
   if aj is not null and bj is not null then
    if r.tbl='athlete_private_contact' then
     foreach field in array array['email','phone'] loop
      if aj->field not in ('null','""') and bj->field not in ('null','""') and aj->field<>bj->field then contact_conflicts:=contact_conflicts||jsonb_build_array(field);end if;
     end loop;
     if private.athlete_merge_contact_values(aj,bj,contact_resolution) is null then blockers:=blockers||jsonb_build_array('Different contact details need your selection.');end if;
    elsif private.athlete_merge_values(aj,bj) is null then blockers:=blockers||jsonb_build_array('Conflicting '||replace(r.tbl,'_',' ')||' values need review.');end if;
   end if;
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
 return jsonb_build_object('keep',jsonb_build_object('id',k,'name',b.first_name||' '||b.last_name,'created_at',b.created_at),'duplicate',jsonb_build_object('id',s,'name',a.first_name||' '||a.last_name,'created_at',a.created_at),'contact_conflicts',(select coalesce(jsonb_agg(distinct value),'[]') from jsonb_array_elements(contact_conflicts)),'contact_resolution',contact_resolution,'records',counts,'blockers',(select coalesce(jsonb_agg(distinct value),'[]') from jsonb_array_elements(blockers)),'version',encode(sha256(convert_to(finger,'UTF8')),'hex'));
end $$;
revoke all on function private.athlete_merge_plan(uuid,uuid,text) from public,anon,authenticated;


-- Keep internal legacy callers fail-closed until an explicit choice is reviewed.
create or replace function private.athlete_merge_plan(s uuid,k uuid) returns jsonb
language sql set search_path='' as $$select private.athlete_merge_plan(s,k,null)$$;
revoke all on function private.athlete_merge_plan(uuid,uuid) from public,anon,authenticated;

create or replace function private.athlete_merge_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();t uuid=(p_data->>'team_id')::uuid;s uuid=(p_data->>'duplicate_id')::uuid;k uuid=(p_data->>'keep_id')::uuid;
 a public.athletes%rowtype;b public.athletes%rowtype;r record;plan jsonb;rows jsonb;aj jsonb;bj jsonb;merged jsonb;cols text;sp uuid;kp uuid;receipt jsonb;contact_resolution text=p_data->>'contact_resolution';
begin
 if u is null or not exists(select 1 from auth.users where id=u and deleted_at is null and email_confirmed_at is not null and (banned_until is null or banned_until<=now())) or exists(select 1 from private.team_logins where user_id=u) or not coalesce(public.is_team_admin(t),false) or coalesce((p_data->>'view_as_parent')::boolean,false) then raise sqlstate '42501' using message='A personal team-administrator account is required';end if;
 if p_action='candidates' then
  select coalesce(jsonb_agg(jsonb_build_object('id',candidate.id,'name',candidate.first_name||' '||candidate.last_name,'created_at',candidate.created_at,'has_login',exists(select 1 from public.team_memberships m where m.athlete_id=candidate.id and m.role='athlete' and m.active)) order by candidate.last_name,candidate.first_name,candidate.created_at),'[]') into rows
  from public.athletes candidate where exists(select 1 from public.roster_memberships rm join public.seasons ss on ss.id=rm.season_id where rm.athlete_id=candidate.id and ss.team_id=t);return rows;
 end if;
 if contact_resolution is not null and contact_resolution<>'keep' then raise exception 'Choose the kept profile contact details or review the profiles again';end if;
 if p_action not in ('preview','merge') then raise exception 'Unknown merge action';end if;
 if s is null or k is null or s=k then raise exception 'Choose two different athletes';end if;
 -- A retry after connection loss returns the committed receipt, never merges twice.
 select metadata into receipt from public.audit_log where actor_user_id=u and action='merge_duplicate_athlete' and entity_id=k and metadata->>'duplicate_id'=s::text and metadata->>'team_id'=t::text order by id desc limit 1;
 if receipt is not null and p_action='merge' then return receipt;end if;
 if private.scoped_deletion_schema_hash()<>'4edb6748d4f52b32daeb62498f2fb3152b6bc5caa1ac1618b7e89e77c850d587' then raise exception 'Athlete merge needs a schema compatibility review before it can continue';end if;
 if (select count(*) from public.athletes candidate where id in(s,k) and exists(select 1 from public.roster_memberships rm join public.seasons ss on ss.id=rm.season_id where rm.athlete_id=candidate.id and ss.team_id=t))<>2 then raise sqlstate '42501' using message='Both athletes must belong to the selected team';end if;
 if p_action='merge' then
  if p_data->>'confirmation' is distinct from 'merge' or p_data->>'version' is null then raise exception 'Type merge after reviewing both profiles';end if;
  perform pg_advisory_xact_lock(hashtext('athlete_merge'));
  perform id from public.athletes where id in(s,k) order by id for update;
  perform id from public.athlete_profiles where id in(select profile_id from public.athletes where id in(s,k)) order by id for update;
  perform id from private.wrestling_profiles where athlete_profile_id in(select profile_id from public.athletes where id in(s,k)) order by id for update;
  for r in select * from private.athlete_merge_refs() loop execute format('select 1 from %I.%I where %I in($1,$2) for update',r.ns,r.tbl,r.col) using s,k;end loop;
  for r in select * from private.athlete_merge_json_refs() loop execute format('lock table %I.%I in share row exclusive mode',r.ns,r.tbl);end loop;
 end if;
 plan:=private.athlete_merge_plan(s,k,contact_resolution);
 if p_action='preview' then return plan;end if;
 if jsonb_array_length(plan->'blockers')>0 then raise exception '%',plan->'blockers'->>0;end if;
 if plan->>'version' is distinct from p_data->>'version' then raise exception 'Records changed. Review the merge again before confirming';end if;
 select * into a from public.athletes where id=s;select * into b from public.athletes where id=k;
 -- Keep the chosen athlete name. Only absent, non-conflicting personal fields fill in.
 update public.athletes set email=case when contact_resolution='keep' and (plan->'contact_conflicts')?'email' then b.email else coalesce(nullif(b.email,''),a.email) end,phone=case when contact_resolution='keep' and (plan->'contact_conflicts')?'phone' then b.phone else coalesce(nullif(b.phone,''),a.phone) end,birth_date=coalesce(b.birth_date,a.birth_date),graduation_year=coalesce(b.graduation_year,a.graduation_year),photo_path=coalesce(b.photo_path,a.photo_path) where id=k;
 for r in select unnest(array['athlete_private_identity','athlete_private_contact','athlete_profile_details','athlete_medical_private']) as tbl loop
  execute format('select to_jsonb(x) from public.%I x where athlete_id=$1',r.tbl) into aj using k;
  execute format('select to_jsonb(x) from public.%I x where athlete_id=$1',r.tbl) into bj using s;
  if aj is not null and bj is not null then
   merged:=case when r.tbl='athlete_private_contact' then private.athlete_merge_contact_values(aj,bj,contact_resolution) else private.athlete_merge_values(aj,bj) end;if merged is null then raise exception 'Profile values changed. Review again';end if;
   select string_agg(format('%1$I = v.%1$I',attname),',') into cols from pg_attribute where attrelid=format('public.%I',r.tbl)::regclass and attnum>0 and not attisdropped and attname not in ('athlete_id','updated_at','updated_by');
   execute format('update public.%1$I x set %2$s from jsonb_populate_record(null::public.%1$I,$1) v where x.athlete_id=$2',r.tbl,cols) using merged,k;
   execute format('delete from public.%I where athlete_id=$1',r.tbl) using s;
  end if;
 end loop;
 -- A season keeps its selected primary roster settings; all event history moves below.
 delete from public.roster_memberships src using public.roster_memberships dst where src.athlete_id=s and dst.athlete_id=k and src.season_id=dst.season_id;
 for r in select * from private.athlete_merge_refs() loop execute format('update %I.%I set %I=$1 where %I=$2',r.ns,r.tbl,r.col,r.col) using k,s;end loop;
 for r in select * from private.athlete_merge_json_refs() loop execute format('update %1$I.%2$I set %3$I=private.athlete_merge_json(%3$I,$1,$2)%4$s where %3$I::text like $3 and %3$I is distinct from private.athlete_merge_json(%3$I,$1,$2)',r.ns,r.tbl,r.col,case when r.tbl in ('match_books','video_scored_matches') then ',revision=revision+1' else '' end) using s,k,'%'||s::text||'%';end loop;
 select id into sp from private.wrestling_profiles where athlete_profile_id=a.profile_id;select id into kp from private.wrestling_profiles where athlete_profile_id=b.profile_id;
 if a.profile_id<>b.profile_id then
  if sp is not null and kp is null then update private.wrestling_profiles set athlete_profile_id=b.profile_id where id=sp;
  elsif sp is not null then delete from private.wrestling_profiles where id=sp;end if;
 end if;
 delete from public.athletes where id=s;
 if a.profile_id<>b.profile_id then delete from public.athlete_profiles where id=a.profile_id and not exists(select 1 from public.athletes where profile_id=a.profile_id);end if;
 receipt:=jsonb_build_object('status','completed','team_id',t,'keep_id',k,'duplicate_id',s,'completed_at',now(),'contact_resolution',contact_resolution,'contact_conflicts',plan->'contact_conflicts','records',plan->'records');
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(u,'merge_duplicate_athlete','athlete',k,receipt);
 return receipt;
exception when unique_violation or check_violation or foreign_key_violation then raise exception 'These profiles have conflicting saved records. Nothing was merged. Review their records and try again';
end $$;
revoke all on function private.athlete_merge_request(text,jsonb) from public,anon;
grant execute on function private.athlete_merge_request(text,jsonb) to authenticated;
