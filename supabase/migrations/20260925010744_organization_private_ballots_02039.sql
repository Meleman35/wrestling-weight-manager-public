-- 0.20.39. Application-secret ballots: participation and aggregate counters only.
-- No individual choice rows, cast timestamps, choice receipts, or cast audit events.
-- Database/WAL/log administrators remain outside this application's secrecy boundary.
alter table private.organization_meetings add column is_test boolean not null default false;
create function private.vote039_released() returns boolean language sql stable set search_path='' as $$select false;$$;
create table private.organization_secret_rounds (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 meeting_id uuid not null references private.organization_meetings(id),
 series_id uuid not null, round_number integer not null check(round_number>0),
 prior_id uuid unique references private.organization_secret_rounds(id),
 motion text not null check(length(trim(motion)) between 1 and 8000), mover text not null default '', seconder text not null default '',
 electorate text not null check(electorate in ('board','affiliates')),
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),
 policy jsonb not null default '{}', change_reason text not null default '',
 eligible_count integer not null default 0, attendance_count integer not null default 0,
 result jsonb, revision integer not null default 1,
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 opened_at timestamptz, closed_at timestamptz,
 unique(series_id,round_number)
);
create index organization_secret_rounds_org_meeting on private.organization_secret_rounds(organization_id,meeting_id,status);
create table private.organization_secret_participants (
 round_id uuid not null references private.organization_secret_rounds(id),
 entity_id uuid not null, snapshot_name text not null, present boolean not null,
 delegate_user_id uuid references public.profiles(id), submitted boolean not null default false,
 primary key(round_id,entity_id), unique(round_id,delegate_user_id)
);
create index organization_secret_participants_user on private.organization_secret_participants(delegate_user_id,round_id);
create table private.organization_secret_delegations (
 round_id uuid not null references private.organization_secret_rounds(id), user_id uuid not null references public.profiles(id), entity_id uuid not null,
 primary key(round_id,user_id), foreign key(round_id,entity_id) references private.organization_secret_participants(round_id,entity_id)
);
-- Only aggregate counters live here. No participant/user/request identifier and
-- no creation/update timestamp is stored alongside an individual choice.
create table private.organization_secret_totals (
 round_id uuid primary key references private.organization_secret_rounds(id),
 yes_count integer not null default 0 check(yes_count>=0),
 no_count integer not null default 0 check(no_count>=0),
 abstain_count integer not null default 0 check(abstain_count>=0)
);
create table private.organization_secret_requests (
 organization_id uuid not null references public.organizations(id), actor_id uuid not null references public.profiles(id), request_id uuid not null,
 fingerprint text not null, result jsonb not null, primary key(organization_id,actor_id,request_id)
);
alter table private.organization_secret_rounds enable row level security;
alter table private.organization_secret_participants enable row level security;
alter table private.organization_secret_delegations enable row level security;
alter table private.organization_secret_totals enable row level security;
alter table private.organization_secret_requests enable row level security;
revoke all on private.organization_secret_rounds,private.organization_secret_participants,private.organization_secret_delegations,
 private.organization_secret_totals,private.organization_secret_requests from public,anon,authenticated;

create function private.vote039_personal() returns boolean language sql stable set search_path='' as $$
 select auth.uid() is not null and private.ops_personal() and private.managed_login_access_ok()
 and exists(select 1 from public.profiles where id=auth.uid())
 and exists(select 1 from auth.sessions se join auth.users u on u.id=se.user_id where se.user_id=auth.uid() and se.id::text=auth.jwt()->>'session_id' and (se.not_after is null or se.not_after>now()) and (u.banned_until is null or u.banned_until<=now()));
$$;
create function private.vote039_adult(u uuid) returns boolean language sql stable set search_path='' as $$
 select u is not null and exists(select 1 from public.profiles where id=u)
 and not exists(select 1 from private.team_logins where user_id=u)
 and not exists(select 1 from public.team_memberships tm join public.athletes a on a.id=tm.athlete_id
   left join public.athlete_private_identity ai on ai.athlete_id=a.id
   where tm.user_id=u and tm.role='athlete' and (coalesce(ai.birth_date,a.birth_date) is null or coalesce(ai.birth_date,a.birth_date)>current_date-interval '18 years'));
