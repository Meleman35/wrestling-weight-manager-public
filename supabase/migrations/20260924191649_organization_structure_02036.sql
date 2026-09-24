-- Positions and directory only. No team membership, invitation, or contract writes.
-- Existing position/access assignments and directory identities are preserved.
do $$ begin
 if exists(select 1 from private.organization_meetings) or exists(select 1 from private.organization_ballots) then
  raise exception 'Meetings or ballots now exist. Review the rollout before disabling the unreleased governance endpoints.';
 end if;
end $$;
alter table private.organization_positions
  add column parent_position_id uuid references private.organization_positions(id),
  add column assignment_enabled boolean not null default true,
  add column adult_confirmed_by uuid references public.profiles(id),
  add column adult_confirmed_at timestamptz;
alter table private.organization_affiliates
  add column affiliate_type text not null default 'club' check (affiliate_type in ('club','school','training_center','organization','other')),
  add column linked_organization_id uuid references public.organizations(id),
  add column membership_review text not null default 'unreviewed' check (membership_review in ('unreviewed','confirmed','not_current')),
  add column voting_review text not null default 'unreviewed' check (voting_review in ('unreviewed','eligible','ineligible')),
  add column review_note text not null default '',
  add column source_note text not null default '';
alter table private.organization_affiliates alter column voting_eligible set default false;
create index organization_positions_parent_idx on private.organization_positions(parent_position_id);
create index organization_affiliates_linked_org_idx on private.organization_affiliates(linked_organization_id);

create table private.organization_structure_versions (
  organization_id uuid not null references public.organizations(id),
  entity_kind text not null check (entity_kind in ('position','affiliate')),
  entity_id uuid not null,
  revision integer not null,
  snapshot jsonb not null,
  reason text not null,
  actor_id uuid references public.profiles(id),
  recorded_at timestamptz not null default now(),
  primary key (entity_kind,entity_id,revision)
);
create index organization_structure_versions_org_idx on private.organization_structure_versions(organization_id,entity_kind,entity_id,revision desc);
alter table private.organization_structure_versions enable row level security;
create table private.organization_structure_requests (
 organization_id uuid not null references public.organizations(id), actor_id uuid not null references public.profiles(id), request_id uuid not null,
 payload jsonb not null, result jsonb not null, created_at timestamptz not null default now(),
 primary key(organization_id,actor_id,request_id)
);
alter table private.organization_structure_requests enable row level security;
revoke all on private.organization_structure_requests from public,anon,authenticated;
alter table private.organization_positions enable row level security;
alter table private.organization_affiliates enable row level security;
revoke all on private.organization_structure_versions,private.organization_positions,private.organization_affiliates from public,anon,authenticated;

-- Preserve exact pre-upgrade values before adding review markers. Prior defaults
-- are not evidence of membership, a governing-rule decision, or adult verification.
insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason)
select organization_id,'position',id,revision,to_jsonb(p),'Pre-0.20.36 baseline' from private.organization_positions p;
insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason)
select organization_id,'affiliate',id,revision,to_jsonb(a),'Pre-0.20.36 baseline; eligibility requires review' from private.organization_affiliates a;
update private.organization_positions set assignment_enabled=false,revision=revision+1,updated_at=now()
where lower(title) ~ 'athlete.*rep' and assigned_user_id is null;
update private.organization_affiliates set voting_eligible=false,revision=revision+1,updated_at=now()
where voting_review='unreviewed';
insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason)
select organization_id,'position',id,revision,to_jsonb(p),'Athlete-representative assignments deferred' from private.organization_positions p
where not assignment_enabled;
insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason)
select organization_id,'affiliate',id,revision,to_jsonb(a),'Unreviewed directory; voting eligibility not established' from private.organization_affiliates a
where not exists(select 1 from private.organization_structure_versions v where v.entity_kind='affiliate' and v.entity_id=a.id and v.revision=a.revision);

-- Only an existing organization administrator can assign people and grant access.
-- Position titles, credential records and SafeSport fields are never checked here.
create or replace function private.gov_can_manage_structure(o uuid) returns boolean
language sql stable set search_path='' as $$ select auth.uid() is not null and private.ops_admin(o); $$;

