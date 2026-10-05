CREATE OR REPLACE FUNCTION private.athlete_merge_request(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if private.scoped_deletion_schema_hash()<>'c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8' then raise exception 'Athlete merge needs a schema compatibility review before it can continue';end if;
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
end $function$
