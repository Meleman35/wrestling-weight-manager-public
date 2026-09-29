-- DISABLED DRAFT. Queue/ledger only; does not revoke access or erase user records.
-- No production executor is supplied until every data/access/provider adapter is reviewed.
alter table public.account_deletion_settings
  add column fulfillment_enabled boolean not null default false,
  add column policy_version text,
  add column inventory_sha256 text check (inventory_sha256 ~ '^[a-f0-9]{64}$'),
  add constraint account_deletion_fulfillment_config check
    (not fulfillment_enabled or (policy_version is not null and inventory_sha256 is not null));

create table private.account_deletion_jobs (
  id uuid primary key references public.account_deletion_requests(id) on delete restrict,
  -- Deliberately no Auth FK: retries must survive Auth removal. Cleared on completion.
  subject_id uuid,
  policy_version text not null,
  inventory_sha256 text not null check (inventory_sha256 ~ '^[a-f0-9]{64}$'),
  phase integer not null default 0 check (phase between 0 and 8),
  state text not null default 'pending' check (state in ('pending','running','retry','blocked','completed')),
  attempts integer not null default 0,
  lease_token uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  last_error_code text check (last_error_code in ('provider_unavailable','verification_failed','scope_unreviewed','schema_changed','adapter_failure')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  check ((state = 'completed') = (phase = 8 and completed_at is not null and subject_id is null)),
  check ((state = 'running') = (lease_token is not null and lease_until is not null))
);
create index account_deletion_jobs_due on private.account_deletion_jobs(next_attempt_at, created_at)
  where state <> 'completed';
create table private.account_deletion_objects (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references private.account_deletion_jobs(id) on delete restrict,
  provider text not null check (provider in ('supabase','video')),
  bucket text not null check (length(bucket) between 1 and 128),
  object_key text not null check (length(object_key) between 1 and 2048),
  removed_at timestamptz,
  unique(job_id, provider, bucket, object_key)
);
alter table private.account_deletion_jobs enable row level security;
alter table private.account_deletion_objects enable row level security;
revoke all on private.account_deletion_jobs, private.account_deletion_objects from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, insert, update, delete on private.account_deletion_jobs, private.account_deletion_objects to service_role;
grant select on public.athlete_guardians to service_role;
grant select,delete on private.conversation_reviewers,private.parent_browser_verifications to service_role;
grant select,update on private.parent_browser_permissions,private.parent_browser_links to service_role;

create function private.account_deletion_enqueue(p_request_id uuid, p_policy text, p_inventory text)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare r public.account_deletion_requests%rowtype;
begin
  if not exists(select 1 from public.account_deletion_settings where id=1 and fulfillment_enabled
      and policy_version=p_policy and inventory_sha256=p_inventory) then
    raise exception 'Fulfillment disabled or release mismatch' using errcode='55000';
  end if;
  select * into r from public.account_deletion_requests where id=p_request_id for update;
  if not found or r.user_id is null or r.status='completed' then
    raise exception 'No eligible request' using errcode='22023';
  end if;
  insert into private.account_deletion_jobs(id,subject_id,policy_version,inventory_sha256)
    values(r.id,r.user_id,p_policy,p_inventory) on conflict(id) do nothing;
  return r.id;
end $$;

create function private.account_deletion_claim(p_policy text, p_inventory text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare j private.account_deletion_jobs%rowtype;
begin
  if not exists(select 1 from public.account_deletion_settings where id=1 and fulfillment_enabled
      and policy_version=p_policy and inventory_sha256=p_inventory) then return null; end if;
  select * into j from private.account_deletion_jobs
    where policy_version=p_policy and inventory_sha256=p_inventory
      and next_attempt_at <= clock_timestamp()
      and (state in ('pending','retry') or (state='running' and lease_until<=clock_timestamp()))
    order by next_attempt_at,created_at for update skip locked limit 1;
  if not found then return null; end if;
  update private.account_deletion_jobs set state='running',lease_token=gen_random_uuid(),
    lease_until=clock_timestamp()+interval '60 seconds',attempts=attempts+1,updated_at=clock_timestamp()
    where id=j.id returning * into j;
  return to_jsonb(j);
end $$;

-- Every checkpoint locks the job and rejects expired/replaced leases and wrong phases.
-- Service workers are trusted: they must supply independently verified adapter evidence.
create function private.account_deletion_checkpoint(
  p_job uuid, p_lease uuid, p_phase integer, p_action text, p_data jsonb default '{}'
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare j private.account_deletion_jobs%rowtype; flags text[]; flag text; item jsonb; guardian_ids uuid[];
begin
  select * into j from private.account_deletion_jobs where id=p_job for update;
  if not found or j.state<>'running' or j.lease_token is distinct from p_lease
      or j.lease_until<=clock_timestamp() or j.phase is distinct from p_phase then
    raise exception 'Worker lease lost' using errcode='40001';
  end if;
  if p_action='fail' then
    if p_data->>'code' not in ('provider_unavailable','verification_failed','scope_unreviewed','schema_changed','adapter_failure')
        or p_data->>'code' is null then raise exception 'Invalid failure code' using errcode='22023'; end if;
    update private.account_deletion_jobs set
      state=case when p_data->'retry'='true'::jsonb then 'retry' else 'blocked' end,
      next_attempt_at=clock_timestamp()+make_interval(secs => least(3600,30*power(2,least(attempts-1,7)))::int),
      lease_token=null,lease_until=null,last_error_code=p_data->>'code',updated_at=clock_timestamp()
      where id=j.id returning * into j;
    return to_jsonb(j);
  end if;
  if not exists(select 1 from public.account_deletion_settings where id=1 and fulfillment_enabled
      and policy_version=j.policy_version and inventory_sha256=j.inventory_sha256) then
    raise exception 'Fulfillment paused' using errcode='55000';
  end if;
  if p_action='revoke_related_access' and j.phase=1 then
    -- Account identity only: never infer guardianship from a caller-supplied email.
    -- Include coach-created verification, whose dependent permissions otherwise outlive it.
    select coalesce(array_agg(distinct g.id),'{}'::uuid[]) into guardian_ids
      from public.athlete_guardians g left join private.parent_browser_verifications v on v.guardian_id=g.id
      where g.guardian_user_id=j.subject_id or v.verified_by=j.subject_id;
    delete from private.conversation_reviewers where user_id=j.subject_id or approved_by=j.subject_id;
    update private.parent_browser_permissions set mode='revoked' where guardian_id=any(guardian_ids);
    update private.parent_browser_links set revoked_at=coalesce(revoked_at,clock_timestamp()) where guardian_id=any(guardian_ids);
    delete from private.parent_browser_verifications where guardian_id=any(guardian_ids);
    -- Preserve athletes, other guardian relationships, global settings and unrelated assignments.
    -- This is capability revocation only; retained personal fields are still part of phase 4.
    return to_jsonb(j);
  elsif p_action='yield' then
    update private.account_deletion_jobs set state='retry',next_attempt_at=clock_timestamp(),
      lease_token=null,lease_until=null,updated_at=clock_timestamp() where id=j.id returning * into j;
    return to_jsonb(j);
  elsif p_action='renew' then
    update private.account_deletion_jobs set lease_until=clock_timestamp()+interval '60 seconds'
      where id=j.id returning * into j;
    return to_jsonb(j);
  elsif p_action='object_done' and j.phase=3 then
    if p_data->'absent' is distinct from 'true'::jsonb then
      raise exception 'Object absence unverified' using errcode='22023'; end if;
    update private.account_deletion_objects set removed_at=clock_timestamp()
      where id=(p_data->>'id')::uuid and job_id=j.id;
    if not found then raise exception 'Object not in job' using errcode='22023'; end if;
    return to_jsonb(j);
  elsif p_action is distinct from 'advance' then raise exception 'Invalid action' using errcode='22023'; end if;

  flags := case j.phase
    when 0 then array['scope_reviewed','schema_current','continuity_reviewed','retention_reviewed','confirmation_prepared']
    when 1 then array['sign_in_blocked','refresh_sessions_revoked','stale_tokens_blocked','managed_access_revoked','deliveries_stopped']
    when 2 then array['inventory_complete','shared_ownership_reviewed']
    when 3 then array['objects_absent']
    when 4 then array['personal_records_erased','shared_records_preserved']
    when 5 then array['auth_absent']
    when 6 then array['auth_absent','personal_records_absent','external_objects_absent','shared_records_preserved','restore_ledger_recorded']
    when 7 then array['confirmation_delivered'] end;
  foreach flag in array flags loop
    if p_data->flag is distinct from 'true'::jsonb then
      raise exception 'Required verification missing: %',flag using errcode='22023'; end if;
  end loop;
  if j.phase=2 then
    if jsonb_typeof(p_data->'objects') is distinct from 'array'
        or jsonb_array_length(p_data->'objects')>10000 then
      raise exception 'Invalid object inventory' using errcode='22023'; end if;
    for item in select value from jsonb_array_elements(p_data->'objects') loop
      if item->>'subject_id' is distinct from j.subject_id::text
          or item->>'disposition' is distinct from 'erase_personal_content'
          or item->>'bucket' in ('.','..') or item->>'bucket' ~ '[/%\\]'
          or item->>'key' ~ '(^/|(^|/)\.\.(/|$)|[\\])'
          or jsonb_typeof(item->'key') is distinct from 'string' then
        raise exception 'Unreviewed object scope' using errcode='22023'; end if;
      insert into private.account_deletion_objects(job_id,provider,bucket,object_key)
        values(j.id,item->>'provider',item->>'bucket',item->>'key');
    end loop;
  elsif j.phase=3 and exists(select 1 from private.account_deletion_objects where job_id=j.id and removed_at is null) then
    raise exception 'Objects remain' using errcode='55000';
  end if;
  if j.phase=7 then
    delete from private.account_deletion_objects where job_id=j.id;
    update public.account_deletion_requests set status='completed',completed_at=clock_timestamp(),user_id=null where id=j.id;
    update private.account_deletion_jobs set phase=8,state='completed',subject_id=null,
      lease_token=null,lease_until=null,last_error_code=null,completed_at=clock_timestamp(),updated_at=clock_timestamp()
      where id=j.id returning * into j;
  else
    update public.account_deletion_requests set status='processing' where id=j.id;
    update private.account_deletion_jobs set phase=phase+1,last_error_code=null,updated_at=clock_timestamp()
      where id=j.id returning * into j;
  end if;
  return to_jsonb(j);
end $$;
revoke all on function private.account_deletion_enqueue(uuid,text,text),
  private.account_deletion_claim(text,text),private.account_deletion_checkpoint(uuid,uuid,integer,text,jsonb)
  from public,anon,authenticated;
grant execute on function private.account_deletion_enqueue(uuid,text,text),
  private.account_deletion_claim(text,text),private.account_deletion_checkpoint(uuid,uuid,integer,text,jsonb)
  to service_role;
comment on table private.account_deletion_jobs is
  'Disabled fulfillment draft. Service-only durable phases; no production erasure adapters or access gate installed.';
