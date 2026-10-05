-- Expiring, service-only acceptance fixtures. No ordinary account can invoke
-- this helper, and every identity/team must belong to the same synthetic run.
begin;
create function private.scoped_deletion_billing_acceptance(p_action text,p_run uuid,p_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.scoped_deletion_acceptance_runs%rowtype; n bigint; original text;
 who uuid; v_token uuid; v_team uuid; product text; snap jsonb; item integer; v_result jsonb;
begin
 if current_setting('role',true) is distinct from 'service_role' then raise sqlstate '42501' using message='SERVICE_ONLY';end if;
 select * into r from private.scoped_deletion_acceptance_runs where id=p_run and token_hash=p_hash
  and expires_at>now() and state in ('running','verified') for update;
 if not found then raise sqlstate '42501' using message='ACCEPTANCE_NOT_AUTHORIZED';end if;
 n:=floor(extract(epoch from now())*1000);
 if p_action='seed' then
  if r.state<>'running' or r.job_id is not null or coalesce((r.result->>'billing_seeded')::boolean,false)
   or (select count(*) from auth.users where id=any(array[r.actor_id,r.retained_id,r.child_id])
    and raw_app_meta_data->>'scoped_deletion_acceptance'=r.id::text and email like '%@tests.example.invalid'
    and email_confirmed_at is not null)<>3
   or not exists(select 1 from public.teams where id=r.team_id and organization_id=r.organization_id)
   or not exists(select 1 from public.teams where id=r.other_team_id and organization_id=r.other_organization_id)
  then raise exception 'BILLING_FIXTURE_IDENTITIES_REQUIRED';end if;
  insert into wm_billing.team_bindings values(r.actor_id,r.team_id),(r.retained_id,r.other_team_id);
  insert into wm_billing.family_coverage values(r.actor_id,1,r.profile_id),(r.retained_id,1,r.profile_id);
  for item in 1..3 loop
   who:=case when item=3 then r.retained_id else r.actor_id end;
   v_token:=case item when 1 then r.id when 2 then r.wrestling_id else r.other_team_id end;
   v_team:=case item when 1 then r.team_id when 3 then r.other_team_id else null end;
   product:='com.damonmele.wrestlingmanager.'||case when item=2 then 'familyvideo.monthly' else 'teampro.monthly' end;
   original:='9'||item::text||floor(extract(epoch from r.created_at)*1000000)::text;
   snap:=jsonb_build_object('environment','Sandbox','userID',who,'teamID',v_team,
    'familyOwnerID',case when item=2 then who else null end,'originalTransactionID',original,
    'transactionID',original,'appAccountToken',v_token,'productID',product,
    'plan',case when item=2 then 'family_video_month' else 'team_pro_month' end,
    'status',1,'snapshotSignedAt',n,'expiresAt',n+3600000,'revokedAt',null,'graceExpiresAt',null);
   insert into wm_billing.intents(token,user_id,product_id,scope,team_id,family_owner_id,created_at,bound_original_id)
    values(v_token,who,product,case when item=2 then 'family' else 'team' end,v_team,case when item=2 then who else null end,n,original);
   insert into wm_billing.subscriptions values('Sandbox',original,v_token,who,case when item=2 then 'family' else 'team' end,
    v_team,case when item=2 then who else null end,snap);
   insert into wm_billing.deliveries(environment,transaction_id,original_id) values('Sandbox',original,original);
   insert into wm_billing.notification_inbox(environment,notification_id,original_id,token,evidence)
    values('Sandbox',v_token,original,v_token,snap||jsonb_build_object('bundleID','com.damonmele.wrestlingmanager'));
   if v_team is not null then
    insert into wm_billing.team_paid_remainders values(wm_billing.remainder_binding('Sandbox',original,v_token),v_team,'Sandbox','team_pro_month',n+3600000,null,n);
   end if;
  end loop;
  -- Include a notification received before an unpaid purchase was delivered.
  insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at)
   values(r.profile_id,r.actor_id,'com.damonmele.wrestlingmanager.teampro.monthly','team',r.team_id,n);
  insert into wm_billing.notification_inbox(environment,notification_id,original_id,token,evidence)
   values('Sandbox',r.profile_id,'94'||floor(extract(epoch from r.created_at)*1000000)::text,r.profile_id,'{}');
  update private.scoped_deletion_acceptance_runs set result=coalesce(result,'{}')||'{"billing_seeded":true}' where id=r.id;
  return '{"billing_seeded":true}';
 elsif p_action='verify' then
  if not exists(select 1 from private.scoped_deletion_jobs where id=r.job_id and state='completed') then raise exception 'COMPLETED_FIXTURE_REQUIRED';end if;
  v_result:=jsonb_build_object(
   'billing_actor_absent',not exists(select 1 from wm_billing.intents where user_id=r.actor_id)
    and not exists(select 1 from wm_billing.subscriptions where user_id=r.actor_id)
    and not exists(select 1 from wm_billing.team_bindings where user_id=r.actor_id)
    and not exists(select 1 from wm_billing.family_coverage where user_id=r.actor_id),
   'billing_inbox_absent',not exists(select 1 from wm_billing.notification_inbox where token=any(array[r.id,r.wrestling_id,r.profile_id])),
   'billing_deliveries_absent',not exists(select 1 from wm_billing.deliveries where environment='Sandbox'
    and original_id=any(array['91'||floor(extract(epoch from r.created_at)*1000000)::text,'92'||floor(extract(epoch from r.created_at)*1000000)::text])),
   'billing_selected_team_absent',not exists(select 1 from wm_billing.team_paid_remainders where team_id=r.team_id),
   'billing_other_preserved',exists(select 1 from wm_billing.team_bindings where user_id=r.retained_id and team_id=r.other_team_id)
    and exists(select 1 from wm_billing.intents where token=r.other_team_id and user_id=r.retained_id)
    and exists(select 1 from wm_billing.subscriptions where token=r.other_team_id and user_id=r.retained_id)
    and exists(select 1 from wm_billing.family_coverage where user_id=r.retained_id and athlete_profile_id=r.profile_id)
    and exists(select 1 from wm_billing.notification_inbox where token=r.other_team_id)
    and exists(select 1 from wm_billing.deliveries where environment='Sandbox' and original_id='93'||floor(extract(epoch from r.created_at)*1000000)::text)
    and exists(select 1 from wm_billing.team_paid_remainders where team_id=r.other_team_id));
  if exists(select 1 from jsonb_each(v_result) x where x.value<>'true'::jsonb) then raise exception 'BILLING_HOSTED_PRESERVATION_FAILED';end if;
  return v_result;
 elsif p_action='cleanup' then
  if r.state<>'verified' or r.result->>'billing_other_preserved' is distinct from 'true'
   or not exists(select 1 from auth.users where id=r.retained_id and raw_app_meta_data->>'scoped_deletion_acceptance'=r.id::text and email like '%@tests.example.invalid')
  then raise exception 'VERIFIED_BILLING_FIXTURE_REQUIRED';end if;
  delete from wm_billing.notification_inbox where token=r.other_team_id;
  delete from wm_billing.deliveries where environment='Sandbox' and original_id='93'||floor(extract(epoch from r.created_at)*1000000)::text;
  delete from wm_billing.subscriptions where token=r.other_team_id and user_id=r.retained_id;
  delete from wm_billing.intents where token=r.other_team_id and user_id=r.retained_id;
  delete from wm_billing.team_bindings where user_id=r.retained_id and team_id=r.other_team_id;
  delete from wm_billing.family_coverage where user_id=r.retained_id and athlete_profile_id=r.profile_id;
  delete from wm_billing.team_paid_remainders where team_id=r.other_team_id;
  return '{"billing_fixtures_cleaned":true}';
 end if;
 raise exception 'INVALID_BILLING_ACCEPTANCE_ACTION';
end $$;
create function public.scoped_deletion_billing_acceptance(p_action text,p_run uuid,p_hash text)
returns jsonb language sql security invoker set search_path='' as $$select private.scoped_deletion_billing_acceptance(p_action,p_run,p_hash)$$;
revoke all on function private.scoped_deletion_billing_acceptance(text,uuid,text),public.scoped_deletion_billing_acceptance(text,uuid,text) from public,anon,authenticated,wm_billing_runtime;
grant execute on function private.scoped_deletion_billing_acceptance(text,uuid,text),public.scoped_deletion_billing_acceptance(text,uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