$$;
create function private.vote039_candidate(o uuid,u uuid) returns boolean language sql stable set search_path='' as $$
 select private.vote039_adult(u) and (
 private.gov_adult_candidate(o,u)
 or exists(select 1 from public.team_memberships tm join private.ops_links l on l.team_id=tm.team_id where l.organization_id=o and l.approved and tm.user_id=u and tm.active and tm.role in ('head_coach','assistant_coach','manager','parent_guardian'))
 or exists(select 1 from private.organization_affiliate_delegates d join private.organization_affiliates a on a.id=d.affiliate_id where a.organization_id=o and a.status='active' and a.membership_review='confirmed' and d.active and d.user_id=u));
$$;
create function private.vote039_manager(mid uuid) returns boolean language sql stable set search_path='' as $$
 select coalesce((select private.meeting038_leader(m) from private.organization_meetings m where m.id=mid),false);
$$;
create function private.vote039_read(r private.organization_secret_rounds) returns boolean language sql stable set search_path='' as $$
 select private.vote039_manager(r.meeting_id)
 or (r.status<>'draft' and exists(select 1 from private.organization_secret_participants p where p.round_id=r.id and p.delegate_user_id=auth.uid()))
 or (r.status='closed' and private.gov_can_read(r.organization_id) and exists(select 1 from private.organization_meetings m where m.id=r.meeting_id and not m.is_test));
$$;
create function private.vote039_policy(p jsonb) returns jsonb language plpgsql set search_path='' as $$
declare k text; n integer; d integer;
begin
 if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text)>10000 then raise exception 'Record a valid governing policy.';end if;
 if length(trim(coalesce(p->>'governing_rule','')))<3 or length(trim(coalesce(p->>'electronic_authorization','')))<3 then raise exception 'Record the governing rule and authorization for electronic secret voting.';end if;
 foreach k in array array['min_attendance','min_ballots','numerator','denominator'] loop
  if coalesce(p->>k,'') !~ '^[0-9]{1,4}$' or (p->>k)::int<1 then raise exception 'Set positive whole-number quorum and threshold values.';end if;
 end loop;
 n:=(p->>'numerator')::int;d:=(p->>'denominator')::int;
 if n>d or (n=d and p->>'comparison'='gt') then raise exception 'Approval threshold cannot exceed all voters.';end if;
 if coalesce(p->>'comparison','') not in ('gt','gte') or coalesce(p->>'basis','') not in ('votes_cast','electorate') or coalesce(p->>'abstentions','') not in ('exclude','include') or coalesce(p->>'tie','') not in ('not_passed','no_decision','new_round') then raise exception 'Explicitly choose majority, abstention, and tie policies.';end if;
 if p->>'basis'='electorate' and p->>'abstentions'<>'include' then raise exception 'An entire-electorate threshold includes abstentions and nonvoters in its denominator.';end if;
 return jsonb_build_object('governing_rule',left(p->>'governing_rule',4000),'electronic_authorization',left(p->>'electronic_authorization',4000),
  'min_attendance',(p->>'min_attendance')::int,'min_ballots',(p->>'min_ballots')::int,'numerator',n,'denominator',d,'comparison',p->>'comparison','basis',p->>'basis','abstentions',p->>'abstentions','tie',p->>'tie');
end $$;