create function private.gov_adult_candidate(o uuid,u uuid) returns boolean
language sql stable set search_path='' as $$
select u is not null
 and exists(select 1 from public.profiles where id=u)
 and not exists(select 1 from private.team_logins where user_id=u)
 -- All known athlete identities must have an adult birth date. This is a guard,
 -- not identity verification; the administrator must separately attest adulthood.
 and not exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
   where m.user_id=u and m.role='athlete' and (a.birth_date is null or a.birth_date>(current_date-interval '18 years')::date))
 and (
   exists(select 1 from public.organization_memberships where organization_id=o and user_id=u)
   or exists(select 1 from private.ops_roles where organization_id=o and user_id=u)
   or exists(select 1 from public.team_memberships m join public.teams t on t.id=m.team_id
     where m.user_id=u and m.active and t.organization_id=o and m.role in ('head_coach','assistant_coach','manager','parent_guardian'))
   or exists(select 1 from private.organization_positions where organization_id=o and assigned_user_id=u and active)
 );
$$;

create function private.gov_structure_context(o uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; admin boolean;
begin
 if auth.uid() is null or not private.ops_personal() or not private.managed_login_access_ok() then raise sqlstate '42501' using message='Use your personal account.'; end if;
 if not private.gov_can_read(o) then raise sqlstate '42501' using message='Organization access required.'; end if;
 admin:=private.gov_can_manage_structure(o);
 select jsonb_build_object(
  'organization_id',o,'can_manage_structure',admin,'meetings_enabled',false,'voting_enabled',false,
  'positions',coalesce((select jsonb_agg((to_jsonb(p)-'created_by'-'updated_by'-'adult_confirmed_by') || jsonb_build_object('assigned_name',pr.display_name,'division_name',d.name)
    order by p.active desc,p.sort_order,p.title,p.id)
    from private.organization_positions p left join public.profiles pr on pr.id=p.assigned_user_id
    left join private.ops_divisions d on d.id=p.division_id where p.organization_id=o and (admin or p.active)),'[]'::jsonb),
  'affiliates',coalesce((select jsonb_agg((to_jsonb(a)-'created_by'-'updated_by'-'contact'-'review_note') ||
    jsonb_build_object('contact',case when admin then a.contact else '{}'::jsonb end,
    'review_note',case when admin then a.review_note else '' end,
    'linked_team_name',t.name,'linked_organization_name',org.name) order by a.name,a.id)
    from private.organization_affiliates a left join public.teams t on t.id=a.linked_team_id
    left join public.organizations org on org.id=a.linked_organization_id where a.organization_id=o and (admin or a.status<>'archived')),'[]'::jsonb),
  'directory',case when admin then coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.display_name,''),'Unnamed adult account')) order by p.display_name,p.id)
    from public.profiles p where private.gov_adult_candidate(o,p.id)),'[]'::jsonb) else '[]'::jsonb end,
  'linkable_teams',case when admin then coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'organization_id',t.organization_id) order by t.name)
    from public.teams t where t.organization_id=o or exists(select 1 from private.ops_links l where l.organization_id=o and l.team_id=t.id and l.approved)),'[]'::jsonb) else '[]'::jsonb end,
  'linkable_organizations',case when admin then coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name) order by x.name)
    from public.organizations x where x.id<>o and exists(select 1 from public.organization_memberships m where m.organization_id=x.id and m.user_id=auth.uid() and m.role='organization_admin')),'[]'::jsonb) else '[]'::jsonb end
 ) into result;
 return result;
end $$;

