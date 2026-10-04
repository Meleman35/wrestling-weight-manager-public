-- DRAFT ONLY. Not a deployable migration. No client/backend grants or public RPC.
-- Requires deletion-catalog/merge integration and verified billing/evidence adapters.
create schema remote_reporting;
revoke all on schema remote_reporting from public, anon, authenticated;
create table remote_reporting.programs (
 id text primary key, kind text not null check(kind in ('network','tournament')),
 event_id text, active boolean not null default false,
 covered_until timestamptz, coverage_revoked boolean not null default true,
 check((kind='tournament' and event_id is not null) or (kind='network' and event_id is null))
);
create table remote_reporting.windows (
 id text primary key, program_id text not null references remote_reporting.programs(id),
 event_id text, opens_at timestamptz not null, closes_at timestamptz not null,
 time_zone text not null, sync_grace_ms bigint not null default 0 check(sync_grace_ms between 0 and 604800000),
 active boolean not null default false, event_date date,
 unique(program_id,id), check(opens_at<closes_at),
 check(event_id is null or (event_date is not null
  and opens_at=((event_date-1)::timestamp at time zone time_zone)
  and closes_at=((event_date+1)::timestamp at time zone time_zone)))
);
create table remote_reporting.club_enrollments (
 program_id text not null references remote_reporting.programs(id), club_id text not null,
 active boolean not null default false, primary key(program_id,club_id)
);
create table remote_reporting.assignments (
 program_id text not null references remote_reporting.programs(id), user_id uuid not null references auth.users(id),
 club_id text not null, role text not null check(role in ('operator','director','club_reader')),
 active boolean not null default false, primary key(program_id,user_id,club_id,role)
);
create table remote_reporting.roster (
 program_id text not null, window_id text not null, club_id text not null, athlete_id text not null,
 active boolean not null default false, remote_consent boolean not null default false,
 primary key(program_id,window_id,club_id,athlete_id),
 foreign key(program_id,window_id) references remote_reporting.windows(program_id,id),
 foreign key(program_id,club_id) references remote_reporting.club_enrollments(program_id,club_id)
);
create table remote_reporting.evidence (
 id text primary key, program_id text not null references remote_reporting.programs(id),
 binding jsonb not null check(jsonb_typeof(binding)='object'),
 private_object_key text not null unique, digest text not null,
 verified boolean not null default false, expires_at timestamptz not null,
 notice_accepted boolean not null default false, settled boolean not null default false,
 source text not null check(source='camera'), byte_count bigint not null check(byte_count between 1 and 5242880),
 revoked boolean not null default false
);
create table remote_reporting.submissions (
 submission_id text primary key, program_id text not null, window_id text not null,
 club_id text not null, athlete_id text not null, operator_id uuid not null references auth.users(id),
 evidence_id text not null unique references remote_reporting.evidence(id),
 record jsonb not null, payload_hash text not null check(length(payload_hash)=64),
 receipt_id uuid not null unique default gen_random_uuid(), received_at timestamptz not null default clock_timestamp(),
 unique(program_id,window_id,club_id,athlete_id),
 foreign key(program_id,window_id,club_id,athlete_id) references remote_reporting.roster(program_id,window_id,club_id,athlete_id)
);
create index remote_submission_report on remote_reporting.submissions(program_id,window_id,club_id,athlete_id);
create index remote_assignment_user on remote_reporting.assignments(user_id,program_id);
create index remote_evidence_expiry on remote_reporting.evidence(expires_at);
do $$declare t text;begin
 foreach t in array array['programs','windows','club_enrollments','assignments','roster','evidence','submissions'] loop
 execute format('alter table remote_reporting.%I enable row level security',t);
 execute format('revoke all on remote_reporting.%I from public,anon,authenticated',t);
 end loop;
end$$;
-- Uses the existing production personal-account and deletion controls.
-- No public RPC. The private backend needs explicit helper/table privileges.
create function remote_reporting.personal_access(p_user uuid) returns boolean
language sql security invoker set search_path='' as $$
 select p_user is not null and private.board_personal(p_user)
 and not exists(select 1 from private.scoped_deletion_jobs j
  where (j.actor_id=p_user and j.state not in ('cancelled','completed'))
   or (j.personal and j.sealed_at is not null and
    j.subject_hash=encode(sha256(convert_to(p_user::text,'UTF8')),'hex')))
$$;
revoke all on function remote_reporting.personal_access(uuid) from public,anon,authenticated;
create function remote_reporting.lock_personal_access(p_user uuid) returns void
language plpgsql security invoker set search_path='' as $$
begin
 if p_user is null then raise exception 'Personal account unavailable';end if;
 -- Identical key and lock order to private.scoped_deletion_begin.
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,91347));
 if not remote_reporting.personal_access(p_user) then raise exception 'Personal account unavailable';end if;
