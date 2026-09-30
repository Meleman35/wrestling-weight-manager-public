begin;
create function private.scoped_deletion_acceptance_inspect(p_run uuid,p_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.scoped_deletion_acceptance_runs%rowtype;j private.scoped_deletion_jobs%rowtype;
begin
 if current_setting('role',true)<>'service_role' then raise sqlstate '42501' using message='SERVICE_ONLY';end if;
 select * into r from private.scoped_deletion_acceptance_runs where id=p_run and token_hash=p_hash and expires_at>now();
 if not found or r.state not in ('running','verified') then raise sqlstate '42501' using message='ACCEPTANCE_NOT_AUTHORIZED';end if;
 select * into j from private.scoped_deletion_jobs where id=r.job_id;
 if not found or j.subject_hash<>encode(sha256(convert_to(r.actor_id::text,'UTF8')),'hex') then raise exception 'ACCEPTANCE_JOB_MISMATCH';end if;
 return jsonb_build_object('jobId',j.id,'receiptHash',j.receipt_hash,'actor',r.actor_id,'retained',r.retained_id,'child',r.child_id,
 'files',jsonb_build_array(
 jsonb_build_object('bucket','profile-photos','path',r.actor_id::text||'/'||r.id||'.jpg','remove',true),
 jsonb_build_object('bucket','wrestling-profile-photos','path',r.wrestling_id::text||'/'||r.id||'.jpg','remove',true),
 jsonb_build_object('bucket','communication-media','path',r.team_id::text||'/'||r.id||'.jpg','remove',true),
 jsonb_build_object('bucket','profile-photos','path',r.retained_id::text||'/'||r.id||'.jpg','remove',false)));
end $$;
create function public.scoped_deletion_acceptance_inspect(p_run uuid,p_hash text) returns jsonb
language sql security invoker set search_path='' as $$select private.scoped_deletion_acceptance_inspect(p_run,p_hash)$$;
revoke all on function private.scoped_deletion_acceptance_inspect(uuid,text),public.scoped_deletion_acceptance_inspect(uuid,text) from public,anon,authenticated;
grant execute on function private.scoped_deletion_acceptance_inspect(uuid,text),public.scoped_deletion_acceptance_inspect(uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
