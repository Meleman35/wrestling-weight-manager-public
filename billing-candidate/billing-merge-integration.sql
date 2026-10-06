-- Isolated candidate. Apply after billing-access-candidate.sql and the reviewed
-- current merge router. This never approves a new deletion/merge fingerprint.
-- Apply in one transaction; a source-pin failure must roll back every change.
-- Coverage may be changed only through the authorized selection/merge helpers.
revoke insert,update,delete on wm_billing.family_coverage from wm_billing_runtime;

create function wm_billing.coverage_merge_version(p_duplicate uuid,p_keep uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare result text;
begin
 if auth.uid() is null then raise exception 'BILLING_MERGE_AUTH_REQUIRED';end if;
 select encode(sha256(convert_to(coalesce(string_agg(
  c.user_id::text||':'||c.slot::text||':'||c.athlete_profile_id::text,'|' order by c.user_id,c.slot),''),'UTF8')),'hex')
 into result from wm_billing.family_coverage c where c.athlete_profile_id in
  (select profile_id from public.athletes where id in(p_duplicate,p_keep));
 return result;
end $$;

create function wm_billing.merge_family_coverage(p_duplicate uuid,p_keep uuid)
returns void language plpgsql security definer set search_path='' as $$
declare source_profile uuid;target_profile uuid;
begin
 if auth.uid() is null or p_duplicate is null or p_keep is null or p_duplicate=p_keep then
  raise exception 'BILLING_MERGE_AUTH_REQUIRED';end if;
 -- Same order as the existing merge router; selection takes a shared lock.
 perform pg_advisory_xact_lock(hashtext('athlete_merge'));
 select profile_id into source_profile from public.athletes where id=p_duplicate;
 select profile_id into target_profile from public.athletes where id=p_keep;
 if source_profile is null or target_profile is null then raise exception 'BILLING_MERGE_PROFILE_REQUIRED';end if;
 if source_profile=target_profile then return;end if;
 if exists(select 1 from public.athletes where profile_id=source_profile and id<>p_duplicate) then
  raise exception 'BILLING_MERGE_SHARED_PROFILE_REVIEW';end if;
 perform 1 from wm_billing.family_coverage where athlete_profile_id in(source_profile,target_profile)
  order by user_id,slot for update;
 if exists(select 1 from wm_billing.family_coverage c join private.scoped_deletion_jobs j on j.actor_id=c.user_id
  where c.athlete_profile_id in(source_profile,target_profile) and j.state not in ('cancelled','completed')) then
  raise exception 'BILLING_MERGE_DELETION_PENDING';end if;
 -- Keep an already-selected target slot. Combining duplicate identities must
 -- not consume a second family slot or add any subscription entitlement.
 delete from wm_billing.family_coverage src using wm_billing.family_coverage dst
  where src.athlete_profile_id=source_profile and dst.athlete_profile_id=target_profile and src.user_id=dst.user_id;
 update wm_billing.family_coverage set athlete_profile_id=target_profile where athlete_profile_id=source_profile;
end $$;
revoke all on function wm_billing.coverage_merge_version(uuid,uuid),wm_billing.merge_family_coverage(uuid,uuid)
 from public,anon,authenticated,wm_billing_runtime;

-- Pin the complete currently deployed router, not just an editable marker.
-- A changed router must be inspected before generating the production migration.
do $$declare source text;old_plan text:='plan:=private.athlete_merge_plan(s,k,contact_resolution);';
 old_mutation text:='select * into a from public.athletes where id=s;select * into b from public.athletes where id=k;';
begin
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if encode(sha256(convert_to(source,'UTF8')),'hex')<>'991e2028b296773026c1a090426585d7af554636572e6ff42d2aa66754af4835'
  or (length(source)-length(replace(source,old_plan,'')))<>length(old_plan)
  or (length(source)-length(replace(source,old_mutation,'')))<>length(old_mutation) then
  raise exception 'BILLING_MERGE_ROUTER_REVIEW_REQUIRED';end if;
 source:=replace(source,old_plan,old_plan||E'\n plan:=jsonb_set(plan,''{version}'',to_jsonb(encode(sha256(convert_to((plan->>''version'')||''|''||wm_billing.coverage_merge_version(s,k),''UTF8'')),''hex'')));');
 source:=replace(source,old_mutation,old_mutation||E'\n perform wm_billing.merge_family_coverage(s,k);');
 execute source;
end $$;
