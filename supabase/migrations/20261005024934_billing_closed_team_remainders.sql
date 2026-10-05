-- A team being erased has no paid period to preserve. Its sealed remainder
-- must be left untouched until the ordinary record-erasure phase removes it.
begin;
set local lock_timeout='5s';
lock table private.scoped_deletion_jobs in exclusive mode;
do $$declare source text; needle text:=E'   order by (n.evidence->>\'snapshotSignedAt\')::bigint,n.notification_id loop';begin
 source:=pg_get_functiondef('wm_billing.prepare_deletion(uuid,uuid)'::regprocedure);
 if encode(sha256(convert_to(source,'UTF8')),'hex')<>'1a67f114583567e747c73e14d3ed174c63cc49ae54c86f8ecb3023e58365e6a6'
  or (length(source)-length(replace(source,needle,'')))<>length(needle) then raise exception 'BILLING_PREPARATION_REVIEW_REQUIRED';end if;
 execute replace(source,needle,E'   where not(r.team_id=any(j.team_ids)) and not exists(\n    select 1 from public.teams t where t.id=r.team_id and t.organization_id=any(j.organization_ids))\n'||needle);
end $$;
commit;