create function private.vote039_projection(r private.organization_secret_rounds) returns jsonb language plpgsql stable set search_path='' as $$
declare result jsonb; manager boolean=private.vote039_manager(r.meeting_id); mine private.organization_secret_participants%rowtype;
begin
 if not private.vote039_read(r) then raise sqlstate '42501' using message='Ballot access required.';end if;
 select * into mine from private.organization_secret_participants where round_id=r.id and delegate_user_id=auth.uid();
 result:=jsonb_build_object('id',r.id,'meeting_id',r.meeting_id,'meeting_title',(select title from private.organization_meetings where id=r.meeting_id),
 'is_test',(select is_test from private.organization_meetings where id=r.meeting_id),'round_number',r.round_number,'prior_id',r.prior_id,'motion',r.motion,'mover',r.mover,'seconder',r.seconder,'electorate',r.electorate,'status',r.status,'policy',r.policy,
 'revision',r.revision,'eligible_count',r.eligible_count,'attendance_count',r.attendance_count,'can_manage',manager,'change_reason',r.change_reason,
 'my_ballot',case when mine.entity_id is null then null else jsonb_build_object('label',mine.snapshot_name,'submitted',mine.submitted,'can_vote',r.status='open' and mine.present and not mine.submitted and private.vote039_adult(auth.uid())) end,
 'result',case when r.status='closed' then r.result else null end);
 if manager then result:=result||jsonb_build_object('participants',coalesce((select jsonb_agg(jsonb_build_object('entity_id',p.entity_id,'name',p.snapshot_name,'present',p.present,'delegate_user_id',p.delegate_user_id,'delegate_name',pr.display_name,'submitted',p.submitted) order by p.snapshot_name,p.entity_id) from private.organization_secret_participants p left join public.profiles pr on pr.id=p.delegate_user_id where p.round_id=r.id),'[]'));end if;
 return result;
end $$;

create function private.vote039_request(q jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); o uuid=nullif(q->>'organization_id','')::uuid; act text=q->>'action';
 bid uuid=nullif(q->>'id','')::uuid; mid uuid=nullif(q->>'meeting_id','')::uuid; rid uuid=nullif(q->>'request_id','')::uuid;
 r private.organization_secret_rounds%rowtype; prior_round private.organization_secret_rounds%rowtype; m private.organization_meetings%rowtype;
 p private.organization_secret_participants%rowtype; t private.organization_secret_totals%rowtype; replay private.organization_secret_requests%rowtype;
 x jsonb; source jsonb; doc jsonb; result jsonb; person uuid; entity uuid; k text; n integer; den integer; votes integer; yes_votes integer; no_votes integer; abstain_votes integer; outcome text;
