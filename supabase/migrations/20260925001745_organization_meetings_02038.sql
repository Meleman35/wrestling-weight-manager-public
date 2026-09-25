-- 0.20.38: meeting records and minutes; electronic voting remains disabled.
-- Extend the installed meeting tables. Never copy executive notes into minutes.
alter table private.organization_meetings
 add column workspace jsonb not null default '{}',
 add column approval jsonb,
 add column minutes_version integer not null default 0;
create table private.organization_meeting_confidential (
 meeting_id uuid primary key references private.organization_meetings(id) on delete cascade,
 notes text not null default '', updated_by uuid not null references public.profiles(id),
 updated_at timestamptz not null default now(), check(length(notes)<=30000)
);
create table private.organization_meeting_requests (
 organization_id uuid not null references public.organizations(id),
 actor_id uuid not null references public.profiles(id), request_id uuid not null,
 fingerprint text not null, result jsonb not null, created_at timestamptz not null default now(),
 primary key(organization_id,actor_id,request_id)
);
alter table private.organization_meeting_confidential enable row level security;
alter table private.organization_meeting_requests enable row level security;
alter table private.organization_meetings enable row level security;
alter table private.organization_meeting_attendance enable row level security;
alter table private.organization_meeting_versions enable row level security;
revoke all on private.organization_meeting_confidential,private.organization_meeting_requests,
 private.organization_meetings,private.organization_meeting_attendance,private.organization_meeting_versions from public,anon,authenticated;
create index if not exists organization_meetings_org_date_038 on private.organization_meetings(organization_id,meeting_at desc,id);

create function private.meeting038_editor(m private.organization_meetings) returns boolean
language sql stable set search_path='' as $$
 select coalesce(private.ops_admin(m.organization_id) or
 (m.secretary_user_id=auth.uid() and private.gov_adult_candidate(m.organization_id,auth.uid())),false);
$$;
create function private.meeting038_leader(m private.organization_meetings) returns boolean
language sql stable set search_path='' as $$
 select coalesce(private.meeting038_editor(m) or
 (m.chair_user_id=auth.uid() and private.gov_adult_candidate(m.organization_id,auth.uid())),false);
$$;
create function private.meeting038_read(m private.organization_meetings) returns boolean
language sql stable set search_path='' as $$
 select coalesce(private.meeting038_leader(m) or
 (m.status='adjourned' and m.minutes_version>0 and private.gov_can_read(m.organization_id)),false);
$$;