create function private.gov_structure_v2(q jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid(); o uuid; act text; rid uuid; target uuid; parent_id uuid; div_id uuid;
 title_text text; access_text text; rev integer; p private.organization_positions%rowtype; a private.organization_affiliates%rowtype;
 snapshot jsonb; kind text; st text; membership text; voting text; link_team uuid; link_org uuid;
 contact_data jsonb; note_text text; enabled boolean; result jsonb; v_request_id uuid; previous private.organization_structure_requests%rowtype;
 preset text; titles text[]; added integer:=0;
begin
 if q is null or jsonb_typeof(q)<>'object' or octet_length(q::text)>30000 then raise exception 'Invalid organization structure request.'; end if;
 if uid is null or not private.ops_personal() or not private.managed_login_access_ok() then raise sqlstate '42501' using message='Use your personal account.'; end if;
 o:=nullif(q->>'organization_id','')::uuid; act:=coalesce(q->>'action','context'); rid:=nullif(q->>'id','')::uuid;
 if o is null then raise exception 'Choose an organization.'; end if;
 if act='context' then return private.gov_structure_context(o); end if;
 if not private.gov_can_manage_structure(o) then raise sqlstate '42501' using message='Organization administrator access required.'; end if;
 if act='history' then
  kind:=q->>'entity_kind';
  select coalesce(jsonb_agg(jsonb_build_object('revision',v.revision,'snapshot',v.snapshot,'reason',v.reason,'recorded_at',v.recorded_at,'actor_name',pr.display_name) order by v.revision desc),'[]'::jsonb)
   into result from private.organization_structure_versions v left join public.profiles pr on pr.id=v.actor_id
   where v.organization_id=o and v.entity_id=rid and v.entity_kind=kind;
  return result;
 end if;
 -- Serialize hierarchy changes, same-row retries and archive/reactivate operations.
 perform 1 from public.organizations where id=o for update;
 if not private.gov_can_manage_structure(o) then raise sqlstate '42501' using message='Organization administrator access required.'; end if;
 if act not in ('save_position','archive_position','restore_position','save_affiliate','archive_affiliate','restore_affiliate','add_presets') then
  raise exception 'Meetings, delegates and voting are not enabled in this release.';
 end if;
 v_request_id:=nullif(q->>'request_id','')::uuid;
 if v_request_id is null then raise exception 'A save request identifier is required.'; end if;
 select * into previous from private.organization_structure_requests r where r.organization_id=o and r.actor_id=uid and r.request_id=v_request_id;
 if found then
  if previous.payload is distinct from q then raise exception 'This save identifier was already used for different content.'; end if;
  return previous.result;
 end if;
 if act='add_presets' then
  preset:=q->>'preset';
  titles:=case preset
   when 'wawa' then array['Chairman','Vice-Chairman','Secretary','Treasurer','Registration','Open Director','Boys Junior','Boys 16U','Boys - Kids','Girls/16U Director','Girls - Kids','Mat Officials','Operations Official','Cultural Exchange','State Coach','Media Director','Member At-Large','Male Athlete Rep','Female Athlete Rep']
   when 'association' then array['President','Vice President','Secretary','Treasurer','Board Member','Membership Coordinator']
   when 'school' then array['Principal','Assistant Principal','Athletic Director','Head Coach','Assistant Coach','Athletic Trainer','Team Manager']
   when 'school_district' then array['Superintendent','Assistant Superintendent','Board Chair','Board Vice Chair','Board Clerk','Board Treasurer','Board Trustee','District Athletic Director','School Principal','Athletic Director']
   when 'club' then array['President','Vice President','Secretary','Treasurer','Head Coach','Assistant Coach','Membership Coordinator']
  end;
  if titles is null then raise exception 'Choose a supported position template.'; end if;
  foreach title_text in array titles loop
   if not exists(select 1 from private.organization_positions p2 where p2.organization_id=o and lower(trim(p2.title))=lower(title_text)) then
    insert into private.organization_positions(organization_id,title,assignment_enabled,created_by,updated_by)
     values(o,title_text,lower(title_text) !~ 'athlete.*rep',uid,uid) returning id,revision,to_jsonb(organization_positions) into rid,rev,snapshot;
    insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason,actor_id)
     values(o,'position',rid,rev,snapshot,'Vacant template: '||preset,uid);
    added:=added+1;
   end if;
  end loop;
  result:=jsonb_build_object('saved',true,'added',added);
  insert into private.organization_structure_requests values(o,uid,v_request_id,q,result,now());
  insert into private.ops_audit(organization_id,actor_id,action,detail) values(o,uid,act,jsonb_build_object('preset',preset,'added',added));
  return result;
 end if;
 if rid is not null and (q->>'revision') is null then raise sqlstate '40001' using message='Reload this record before saving.'; end if;
 if act in ('save_position','archive_position','restore_position') then
  kind:='position';
  if rid is not null then
   select * into p from private.organization_positions where id=rid and organization_id=o for update;
   if not found then raise exception 'Position not found in this organization.'; end if;
   if p.revision is distinct from (q->>'revision')::int then raise sqlstate '40001' using message='This position changed. Reload before saving.'; end if;
  end if;
  if act<>'save_position' then
   if rid is null then raise exception 'Choose a position.'; end if;
   update private.organization_positions set active=(act='restore_position'),revision=revision+1,updated_by=uid,updated_at=now() where id=rid returning to_jsonb(organization_positions),revision into snapshot,rev;
  else
   title_text:=trim(coalesce(q->>'title','')); target:=nullif(q->>'user_id','')::uuid;
   parent_id:=nullif(q->>'parent_position_id','')::uuid; div_id:=nullif(q->>'division_id','')::uuid; access_text:=nullif(q->>'access_role','');
   if length(title_text) not between 1 and 120 then raise exception 'Enter a position title (up to 120 characters).'; end if;
   enabled:=coalesce(p.assignment_enabled,true) and lower(title_text) !~ 'athlete.*rep';
   if target is not null and not enabled then raise exception 'Athlete-representative assignments are deferred.'; end if;
   if target is not null and not private.gov_adult_candidate(o,target) then raise exception 'Choose a connected personal adult account. Minor, shared and unverified athlete accounts cannot be assigned.'; end if;
   if target is not null and (p.assigned_user_id is distinct from target or p.adult_confirmed_at is null) and q->'confirm_adult' is distinct from 'true'::jsonb then
    raise exception 'Confirm this is the adult own account and they are at least 18.';
   end if;
   if access_text is not null and access_text not in ('president','director','board','division_director','pairing_director','mat_director','coach','chaperone','team_leader','official','membership_coordinator') then raise exception 'Choose a supported access permission.'; end if;
   if target is not null and access_text is not null and (p.assigned_user_id is distinct from target or p.access_role is distinct from access_text)
      and q->'confirm_access' is distinct from 'true'::jsonb then raise exception 'Explicitly confirm the selected access permissions.'; end if;
   -- A vacant post cannot silently carry access rights to the next appointee.
   if target is null then access_text:=null; end if;
   if div_id is not null and not exists(select 1 from private.ops_divisions where id=div_id and organization_id=o) then raise exception 'Choose a division in this organization.'; end if;
   if parent_id is not null then
    if parent_id=rid or not exists(select 1 from private.organization_positions where id=parent_id and organization_id=o and active) then raise exception 'Choose an active parent position in this organization.'; end if;
    if exists(with recursive chain as (
      select id,parent_position_id from private.organization_positions where id=parent_id and organization_id=o
      union select p2.id,p2.parent_position_id from private.organization_positions p2 join chain c on c.parent_position_id=p2.id where p2.organization_id=o
     ) select 1 from chain where id=rid) then raise exception 'Position hierarchy cannot contain a cycle.'; end if;
   end if;
   if rid is null then
    insert into private.organization_positions(organization_id,division_id,parent_position_id,title,assigned_user_id,access_role,assignment_enabled,adult_confirmed_by,adult_confirmed_at,created_by,updated_by)
    values(o,div_id,parent_id,title_text,target,access_text,enabled,case when target is not null then uid end,case when target is not null then now() end,uid,uid)
    returning id,revision,to_jsonb(organization_positions) into rid,rev,snapshot;
   else
    update private.organization_positions set division_id=div_id,parent_position_id=parent_id,title=title_text,assigned_user_id=target,access_role=access_text,
     assignment_enabled=enabled,adult_confirmed_by=case when target is null then null when p.assigned_user_id is distinct from target or p.adult_confirmed_at is null then uid else p.adult_confirmed_by end,
     adult_confirmed_at=case when target is null then null when p.assigned_user_id is distinct from target or p.adult_confirmed_at is null then now() else p.adult_confirmed_at end,
     revision=revision+1,updated_by=uid,updated_at=now() where id=rid returning revision,to_jsonb(organization_positions) into rev,snapshot;
   end if;
  end if;
 else
  kind:='affiliate';
  if rid is not null then
   select * into a from private.organization_affiliates where id=rid and organization_id=o for update;
   if not found then raise exception 'Affiliate not found in this organization.'; end if;
   if a.revision is distinct from (q->>'revision')::int then raise sqlstate '40001' using message='This affiliate changed. Reload before saving.'; end if;
  end if;
  if act<>'save_affiliate' then
   if rid is null then raise exception 'Choose an affiliate.'; end if;
   update private.organization_affiliates set status=case when act='archive_affiliate' then 'archived' else 'active' end,
    archived_at=case when act='archive_affiliate' then now() else null end,
    membership_review=case when act='restore_affiliate' then 'unreviewed' else membership_review end,
    voting_review='unreviewed',voting_eligible=false,revision=revision+1,updated_by=uid,updated_at=now()
    where id=rid returning revision,to_jsonb(organization_affiliates) into rev,snapshot;
  else
   title_text:=trim(coalesce(q->>'title','')); st:=coalesce(q->>'status','active');
   membership:=coalesce(q->>'membership_review','unreviewed');voting:=coalesce(q->>'voting_review','unreviewed');
   link_team:=nullif(q->>'linked_team_id','')::uuid; link_org:=nullif(q->>'linked_organization_id','')::uuid;
   note_text:=trim(coalesce(q->>'review_note',''));contact_data:=coalesce(q->'contact','{}'::jsonb);
   if length(title_text) not between 1 and 160 or st not in ('active','inactive','archived') then raise exception 'Enter a name and valid directory status.'; end if;
   if coalesce(q->>'affiliate_type','club') not in ('club','school','training_center','organization','other') then raise exception 'Choose an affiliate type.'; end if;
   if membership not in ('unreviewed','confirmed','not_current') or voting not in ('unreviewed','eligible','ineligible') then raise exception 'Choose membership and voting review states.'; end if;
   if voting='eligible' and (membership<>'confirmed' or st<>'active') then raise exception 'Voting eligibility requires confirmed, active membership.'; end if;
   if voting<>'unreviewed' and length(note_text)<3 then raise exception 'Record the governing rule or decision supporting voting eligibility.'; end if;
   if length(note_text)>2000 or length(coalesce(q->>'source_note',''))>1000 then raise exception 'Keep review notes within 2000 characters and source notes within 1000.'; end if;
   if jsonb_typeof(contact_data)<>'object' or octet_length(contact_data::text)>2000 or exists(select 1 from jsonb_each(contact_data) kv where kv.key not in ('name','email','phone') or jsonb_typeof(kv.value)<>'string' or length(kv.value#>>'{}')>250) then raise exception 'Contact details must be name, email and phone, up to 250 characters each.'; end if;
   if link_team is not null and link_team is distinct from a.linked_team_id and not exists(select 1 from public.teams t where t.id=link_team and (t.organization_id=o or exists(select 1 from private.ops_links l where l.organization_id=o and l.team_id=t.id and l.approved))) then raise exception 'First approve the team affiliation using its team code.'; end if;
   if link_org is not null and link_org is distinct from a.linked_organization_id and (link_org=o or not exists(select 1 from public.organization_memberships m where m.organization_id=link_org and m.user_id=uid and m.role='organization_admin')) then raise exception 'Choose another organization you administer. Linking does not transfer management.'; end if;
   if link_team is not null and link_org is not null and not exists(select 1 from public.teams where id=link_team and organization_id=link_org) then raise exception 'The selected team does not belong to the selected organization.'; end if;
   if rid is null then
    insert into private.organization_affiliates(organization_id,name,affiliate_type,status,membership_review,voting_review,voting_eligible,review_note,source_note,contact,linked_team_id,linked_organization_id,created_by,updated_by,archived_at)
    values(o,title_text,coalesce(q->>'affiliate_type','club'),st,membership,voting,voting='eligible',note_text,coalesce(q->>'source_note',''),contact_data,link_team,link_org,uid,uid,case when st='archived' then now() end)
    returning id,revision,to_jsonb(organization_affiliates) into rid,rev,snapshot;
   else
    update private.organization_affiliates set name=title_text,affiliate_type=coalesce(q->>'affiliate_type','club'),status=st,membership_review=membership,voting_review=voting,voting_eligible=(voting='eligible'),
     review_note=note_text,source_note=coalesce(q->>'source_note',''),contact=contact_data,linked_team_id=link_team,linked_organization_id=link_org,
     archived_at=case when st='archived' then coalesce(archived_at,now()) else null end,
     revision=revision+1,updated_by=uid,updated_at=now() where id=rid returning revision,to_jsonb(organization_affiliates) into rev,snapshot;
   end if;
  end if;
 end if;
 insert into private.organization_structure_versions(organization_id,entity_kind,entity_id,revision,snapshot,reason,actor_id)
 values(o,kind,rid,rev,snapshot,act,uid);
 insert into private.ops_audit(organization_id,actor_id,action,record_id,detail)
 values(o,uid,act,rid,jsonb_build_object('revision',rev));
 result:=jsonb_build_object('saved',true,'id',rid,'revision',rev);
 insert into private.organization_structure_requests values(o,uid,v_request_id,q,result,now());
 return result;
end $$;

-- Keep the existing API name. Only the released structure actions are routed.
-- No meetings or ballots existed at preflight. Their incomplete endpoints stay
-- unavailable until governing policies and voting security release gates pass.
create or replace function private.organization_governance(q jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.gov_structure_v2(q); $$;
revoke all on function public.organization_governance(jsonb) from public,anon,authenticated;
grant execute on function public.organization_governance(jsonb) to authenticated;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and (p.proname like 'gov_%' or p.proname='organization_governance') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end $$;
grant execute on function private.organization_governance(jsonb),private.gov_structure_v2(jsonb) to authenticated;
comment on function public.organization_governance(jsonb) is '0.20.36 positions and affiliate directory only. Meetings and voting are not enabled.';
notify pgrst,'reload schema';