begin
 if not private.vote039_personal() then raise sqlstate '42501' using message='Use your personal account.';end if;
 if act='ballot_inbox' then return coalesce((select jsonb_agg(jsonb_build_object('organization_id',b.organization_id,'organization_name',z.name,'id',b.id,'motion',b.motion,'status',b.status,'is_test',mm.is_test,'submitted',sp.submitted) order by b.created_at desc,b.id) from private.organization_secret_rounds b join private.organization_secret_participants sp on sp.round_id=b.id join public.organizations z on z.id=b.organization_id join private.organization_meetings mm on mm.id=b.meeting_id where sp.delegate_user_id=uid and b.status in ('open','closed','cancelled')),'[]');end if;
 if o is null or octet_length(q::text)>160000 then raise exception 'Invalid ballot request.';end if;
 if act='ballot_context' then
  if not private.gov_can_read(o) and not exists(select 1 from private.organization_secret_rounds b join private.organization_secret_participants sp on sp.round_id=b.id where b.organization_id=o and sp.delegate_user_id=uid and b.status<>'draft') then raise sqlstate '42501' using message='Organization access required.';end if;
  return jsonb_build_object('rounds',coalesce((select jsonb_agg(private.vote039_projection(b) order by b.created_at desc,b.id) from private.organization_secret_rounds b where b.organization_id=o and private.vote039_read(b)),'[]'),
   'meetings',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'is_test',a.is_test,'status',a.status,'revision',a.revision,'roll',a.workspace->'roll') order by a.meeting_at desc) from private.organization_meetings a where a.organization_id=o and a.status in ('scheduled','active') and private.vote039_manager(a.id)),'[]'),
   'directory',case when exists(select 1 from private.organization_meetings a where a.organization_id=o and a.status in ('scheduled','active') and private.vote039_manager(a.id)) then coalesce((select jsonb_agg(jsonb_build_object('id',pr.id,'name',coalesce(pr.display_name,'Adult account')) order by pr.display_name,pr.id) from public.profiles pr where private.vote039_candidate(o,pr.id)),'[]') else '[]'::jsonb end);
 end if;
 if act='ballot_detail' then
  select * into r from private.organization_secret_rounds where id=bid and organization_id=o;
  if not found then raise sqlstate '42501' using message='Ballot access required.';end if;
  return private.vote039_projection(r);
 end if;
 if act not in ('ballot_save','ballot_open','ballot_cast','ballot_test_cast','ballot_close','ballot_cancel','ballot_substitute') then raise exception 'Unknown ballot action.';end if;
 -- Every ballot mutation uses the same lock order as the meeting writer. This
 -- serializes casts, delegate substitutions, close and adjournment safely.
 perform 1 from public.organizations where id=o for update;
 if bid is not null then
  select * into r from private.organization_secret_rounds where id=bid and organization_id=o for update;
  if not found then raise sqlstate '42501' using message='Ballot access required.';end if;
  mid:=r.meeting_id;
 end if;
 select * into m from private.organization_meetings where id=mid and organization_id=o for update;
 if not found then raise sqlstate '42501' using message='Meeting access required.';end if;
 if act in ('ballot_cast','ballot_test_cast') then
  if bid is null then raise sqlstate '42501' using message='Ballot access required.';end if;
  if act='ballot_test_cast' then
   if not m.is_test or not private.vote039_manager(mid) then raise sqlstate '42501' using message='Test simulation is available only to leaders of a test meeting.';end if;
   select * into p from private.organization_secret_participants where round_id=bid and entity_id=nullif(q->>'entity_id','')::uuid and delegate_user_id is null for update;
   if not found then raise sqlstate '42501' using message='Only an unassigned test seat can be simulated.';end if;
  else
   select * into p from private.organization_secret_participants where round_id=bid and delegate_user_id=uid for update;
   if not found or not private.vote039_adult(uid) then raise sqlstate '42501' using message='You are not the designated eligible voter for this round.';end if;
  end if;
  -- An accepted ballot remains accepted on retry, even after close or when a
  -- second device submits a different choice. No choice or choice hash returns.
  if p.submitted then return jsonb_build_object('recorded',true,'already_recorded',true);end if;
  if r.status<>'open' or m.status<>'active' or not p.present then raise exception 'This ballot is not open for your participation.';end if;
  if coalesce(q->>'choice','') not in ('for','against','abstain') then raise exception 'Choose For, Against, or Abstain.';end if;
  update private.organization_secret_participants set submitted=true where round_id=bid and entity_id=p.entity_id;
  update private.organization_secret_totals set yes_count=yes_count+case when q->>'choice'='for' then 1 else 0 end,
   no_count=no_count+case when q->>'choice'='against' then 1 else 0 end,
   abstain_count=abstain_count+case when q->>'choice'='abstain' then 1 else 0 end where round_id=bid;
  if not found then raise exception 'Ballot acceptance unavailable. Try again.';end if;
  return jsonb_build_object('recorded',true,'already_recorded',false);
 end if;
 if not private.vote039_manager(mid) then raise sqlstate '42501' using message='Assigned meeting chair, secretary or organization administrator required.';end if;
 if rid is null then raise exception 'A request ID is required.';end if;
 select * into replay from private.organization_secret_requests where organization_id=o and actor_id=uid and request_id=rid;
 if found then
  if replay.fingerprint<>md5(q::text) then raise exception 'Request ID already used for different content.';end if;
  return replay.result;
 end if;
 if bid is not null and (q->>'revision' is null or (q->>'revision')::int<>r.revision) then raise sqlstate '40001' using message='The ballot setup changed. Reload its latest revision.';end if;
 if m.status not in ('scheduled','active') then raise exception 'This meeting is no longer accepting ballot changes.';end if;
 if act='ballot_save' then
  if bid is not null and r.status<>'draft' then raise exception 'An opened round is immutable. Create a new round for an amendment or revote.';end if;
  if length(trim(coalesce(q->>'motion',''))) not between 1 and 8000 or coalesce(q->>'electorate','') not in ('board','affiliates') then raise exception 'Motion text and electorate are required.';end if;
  if jsonb_typeof(q->'participants') is distinct from 'array' or jsonb_array_length(q->'participants')>200 then raise exception 'Choose up to 200 eligible participants.';end if;
  if jsonb_typeof(q->'policy') is distinct from 'object' or octet_length((q->'policy')::text)>10000 then raise exception 'Invalid policy draft.';end if;
  -- Allow incomplete policies in a draft; opening performs strict validation.
  doc:='{}';foreach k in array array['governing_rule','electronic_authorization','min_attendance','min_ballots','numerator','denominator','comparison','basis','abstentions','tie'] loop doc:=doc||jsonb_build_object(k,q->'policy'->k);end loop;
  if bid is null then
   bid:=gen_random_uuid();
   if nullif(q->>'prior_id','') is not null then
    select * into prior_round from private.organization_secret_rounds where id=(q->>'prior_id')::uuid and organization_id=o and meeting_id=mid;
    if not found or prior_round.status not in ('closed','cancelled') or length(trim(coalesce(q->>'change_reason','')))<3 then raise exception 'Reference a closed or cancelled round and explain the amendment or revote.';end if;
   end if;
   insert into private.organization_secret_rounds(id,organization_id,meeting_id,series_id,round_number,prior_id,motion,mover,seconder,electorate,policy,change_reason,created_by)
    values(bid,o,mid,coalesce(prior_round.series_id,bid),coalesce(prior_round.round_number,0)+1,prior_round.id,trim(q->>'motion'),left(coalesce(q->>'mover',''),200),left(coalesce(q->>'seconder',''),200),q->>'electorate',doc,left(coalesce(q->>'change_reason',''),2000),uid) returning * into r;
   insert into private.organization_secret_totals(round_id) values(bid);
  else
   delete from private.organization_secret_delegations where round_id=bid;
   delete from private.organization_secret_participants where round_id=bid;
   update private.organization_secret_rounds set motion=trim(q->>'motion'),mover=left(coalesce(q->>'mover',''),200),seconder=left(coalesce(q->>'seconder',''),200),electorate=q->>'electorate',policy=doc,revision=revision+1 where id=bid returning * into r;
  end if;
  for x in select value from jsonb_array_elements(q->'participants') loop
   entity:=nullif(x->>'entity_id','')::uuid;person:=nullif(x->>'delegate_user_id','')::uuid;
   select a into source from jsonb_array_elements(m.workspace->'roll') a where a->>'id'=entity::text and a->>'kind'=case when r.electorate='board' then 'board' else 'affiliate' end and a->>'eligible'='true';
   if not found or (r.electorate='affiliates' and source->>'present'<>'true') then raise exception 'Choose eligible entries from this meeting roll call; clubs must be present.';end if;
   if r.electorate='board' then person:=entity;end if;
   if person is not null and not private.vote039_candidate(o,person) then raise exception 'Choose an eligible adult personal account from this organization or an approved affiliate.';end if;
   insert into private.organization_secret_participants(round_id,entity_id,snapshot_name,present,delegate_user_id) values(bid,entity,source->>'name',(source->>'present')::boolean,person);
   if person is not null then insert into private.organization_secret_delegations(round_id,user_id,entity_id) values(bid,person,entity);end if;
  end loop;
  update private.organization_secret_rounds set eligible_count=(select count(*) from private.organization_secret_participants where round_id=bid),attendance_count=(select count(*) from private.organization_secret_participants where round_id=bid and present) where id=bid returning * into r;
 elsif act='ballot_open' then
  if r.status<>'draft' or m.status<>'active' then raise exception 'Start the meeting and use a draft round before opening voting.';end if;
  if q->>'confirm_rules' is distinct from 'true' or q->>'confirm_delegates' is distinct from 'true' then raise exception 'Confirm the governing authorization, electorate and adult delegate assignments.';end if;
  if not m.is_test and not private.vote039_released() then raise exception 'Live voting is awaiting release verification. Use a test meeting for now.';end if;
  doc:=private.vote039_policy(r.policy);
  if r.eligible_count<1 or r.attendance_count<(doc->>'min_attendance')::int or r.attendance_count<(doc->>'min_ballots')::int then raise exception 'The snapshotted attendance cannot meet the configured quorum.';end if;
  for p in select * from private.organization_secret_participants where round_id=bid loop
   select a into source from jsonb_array_elements(m.workspace->'roll') a where a->>'id'=p.entity_id::text and a->>'kind'=case when r.electorate='board' then 'board' else 'affiliate' end and a->>'eligible'='true';
   if not found or (source->>'present')::boolean is distinct from p.present then raise exception 'Meeting eligibility or attendance changed. Save the draft from the current roll call.';end if;
   if not (m.is_test and p.delegate_user_id is null) and (p.delegate_user_id is null or not private.vote039_candidate(o,p.delegate_user_id)) then raise exception 'Assign and confirm an eligible adult personal account for every seat.';end if;
   if r.electorate='affiliates' and not m.is_test and not exists(select 1 from private.organization_affiliates a where a.id=p.entity_id and a.organization_id=o and a.status='active' and a.membership_review='confirmed' and a.voting_review='eligible' and a.voting_eligible) then raise exception 'Review membership and voting eligibility in Affiliate directory before opening this ballot.';end if;
  end loop;
  update private.organization_secret_rounds set status='open',policy=doc,opened_at=now(),revision=revision+1 where id=bid returning * into r;
 elsif act='ballot_substitute' then
  if r.electorate<>'affiliates' or r.status not in ('draft','open') or q->>'confirm_delegates' is distinct from 'true' then raise exception 'Delegate substitution requires an active club round and explicit adult appointment.';end if;
  entity:=nullif(q->>'entity_id','')::uuid;person:=nullif(q->>'delegate_user_id','')::uuid;
  select * into p from private.organization_secret_participants where round_id=bid and entity_id=entity for update;
  if not found or not private.vote039_candidate(o,person) then raise exception 'Choose this club and an eligible adult personal account.';end if;
  if exists(select 1 from private.organization_secret_delegations where round_id=bid and user_id=person and entity_id<>entity) then raise exception 'That person already represents another seat in this voting round.';end if;
  insert into private.organization_secret_delegations(round_id,user_id,entity_id) values(bid,person,entity) on conflict do nothing;
  update private.organization_secret_participants set delegate_user_id=person where round_id=bid and entity_id=entity;
  -- submitted is deliberately unchanged, including after a ballot was accepted.
  update private.organization_secret_rounds set revision=revision+1 where id=bid returning * into r;
 elsif act='ballot_close' then
  if r.status<>'open' then raise exception 'Only an open round can be closed.';end if;
  select * into t from private.organization_secret_totals where round_id=bid;
  yes_votes:=t.yes_count;no_votes:=t.no_count;abstain_votes:=t.abstain_count;votes:=yes_votes+no_votes+abstain_votes;
  if votes<>(select count(*) from private.organization_secret_participants where round_id=bid and submitted) then raise exception 'Ballot integrity check failed; results were not published.';end if;
  den:=case when r.policy->>'basis'='electorate' then r.eligible_count else yes_votes+no_votes+case when r.policy->>'abstentions'='include' then abstain_votes else 0 end end;
  if votes=0 then outcome:='no_decision';
  elsif votes<(r.policy->>'min_ballots')::int or r.attendance_count<(r.policy->>'min_attendance')::int then outcome:='no_quorum';
  elsif yes_votes+no_votes=0 or den=0 then outcome:='no_decision';
  elsif yes_votes=no_votes then outcome:=case r.policy->>'tie' when 'not_passed' then 'not_passed' when 'new_round' then 'new_round_required' else 'no_decision' end;
  elsif (case when r.policy->>'comparison'='gt' then yes_votes::bigint*(r.policy->>'denominator')::int>den::bigint*(r.policy->>'numerator')::int else yes_votes::bigint*(r.policy->>'denominator')::int>=den::bigint*(r.policy->>'numerator')::int end) then outcome:='passed';
  else outcome:='not_passed';end if;
  doc:=jsonb_build_object('id',bid,'is_test',m.is_test,'round_number',r.round_number,'motion',r.motion,'mover',r.mover,'seconder',r.seconder,'electorate',r.electorate,'policy',r.policy,
   'eligible_count',r.eligible_count,'attendance_count',r.attendance_count,'ballots_cast',votes,'approval_denominator',den,'totals',jsonb_build_object('for',yes_votes,'against',no_votes,'abstain',abstain_votes),'outcome',outcome);
  update private.organization_secret_rounds set status='closed',closed_at=now(),result=doc,revision=revision+1 where id=bid returning * into r;
 elsif act='ballot_cancel' then
  if r.status not in ('draft','open') or length(trim(coalesce(q->>'reason','')))<3 then raise exception 'Record a cancellation reason for a draft or open round.';end if;
  update private.organization_secret_rounds set status='cancelled',closed_at=now(),change_reason=left(q->>'reason',2000),revision=revision+1 where id=bid returning * into r;
 end if;
 result:=jsonb_build_object('id',bid,'revision',r.revision,'status',r.status);
 insert into private.organization_secret_requests(organization_id,actor_id,request_id,fingerprint,result) values(o,uid,rid,md5(q::text),result);
 insert into private.ops_audit(organization_id,actor_id,action,record_id,detail) values(o,uid,act,bid,jsonb_build_object('revision',r.revision,'status',r.status));
 return result;