-- Validate a bounded document; return only supported fields. No arbitrary JSON
-- supplied by a client can become metadata or override authorization/status.
create function private.meeting038_document(d jsonb, old_doc jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare k text; f text; r jsonb; x jsonb; rows jsonb; result jsonb='{}'; q jsonb;
begin
 if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>180000 then raise exception 'Meeting document is too large or invalid.'; end if;
 foreach k in array array['minutes','guests'] loop
  if jsonb_typeof(d->k) is distinct from 'string' or length(d->>k)>30000 then raise exception 'Invalid or oversized meeting notes.'; end if;
  result:=result||jsonb_build_object(k,d->k);
 end loop;
 q:=d->'quorum';
 if jsonb_typeof(q) is distinct from 'object' or length(coalesce(q->>'rule',''))>4000 then raise exception 'Record a valid quorum rule.'; end if;
 foreach k in array array['board_required','affiliate_required'] loop
  if q->>k is not null and (q->>k !~ '^[0-9]{1,4}$' or (q->>k)::int<1) then raise exception 'Quorum counts must be positive whole numbers or left unset.'; end if;
 end loop;
 if (q->>'board_required' is not null or q->>'affiliate_required' is not null) and length(trim(coalesce(q->>'rule','')))<3 then raise exception 'Record the governing rule supporting quorum.'; end if;
 result:=result||jsonb_build_object('quorum',jsonb_build_object('rule',coalesce(q->>'rule',''),'board_required',(q->>'board_required')::int,'affiliate_required',(q->>'affiliate_required')::int));
 foreach k in array array['agenda','roll','motions','actions'] loop
  if jsonb_typeof(d->k) is distinct from 'array' or jsonb_array_length(d->k)>200 then raise exception 'Meeting sections must contain at most 200 entries.'; end if;
  rows:='[]';
  for r in select value from jsonb_array_elements(d->k) loop
   if jsonb_typeof(r) is distinct from 'object' or octet_length(r::text)>20000 then raise exception 'Invalid meeting entry.'; end if;
   if k='agenda' then
    x:=jsonb_build_object('topic',left(coalesce(r->>'topic',''),400),'notes',left(coalesce(r->>'notes',''),8000));
   elsif k='roll' then
    if not exists(select 1 from jsonb_array_elements(old_doc->'roll') a where a->>'id'=r->>'id' and a->>'kind'=r->>'kind' and a->>'name'=r->>'name') then raise exception 'The snapshotted roll cannot be replaced. Reopen this meeting.'; end if;
    if jsonb_typeof(r->'present') is distinct from 'boolean' or jsonb_typeof(r->'eligible') is distinct from 'boolean' then raise exception 'Invalid roll call.'; end if;
    if (r->>'eligible')::boolean and not coalesce((select (a->>'eligible')::boolean from jsonb_array_elements(old_doc->'roll') a where a->>'id'=r->>'id'),false) and length(trim(coalesce(q->>'rule','')))<3 then raise exception 'Record a governing rule before changing eligibility.'; end if;
    x:=jsonb_build_object('id',r->>'id','kind',r->>'kind','name',r->>'name','delegate',left(coalesce(r->>'delegate',''),200),'present',r->'present','eligible',r->'eligible');
   elsif k='motions' then
    if coalesce(r->>'body','') not in ('board','affiliates') or coalesce(r->>'result','') not in ('not_recorded','passed','denied','tie','withdrawn','deferred') then raise exception 'Choose a motion electorate and recorded outcome.'; end if;
    foreach f in array array['yes','no','abstain'] loop
     if r->>f is not null and r->>f !~ '^[0-9]{1,6}$' then raise exception 'Vote counts must be whole numbers or left blank.'; end if;
    end loop;
    if r->>'result' in ('passed','denied') and
     (q->>case when r->>'body'='board' then 'board_required' else 'affiliate_required' end) is not null and
     (select count(*) from jsonb_array_elements(d->'roll') a where a->>'kind'=case when r->>'body'='board' then 'board' else 'affiliate' end and a->>'eligible'='true' and a->>'present'='true') < (q->>case when r->>'body'='board' then 'board_required' else 'affiliate_required' end)::int then
     raise exception 'The recorded attendance does not meet the configured quorum for this decision.';
    end if;
    -- Counts are a secretary's record, never a computed electronic result.
    if r->>'result' in ('passed','denied') and (length(trim(coalesce(r->>'rule','')))<3 or length(trim(coalesce(r->>'method','')))<3) then raise exception 'Record the decision method and governing rule for a passed or denied motion.'; end if;
    if r->>'result' in ('passed','denied') and r->>'yes' is not null and r->>'no' is not null and r->>'abstain' is not null and (r->>'yes')::int+(r->>'no')::int+(r->>'abstain')::int=0 then raise exception 'Zero ballots cannot establish a majority.'; end if;
    x:=jsonb_build_object('text',left(coalesce(r->>'text',''),8000),'mover',left(coalesce(r->>'mover',''),200),'seconder',left(coalesce(r->>'seconder',''),200),'body',r->>'body','method',left(coalesce(r->>'method',''),200),'result',r->>'result','yes',(r->>'yes')::int,'no',(r->>'no')::int,'abstain',(r->>'abstain')::int,'rule',left(coalesce(r->>'rule',''),2000),'notes',left(coalesce(r->>'notes',''),6000));
   else
    if coalesce(r->>'status','') not in ('open','in_progress','done') then raise exception 'Invalid action item status.'; end if;
    if nullif(r->>'due','') is not null then perform (r->>'due')::date; end if;
    x:=jsonb_build_object('task',left(coalesce(r->>'task',''),2000),'owner',left(coalesce(r->>'owner',''),200),'due',coalesce(r->>'due',''),'status',r->>'status');
   end if;
   rows:=rows||jsonb_build_array(x);
  end loop;
  -- Inner loops must not change the section key.
  result:=result||jsonb_build_object(k,rows);
 end loop;
 if jsonb_array_length(result->'roll')<>jsonb_array_length(old_doc->'roll') or
 (select count(distinct a->>'id') from jsonb_array_elements(result->'roll') a)<>jsonb_array_length(result->'roll') then raise exception 'Keep every snapshotted roll entry once.'; end if;
 return result;
end $$;

create function private.meeting038_snapshot(m private.organization_meetings) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',m.id,'organization_id',m.organization_id,'title',m.title,'meeting_at',m.meeting_at,'location',m.location,
 'status',m.status,'started_at',m.started_at,'adjourned_at',m.adjourned_at,'version',m.minutes_version,
 'approval',m.approval,'minutes_label',case when m.approval is null then 'UNAPPROVED MINUTES' else 'APPROVED MINUTES' end,
 'chair',coalesce((select display_name from public.profiles where id=m.chair_user_id),''),
 'secretary',coalesce((select display_name from public.profiles where id=m.secretary_user_id),''),
 'document',m.workspace);