end$$;
revoke all on function remote_reporting.lock_personal_access(uuid) from public,anon,authenticated;
-- Invoker, restricted schema. Server must supply validated Auth session separately
-- from native generation. SQL rechecks the active session at acceptance.
create function remote_reporting.accept(p_user uuid,p_session uuid,p_record jsonb,p_hash text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare p remote_reporting.programs%rowtype; w remote_reporting.windows%rowtype;
 e remote_reporting.evidence%rowtype; prior remote_reporting.submissions%rowtype;
 captured timestamptz; photo timestamptz; accepted_at timestamptz; expected_binding jsonb;
begin
 if p_record is null or jsonb_typeof(p_record)<>'object' or octet_length(p_record::text)>12000 or p_hash is null or p_hash!~'^[a-f0-9]{64}$' then raise exception 'Invalid payload';end if;
 perform remote_reporting.lock_personal_access(p_user);
 -- Locks serialize acceptance for a program and keep mutable authorization rows
 -- stable until commit. Provision/revocation adapters must use normal row locks.
 select * into p from remote_reporting.programs where id=p_record->>'programId' for update;
 if not found or not p.active or p.coverage_revoked or p.covered_until is null or p.covered_until<=clock_timestamp() then raise exception 'Coverage unavailable';end if;
 perform 1 from auth.users u join auth.sessions s on s.user_id=u.id
 where u.id=p_user and s.id=p_session and u.email_confirmed_at is not null and u.deleted_at is null
 and (u.banned_until is null or u.banned_until<=clock_timestamp()) and (s.not_after is null or s.not_after>clock_timestamp()) for share of u,s;
 if not found or p_record->>'operatorId' is distinct from p_user::text then raise exception 'Session unavailable';end if;
 perform 1 from remote_reporting.assignments where program_id=p.id and user_id=p_user and club_id=p_record->>'clubId' and role='operator' and active for share;
 if not found then raise exception 'Operator unavailable';end if;
 perform 1 from remote_reporting.club_enrollments where program_id=p.id and club_id=p_record->>'clubId' and active for share;
 if not found then raise exception 'Club unavailable';end if;
 select * into w from remote_reporting.windows where id=p_record->>'windowId' and program_id=p.id for share;
 if not found or not w.active or (p.kind='tournament' and (w.event_id is distinct from p.event_id or p_record->>'eventId' is distinct from p.event_id)) or p_record->>'kind' is distinct from p.kind then raise exception 'Window unavailable';end if;
 perform 1 from remote_reporting.roster where program_id=p.id and window_id=w.id and club_id=p_record->>'clubId' and athlete_id=p_record->>'athleteId' and active and remote_consent for share;
 if not found then raise exception 'Roster consent unavailable';end if;
 captured:=(p_record->>'capturedAt')::timestamptz;
 if captured is null or captured+interval '240 hours'<=clock_timestamp() then raise exception 'Capture retention expired';end if;
 select * into prior from remote_reporting.submissions where submission_id=p_record->>'submissionId';
 if found then
 if prior.payload_hash<>p_hash or prior.record<>p_record then raise exception 'Idempotency conflict';end if;
 return jsonb_build_object('submissionId',prior.submission_id,'receiptId',prior.receipt_id,'status','submitted','receivedAt',prior.received_at);
 end if;
 captured:=(p_record->>'capturedAt')::timestamptz;photo:=(p_record->>'photoCapturedAt')::timestamptz;
 accepted_at:=clock_timestamp();
 if captured is null or photo is null or captured<w.opens_at or photo>=w.closes_at or photo<captured or photo-captured>interval '30 seconds' or photo>accepted_at or accepted_at>w.closes_at+w.sync_grace_ms*interval '1 millisecond' then raise exception 'Capture deadline unavailable';end if;
 if p_record->>'method' is null or p_record->>'method' not in ('qr','nfc') or p_record->>'unit' is distinct from 'lb' or p_record->>'weight' is null or (p_record->>'weight')::numeric not between 0.01 and 800 then raise exception 'Invalid scale reading';end if;
 select * into e from remote_reporting.evidence where id=p_record->>'evidenceId' and program_id=p.id for share;
 expected_binding:=p_record-array['submissionId','evidenceId','eventId','kind','evidenceDigest'];
 if not found or not e.verified or e.revoked or not e.notice_accepted or not e.settled or e.expires_at<=accepted_at or e.digest is distinct from p_record->>'evidenceDigest' or e.binding<>expected_binding then raise exception 'Evidence unavailable';end if;
 insert into remote_reporting.submissions(submission_id,program_id,window_id,club_id,athlete_id,operator_id,evidence_id,record,payload_hash,received_at)
 values(p_record->>'submissionId',p.id,w.id,p_record->>'clubId',p_record->>'athleteId',p_user,e.id,p_record,p_hash,accepted_at) returning * into prior;
 return jsonb_build_object('submissionId',prior.submission_id,'receiptId',prior.receipt_id,'status','submitted','receivedAt',prior.received_at);
end$$;
revoke all on function remote_reporting.accept(uuid,uuid,jsonb,text) from public,anon,authenticated;
