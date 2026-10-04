-- Private review candidate. Apply after remote-weighins.sql; include all tables
-- in scoped deletion before deployment. Canonical ownership is server provisioned.
create table private.remote_program_organizations (
 program_id text primary key references remote_reporting.programs(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade
);
create table private.remote_director_trials (
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 started_at timestamptz not null,expires_at timestamptz not null,
 revoked boolean not null default false,
 check(expires_at=(((started_at at time zone 'UTC')+interval '1 month') at time zone 'UTC'))
);
create table private.remote_trial_tournaments (
 organization_id uuid not null references private.remote_director_trials(organization_id) on delete cascade,
 event_id text not null,slot smallint not null check(slot between 1 and 4),
 primary key(organization_id,event_id),unique(organization_id,slot)
);
do $$declare t text;begin
 foreach t in array array['remote_program_organizations','remote_director_trials','remote_trial_tournaments'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end$$;
-- Shared reader used by report preflight, evidence and atomic acceptance. Paid
-- coverage and trial coverage have independent revocation; active=false disables
-- the entire program. Locks keep trial revocation stable through the transaction.
create or replace function remote_reporting.program_coverage_until(p_program text) returns timestamptz
language plpgsql security invoker set search_path='' as $$
declare p remote_reporting.programs%rowtype;o uuid;t private.remote_director_trials%rowtype;
begin
 select * into p from remote_reporting.programs where id=p_program for share;
 if not found or not p.active then return null;end if;
 if not p.coverage_revoked and p.covered_until>clock_timestamp() then return p.covered_until;end if;
 if p.kind<>'tournament' then return null;end if;
 select organization_id into o from private.remote_program_organizations where program_id=p.id for share;
 if not found then return null;end if;
 select * into t from private.remote_director_trials where organization_id=o for share;
 if not found or t.revoked or t.started_at>clock_timestamp() or t.expires_at<=clock_timestamp() then return null;end if;
 perform 1 from private.remote_trial_tournaments where organization_id=o and event_id=p.event_id for share;
 if not found then return null;end if;
 return t.expires_at;
end$$;
revoke all on function remote_reporting.program_coverage_until(text) from public,anon,authenticated;