$$;
create function private.meeting038_detail(m private.organization_meetings) returns jsonb
language plpgsql stable set search_path='' as $$
declare result jsonb;
begin
 if not private.meeting038_read(m) then raise sqlstate '42501' using message='Meeting access required.'; end if;
 result:=jsonb_build_object('can_edit',private.meeting038_editor(m),'can_assign',private.ops_admin(m.organization_id),'can_confidential',private.meeting038_leader(m));
 if private.meeting038_leader(m) then
  result:=result||case when m.status='adjourned' then m.minutes_snapshot else private.meeting038_snapshot(m) end||jsonb_build_object('revision',m.revision,'chair_user_id',m.chair_user_id,'secretary_user_id',m.secretary_user_id,
   'confidential_notes',coalesce((select notes from private.organization_meeting_confidential where meeting_id=m.id),''));
 else result:=result||m.minutes_snapshot;
 end if;
 return result;
end $$;

create function private.meeting038_request(q jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); o uuid=nullif(q->>'organization_id','')::uuid; action text=q->>'action';
 mid uuid=nullif(q->>'id','')::uuid; rid uuid=nullif(q->>'request_id','')::uuid; m private.organization_meetings%rowtype;
 d jsonb; oldd jsonb; result jsonb; prior private.organization_meeting_requests%rowtype; person uuid; k text; changed boolean=false;