end $$;

-- The shared org lock prevents adjournment racing an open/cast operation.
create function private.vote039_meeting(q jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o uuid=nullif(q->>'organization_id','')::uuid; m private.organization_meetings%rowtype; out jsonb; request uuid=nullif(q->>'request_id','')::uuid; receipt private.organization_meeting_requests%rowtype; demo jsonb; i integer;
begin
 if auth.uid() is null or not private.ops_personal() or not private.managed_login_access_ok() then raise sqlstate '42501' using message='Use your personal account.';end if;
 if q->>'action'='meeting_delete_test' then
  if not private.ops_admin(o) then raise sqlstate '42501' using message='Organization administrator required to delete a test meeting.';end if;
  if request is null or q->>'confirm_delete' is distinct from 'DELETE' then raise exception 'Type DELETE to delete this test meeting and its test ballots.';end if;
  perform 1 from public.organizations where id=o for update;
  select * into receipt from private.organization_meeting_requests where organization_id=o and actor_id=auth.uid() and request_id=request;
  if found then if receipt.fingerprint<>md5(q::text) then raise exception 'Request ID already used for different content.';end if;return receipt.result;end if;
  select * into m from private.organization_meetings where id=nullif(q->>'id','')::uuid and organization_id=o for update;
  if not found or not m.is_test then raise exception 'Only a test meeting can be deleted here.';end if;
  if q->>'revision' is null or (q->>'revision')::int<>m.revision then raise sqlstate '40001' using message='Meeting changed. Reload before deleting.';end if;
  delete from private.organization_secret_requests where organization_id=o and result->>'id' in(select id::text from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_delegations where round_id in(select id from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_participants where round_id in(select id from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_totals where round_id in(select id from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_rounds where meeting_id=m.id;
  delete from private.organization_meeting_requests where organization_id=o and result->>'id'=m.id::text;
  delete from private.organization_meetings where id=m.id;
  out:=jsonb_build_object('id',m.id,'deleted',true);
  insert into private.organization_meeting_requests(organization_id,actor_id,request_id,fingerprint,result) values(o,auth.uid(),request,md5(q::text),out);
  insert into private.ops_audit(organization_id,actor_id,action,record_id,detail) values(o,auth.uid(),'meeting_delete_test',m.id,'{"is_test":true}');
  return out;
 end if;
 if q->>'action' in ('meeting_adjourn','meeting_cancel') then
  perform 1 from public.organizations where id=o for update;
  select * into m from private.organization_meetings where organization_id=o and id=nullif(q->>'id','')::uuid;
  if m.id is null or not private.meeting038_editor(m) then raise exception 'Meeting editor access required.' using errcode='42501';end if;
  if exists(select 1 from private.organization_secret_rounds where organization_id=o and meeting_id=m.id and status='open') then raise exception 'Close or cancel every open ballot before adjourning this meeting.';end if;
 end if;
 out:=private.meeting038_request(q);
 if q->>'action'='meeting_create' and q->>'is_test'='true' then
  select * into m from private.organization_meetings where id=(out->>'id')::uuid and created_by=auth.uid() for update;
  if m.id is not null and not m.is_test then
   demo:='[]';for i in 1..3 loop demo:=demo||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind','affiliate','name','Demo club '||i||' (test only)','delegate','','present',true,'eligible',true));end loop;
   update private.organization_meetings set is_test=true,workspace=jsonb_set(workspace,'{roll}',workspace->'roll'||demo) where id=m.id;
   insert into private.organization_meeting_attendance(meeting_id,participant_kind,participant_id,display_name,present)
    select m.id,'affiliate',(a->>'id')::uuid,a->>'name',true from jsonb_array_elements(demo) a;
  end if;
 elsif q->>'action'='meeting_list' then
  out:=out||'{"voting_enabled":true}'::jsonb;
  out:=jsonb_set(out,'{meetings}',coalesce((select jsonb_agg(a||jsonb_build_object('is_test',m.is_test)) from jsonb_array_elements(out->'meetings') a join private.organization_meetings m on m.id=(a->>'id')::uuid),'[]'));
 end if;
 return out;
end $$;
create or replace function private.meeting038_read(m private.organization_meetings) returns boolean language sql stable set search_path='' as $$
 select coalesce(private.meeting038_leader(m) or (not m.is_test and m.status='adjourned' and m.minutes_version>0 and private.gov_can_read(m.organization_id)),false);
$$;
create or replace function private.meeting038_snapshot(m private.organization_meetings) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',m.id,'organization_id',m.organization_id,'title',m.title,'meeting_at',m.meeting_at,'location',m.location,
 'is_test',m.is_test,'status',m.status,'started_at',m.started_at,'adjourned_at',m.adjourned_at,'version',m.minutes_version,
 'approval',m.approval,'minutes_label',case when m.approval is null then 'UNAPPROVED MINUTES' else 'APPROVED MINUTES' end,
 'chair',coalesce((select display_name from public.profiles where id=m.chair_user_id),''),
 'secretary',coalesce((select display_name from public.profiles where id=m.secretary_user_id),''),'document',m.workspace,
 'private_ballot_results',coalesce((select jsonb_agg(r.result order by r.created_at,r.id) from private.organization_secret_rounds r where r.meeting_id=m.id and r.status='closed'),'[]'));
$$;
create or replace function private.organization_governance(q jsonb) returns jsonb language sql set search_path='' as $$
 select case when q->>'action' like 'ballot\_%' escape '\' then private.vote039_request(q)
 when q->>'action' like 'meeting\_%' escape '\' then private.vote039_meeting(q)
 when q->>'action'='context' then private.gov_structure_v2(q)||'{"meetings_enabled":true,"voting_enabled":true}'::jsonb else private.gov_structure_v2(q) end;
$$;
do $$ declare r record;begin
 for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'vote039_%' loop execute format('revoke all on function %s from public,anon,authenticated',r.sig);end loop;
end $$;
revoke all on function private.meeting038_request(jsonb) from public,anon,authenticated;
grant execute on function private.vote039_request(jsonb),private.vote039_meeting(jsonb) to authenticated;
