-- Read-only operator report after BOTH draft migrations are installed in isolation.
-- Include unqueued requests so intake cannot silently outpace the worker.
-- No email, subject UUID, object key, provider body or credentials are returned.
select r.id as request_id, r.status, r.requested_at, r.deadline_at,
  coalesce(j.state,'unqueued') as worker_state, j.phase, j.attempts,
  j.next_attempt_at, j.last_error_code,
  r.deadline_at < now() as overdue,
  r.deadline_at < now()+interval '3 days' as deadline_within_three_days
from public.account_deletion_requests r
left join private.account_deletion_jobs j on j.id=r.id
where r.status <> 'completed'
order by r.deadline_at, r.requested_at;