begin
 if uid is null or not private.ops_personal() or not private.managed_login_access_ok() then raise sqlstate '42501' using message='Use your personal account.'; end if;
 if o is null or not private.gov_can_read(o) then raise sqlstate '42501' using message='Organization access required.'; end if;
 if octet_length(q::text)>240000 then raise exception 'Meeting request is too large.'; end if;
 if action='meeting_list' then
  return jsonb_build_object('can_create',private.ops_admin(o),'voting_enabled',false,
   'directory',case when private.ops_admin(o) then coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.display_name,'Adult account')) order by p.display_name,p.id) from public.profiles p where private.gov_adult_candidate(o,p.id)),'[]') else '[]'::jsonb end,
   'meetings',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'title',x.title,'meeting_at',x.meeting_at,'status',x.status,'minutes_version',x.minutes_version,'approved',x.approval is not null,'can_edit',private.meeting038_editor(x)) order by x.meeting_at desc,x.id) from private.organization_meetings x where x.organization_id=o and private.meeting038_read(x)),'[]'));
 end if;
 if action in ('meeting_detail','meeting_history') then
  select * into m from private.organization_meetings where id=mid and organization_id=o;
  if not found or not private.meeting038_read(m) then raise sqlstate '42501' using message='Meeting access required.'; end if;
  if action='meeting_detail' then return private.meeting038_detail(m); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('version',v.version,'reason',v.reason,'created_at',v.created_at,'snapshot',v.snapshot) order by v.version desc) from private.organization_meeting_versions v where v.meeting_id=mid),'[]');
 end if;
 if action not in ('meeting_create','meeting_save','meeting_start','meeting_adjourn','meeting_approve','meeting_assign','meeting_cancel') then raise exception 'This meeting action is not enabled.'; end if;
 if rid is null then raise exception 'A request ID is required. Reopen the meeting.'; end if;
 -- Serialize writes and retries per tenant. Revision checks occur under this lock.
 perform 1 from public.organizations where id=o for update;
 if action='meeting_create' then
  if not private.ops_admin(o) then raise sqlstate '42501' using message='Organization administrator required to create a meeting.'; end if;
 else
  select * into m from private.organization_meetings where id=mid and organization_id=o for update;
  if not found or not private.meeting038_editor(m) then raise sqlstate '42501' using message='Assigned secretary or organization administrator required.'; end if;
 end if;
 select * into prior from private.organization_meeting_requests where organization_id=o and actor_id=uid and request_id=rid;
 if found then
  if prior.fingerprint<>md5(q::text) then raise exception 'This request ID was already used for different content.'; end if;
  return prior.result;
 end if;
 if action<>'meeting_create' and (q->>'revision' is null or (q->>'revision')::int<>m.revision) then raise sqlstate '40001' using message='This meeting changed on another device. Reload the latest revision before saving.'; end if;
 if action in ('meeting_create','meeting_assign') then
  if not private.ops_admin(o) then raise sqlstate '42501' using message='Only an organization administrator can assign meeting access.'; end if;
  if q->>'confirm_adult' is distinct from 'true' then raise exception 'Confirm these are adult personal accounts and approve their meeting access.'; end if;
  foreach k in array array['secretary_user_id','chair_user_id'] loop
   person:=nullif(q->>k,'')::uuid;
   if person is not null and not private.gov_adult_candidate(o,person) then raise exception 'Choose an eligible adult personal account from this organization.'; end if;
  end loop;
  if nullif(q->>'secretary_user_id','') is null then raise exception 'Assign an authorized secretary.'; end if;
 end if;
 if action='meeting_create' then
  if length(trim(coalesce(q->>'title',''))) not between 1 and 200 or nullif(q->>'meeting_at','') is null then raise exception 'Meeting title and date are required.'; end if;
  select jsonb_build_object('minutes','','guests','','agenda','[]'::jsonb,'motions','[]'::jsonb,'actions','[]'::jsonb,'quorum',jsonb_build_object('rule','','board_required',null,'affiliate_required',null),'roll',coalesce(jsonb_agg(r order by r->>'kind',r->>'name',r->>'id'),'[]')) into d from (
   select jsonb_build_object('id',p.assigned_user_id,'kind','board','name',coalesce(pr.display_name,'Assigned adult'),'delegate','','present',false,'eligible',bool_or(p.voting_member)) r
   from private.organization_positions p join public.profiles pr on pr.id=p.assigned_user_id where p.organization_id=o and p.active group by p.assigned_user_id,pr.display_name
   union all
   select jsonb_build_object('id',a.id,'kind','affiliate','name',a.name,'delegate','','present',false,'eligible',a.membership_review='confirmed' and a.voting_review='eligible' and a.voting_eligible)
   from private.organization_affiliates a where a.organization_id=o and a.status='active'
  ) roster;
  insert into private.organization_meetings(organization_id,title,meeting_at,location,secretary_user_id,chair_user_id,workspace,created_by,updated_by)
  values(o,trim(q->>'title'),(q->>'meeting_at')::timestamptz,left(coalesce(q->>'location',''),500),(q->>'secretary_user_id')::uuid,nullif(q->>'chair_user_id','')::uuid,d,uid,uid) returning * into m;
  mid:=m.id;
  insert into private.organization_meeting_attendance(meeting_id,participant_kind,participant_id,display_name)
   select mid,a->>'kind',(a->>'id')::uuid,a->>'name' from jsonb_array_elements(d->'roll') a;
 elsif action='meeting_save' then
  if m.status='cancelled' then raise exception 'Cancelled meetings are read only.'; end if;
  d:=private.meeting038_document(q->'document',m.workspace);
  if length(coalesce(q->>'confidential_notes',''))>30000 then raise exception 'Executive notes must be shorter than 30000 characters.'; end if;
  if m.status='adjourned' and d is distinct from m.workspace and length(trim(coalesce(q->>'correction_reason','')))<3 then raise exception 'Record the reason for this minutes correction.'; end if;
  changed:=d is distinct from m.workspace;
  update private.organization_meetings set workspace=d,agenda=d->'agenda',notes=d->>'minutes',approval=case when changed then null else approval end where id=mid returning * into m;
  insert into private.organization_meeting_confidential(meeting_id,notes,updated_by) values(mid,coalesce(q->>'confidential_notes',''),uid)
  on conflict(meeting_id) do update set notes=excluded.notes,updated_by=uid,updated_at=now();
  update private.organization_meeting_attendance a set present=(r->>'present')::bool,checked_in_by=uid,checked_in_at=now()
   from jsonb_array_elements(d->'roll') r where a.meeting_id=mid and a.participant_kind=r->>'kind' and a.participant_id=(r->>'id')::uuid and a.present is distinct from (r->>'present')::bool;
 elsif action='meeting_assign' then
  if m.status in ('adjourned','cancelled') then raise exception 'Meeting assignments are fixed after adjournment or cancellation.'; end if;
  update private.organization_meetings set secretary_user_id=(q->>'secretary_user_id')::uuid,chair_user_id=nullif(q->>'chair_user_id','')::uuid where id=mid returning * into m;
 elsif action='meeting_start' then
  if m.status<>'scheduled' then raise exception 'Only a scheduled meeting can be started.'; end if;
  if not private.gov_adult_candidate(o,m.secretary_user_id) then raise exception 'Assign a current authorized secretary first.'; end if;
  update private.organization_meetings set status='active',started_at=now() where id=mid returning * into m;
 elsif action='meeting_adjourn' then
  if m.status<>'active' then raise exception 'Start the meeting before recording adjournment.'; end if;
  update private.organization_meetings set status='adjourned',adjourned_at=now(),minutes_published_at=now(),visibility='affiliates',approval=null where id=mid returning * into m;
  changed:=true;
 elsif action='meeting_cancel' then
  if m.status<>'scheduled' then raise exception 'Only a scheduled meeting can be cancelled.'; end if;
  update private.organization_meetings set status='cancelled' where id=mid returning * into m;
 elsif action='meeting_approve' then
  if m.status<>'adjourned' or q->>'confirm_approved' is distinct from 'true' or length(trim(coalesce(q->>'reference','')))<3 or nullif(q->>'approved_on','') is null then raise exception 'Record the actual approval date and motion or decision reference.'; end if;
  if (q->>'approved_on')::date>current_date then raise exception 'Approval must already have occurred.'; end if;
  update private.organization_meetings set approval=jsonb_build_object('approved_on',(q->>'approved_on')::date,'reference',left(q->>'reference',2000)) where id=mid returning * into m;
  changed:=true;
 end if;
 if action<>'meeting_create' then update private.organization_meetings set revision=revision+1,updated_by=uid,updated_at=now() where id=mid returning * into m; end if;
 if m.status='adjourned' and changed then
  update private.organization_meetings set minutes_version=minutes_version+1 where id=mid returning * into m;
  d:=private.meeting038_snapshot(m);
  insert into private.organization_meeting_versions(meeting_id,version,reason,snapshot,created_by)
   values(mid,m.minutes_version,case action when 'meeting_adjourn' then 'Adjourned; unapproved minutes' when 'meeting_approve' then 'Recorded approval' else left(q->>'correction_reason',2000) end,d,uid);
  update private.organization_meetings set minutes_snapshot=d where id=mid;
 end if;
 result:=jsonb_build_object('id',mid,'revision',m.revision,'minutes_version',m.minutes_version,'status',m.status);
 insert into private.organization_meeting_requests(organization_id,actor_id,request_id,fingerprint,result) values(o,uid,rid,md5(q::text),result);
 insert into private.ops_audit(organization_id,actor_id,action,record_id,detail) values(o,uid,action,mid,jsonb_build_object('revision',m.revision,'minutes_version',m.minutes_version));
 return result;
end $$;

create or replace function private.organization_governance(q jsonb) returns jsonb
language sql set search_path='' as $$
 select case when q->>'action' like 'meeting\_%' escape '\' then private.meeting038_request(q) else private.gov_structure_v2(q)||case when q->>'action'='context' then '{"meetings_enabled":true}'::jsonb else '{}'::jsonb end end;
$$;
-- Only the guarded dispatcher is an API. Helpers and legacy ballot APIs stay closed.
do $$ declare r record; begin
 for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'meeting038_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',r.sig);
 end loop;
end $$;
grant execute on function private.meeting038_request(jsonb) to authenticated;
