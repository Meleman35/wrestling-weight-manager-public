-- Separate read-only review. No thread membership, messaging gate or parent authority is granted.
create table private.conversation_review_settings(id boolean primary key default true check(id),enabled boolean not null default false);
insert into private.conversation_review_settings default values;
create table private.conversation_reviewers(
 team_id uuid not null references public.teams(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 membership_id uuid not null references public.team_memberships(id) on delete cascade,
 role_key text not null, approved_by uuid not null references auth.users(id),
 approved_at timestamptz not null default clock_timestamp(),accepted_at timestamptz,
 active boolean not null default true,primary key(team_id,user_id)
);
create table private.conversation_review_events(
 id uuid primary key default gen_random_uuid(),team_id uuid not null references public.teams(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,subject_id uuid references auth.users(id) on delete set null,
 event text not null check(event in ('assigned','accepted','revoked','left','viewed')),
 thread_id uuid references public.communication_threads(id) on delete set null,
 created_at timestamptz not null default clock_timestamp()
);
create index conversation_review_event_lookup on private.conversation_review_events(team_id,actor_id,thread_id,created_at desc);
alter table private.conversation_review_settings enable row level security;
alter table private.conversation_reviewers enable row level security;
alter table private.conversation_review_events enable row level security;
revoke all on private.conversation_review_settings,private.conversation_reviewers,private.conversation_review_events from public,anon,authenticated;

create function private.conversation_review_admin(tid uuid,uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select uid is not null and not exists(select 1 from private.team_logins where user_id=uid) and (
 exists(select 1 from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active
  and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and m.permissions->>'team_admin'='true')))
 or exists(select 1 from public.teams t join public.organization_memberships o on o.organization_id=t.organization_id
  where t.id=tid and o.user_id=uid and o.role='organization_admin'))
$$;
create function private.conversation_review_adult(tid uuid,uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select uid is not null and not exists(select 1 from private.team_logins where user_id=uid)
 and exists(select 1 from auth.users u where u.id=uid and u.email_confirmed_at is not null)
 and exists(select 1 from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active
  and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->>'staff_role' in ('team_mom','team_leader','volunteer_coach','club_president','limited_staff'))))
 and not exists(select 1 from public.team_memberships own join public.athletes a on a.id=own.athlete_id
  left join public.athlete_private_identity i on i.athlete_id=a.id where own.user_id=uid and own.role='athlete'
  and (coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'
    or (own.active and coalesce(i.birth_date,a.birth_date) is null)))
$$;
create function private.conversation_review_minor(tid uuid,uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
 left join public.athlete_private_identity i on i.athlete_id=a.id
 where m.team_id=tid and m.user_id=uid and m.role='athlete' and m.active
 and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'))
$$;
create function private.conversation_review_assigned(tid uuid,uid uuid,accepted boolean default true)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.conversation_review_settings where id and enabled)
 and private.conversation_review_adult(tid,uid)
 and exists(select 1 from private.conversation_reviewers r join public.team_memberships m on m.id=r.membership_id
  where r.team_id=tid and r.user_id=uid and r.active and (not accepted or r.accepted_at is not null)
  and m.team_id=tid and m.user_id=uid and m.active
  and r.role_key=case when m.role='manager' then m.permissions->>'staff_role' else m.role::text end
  and private.conversation_review_admin(tid,r.approved_by))
$$;
create function private.conversation_review_covered(th uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.communication_threads t where t.id=th and t.kind in ('direct','group')
 and t.archived_at is null and not coalesce(t.is_safety_test,false)
 and exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null
   and m.member_role='participant' and private.conversation_review_minor(t.team_id,m.user_id))
 and exists(select 1 from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null
   and m.member_role='participant' and private.communication_authorized_adult(t.team_id,m.user_id)
   and not private.conversation_review_minor(t.team_id,m.user_id)
   and not exists(select 1 from private.team_logins where user_id=m.user_id)))
$$;
create function private.conversation_review_can_view(th uuid,uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.conversation_review_covered(th) and exists(select 1 from public.communication_threads t
 where t.id=th and private.conversation_review_assigned(t.team_id,uid))
$$;
revoke all on function private.conversation_review_admin(uuid,uuid),private.conversation_review_adult(uuid,uuid),
 private.conversation_review_minor(uuid,uuid),private.conversation_review_assigned(uuid,uuid,boolean),
 private.conversation_review_covered(uuid),private.conversation_review_can_view(uuid,uuid) from public,anon,authenticated;

create function private.conversation_review_request(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid();tid uuid;uid uuid;th uuid;mem public.team_memberships%rowtype;
 result jsonb;admin boolean;offset_value integer;before_time timestamptz;before_id uuid;
begin
 if actor is null or exists(select 1 from private.team_logins where user_id=actor) then raise exception 'Use your personal account.' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'Invalid review request.';end if;
 tid:=nullif(p_data->>'team_id','')::uuid;th:=nullif(p_data->>'thread_id','')::uuid;
 if th is not null then select team_id into tid from public.communication_threads where id=th;end if;
 if tid is null or not private.communication_user_belongs_to_team(tid,actor) then raise exception 'Team access required.' using errcode='42501';end if;
 admin:=private.conversation_review_admin(tid,actor);
 if p_action='context' then
  return jsonb_build_object('enabled',exists(select 1 from private.conversation_review_settings where id and enabled),
   'admin',admin,'assigned',private.conversation_review_assigned(tid,actor,false),'accepted',private.conversation_review_assigned(tid,actor));
 end if;
 if not exists(select 1 from private.conversation_review_settings where id and enabled) then raise exception 'Conversation review is not enabled yet.';end if;
 if p_action='observers' then
  if th is null or not(private.communication_can_view_thread(th,actor) or private.conversation_review_can_view(th,actor)) then raise exception 'Conversation access required.';end if;
  select coalesce(jsonb_agg(jsonb_build_object('name',private.communication_person_name(tid,r.user_id),'role',r.role_key) order by r.approved_at),'[]') into result
  from private.conversation_reviewers r where r.team_id=tid and private.conversation_review_assigned(tid,r.user_id)
   and private.conversation_review_covered(th);
  return result;
 elsif p_action='manage' then
  if not admin then raise exception 'Team administrator access required.' using errcode='42501';end if;
  select coalesce(jsonb_agg(x.item order by x.item->>'name'),'[]') into result from (
   select distinct on(m.user_id) jsonb_build_object('user_id',m.user_id,'name',private.communication_person_name(tid,m.user_id),
    'role',case when m.role='manager' then m.permissions->>'staff_role' else m.role::text end,
    'assigned',coalesce(r.active,false),'accepted',private.conversation_review_assigned(tid,m.user_id),
    'eligible',private.conversation_review_adult(tid,m.user_id)) item
   from public.team_memberships m left join private.conversation_reviewers r on r.team_id=tid and r.user_id=m.user_id
   where m.team_id=tid and m.active and m.role in ('head_coach','assistant_coach','manager')
    and not exists(select 1 from private.team_logins where user_id=m.user_id)
   order by m.user_id,case m.role when 'head_coach' then 1 when 'assistant_coach' then 2 else 3 end,m.id
  ) x;
  return result;
 elsif p_action in ('assign','revoke','accept','leave') then
  if p_action in ('assign','revoke') then
   if not admin then raise exception 'Team administrator access required.' using errcode='42501';end if;
   uid:=nullif(p_data->>'user_id','')::uuid;
  else uid:=actor;end if;
  if uid is null then raise exception 'Choose an adult team member.';end if;
  perform 1 from public.teams where id=tid for update;
  if p_action in ('assign','revoke') and not private.conversation_review_admin(tid,actor) then raise exception 'Team administrator access required.';end if;
  if p_action='assign' then
   if p_data->'confirm_adult' is distinct from 'true'::jsonb then raise exception 'Verify this adult and their authority under your team policies.';end if;
   if not private.conversation_review_adult(tid,uid) then raise exception 'Choose a confirmed personal adult staff account. Check any under-18 or unknown-age athlete membership.';end if;
   select * into mem from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active
    and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->>'staff_role' in ('team_mom','team_leader','volunteer_coach','club_president','limited_staff')))
    order by case m.role when 'head_coach' then 1 when 'assistant_coach' then 2 else 3 end,m.id limit 1;
   insert into private.conversation_reviewers(team_id,user_id,membership_id,role_key,approved_by)
   values(tid,uid,mem.id,case when mem.role='manager' then mem.permissions->>'staff_role' else mem.role::text end,actor)
   on conflict(team_id,user_id) do update set membership_id=excluded.membership_id,role_key=excluded.role_key,
    approved_by=actor,approved_at=clock_timestamp(),active=true,accepted_at=null;
  elsif p_action='accept' then
   if p_data->'acknowledge' is distinct from 'true'::jsonb or not private.conversation_review_assigned(tid,actor,false) then raise exception 'Review the responsibility statement and confirm your assignment.';end if;
   update private.conversation_reviewers set accepted_at=clock_timestamp() where team_id=tid and user_id=actor and active;
  else
   update private.conversation_reviewers set active=false,accepted_at=null where team_id=tid and user_id=uid;
   if not found then raise exception 'Reviewer assignment not found.';end if;
  end if;
  insert into private.conversation_review_events(team_id,actor_id,subject_id,event)
  values(tid,actor,uid,case p_action when 'assign' then 'assigned' when 'accept' then 'accepted' when 'revoke' then 'revoked' else 'left' end);
  return jsonb_build_object('saved',true);
 elsif p_action='inbox' then
  if not private.conversation_review_assigned(tid,actor) then raise exception 'An accepted, current adult reviewer assignment is required.' using errcode='42501';end if;
  offset_value:=least(greatest(coalesce((p_data->>'offset')::integer,0),0),5000);
  select coalesce(jsonb_agg(x.item order by x.last_at desc,x.id),'[]') into result from (
   select t.id,coalesce(lm.created_at,t.created_at) last_at,jsonb_build_object('id',t.id,
    'title',coalesce(nullif(t.title,''),(select string_agg(private.communication_person_name(tid,m.user_id),' · ' order by m.joined_at) from public.communication_thread_members m where m.thread_id=t.id and m.left_at is null and m.member_role='participant'),'Conversation'),
    'last_at',coalesce(lm.created_at,t.created_at),'safety_flags',(select count(*) from public.communication_messages msg where msg.thread_id=t.id and msg.deleted_at is null and msg.safety_level in ('medium','high'))) item
   from public.communication_threads t left join lateral(select created_at from public.communication_messages where thread_id=t.id order by created_at desc limit 1) lm on true
   where t.team_id=tid and private.conversation_review_covered(t.id)
   order by coalesce(lm.created_at,t.created_at) desc,t.id limit 51 offset offset_value
  ) x;
  return result;
 elsif p_action='media' then
  if th is null or not private.conversation_review_can_view(th,actor) then raise exception 'Reviewer access ended.' using errcode='42501';end if;
  select jsonb_build_object('path',a.storage_path) into result
  from public.communication_attachments a join public.communication_messages m on m.id=a.message_id and m.thread_id=a.thread_id
  where a.id=nullif(p_data->>'attachment_id','')::uuid and a.thread_id=th and a.removed_at is null and m.deleted_at is null
   and split_part(a.storage_path,'/',1)=tid::text
   and exists(select 1 from public.communication_threads source where source.id::text=split_part(a.storage_path,'/',2)
    and source.team_id=tid and coalesce(source.merged_into_thread_id,source.id)=th);
  if result is null then raise exception 'This media is unavailable.' using errcode='42501';end if;
  return result;
 elsif p_action='check' then
  if th is null or not private.conversation_review_can_view(th,actor) then raise exception 'Reviewer access ended.' using errcode='42501';end if;
  return jsonb_build_object('allowed',true);
 elsif p_action='messages' then
  if th is null or not private.conversation_review_can_view(th,actor) then raise exception 'Reviewer access to this conversation is required.' using errcode='42501';end if;
  before_time:=nullif(p_data->>'before_at','')::timestamptz;before_id:=nullif(p_data->>'before_id','')::uuid;
  if (before_time is null)<>(before_id is null) then raise exception 'Invalid message page.';end if;
  select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id desc),'[]') into result from (
   select m.id,m.created_at,jsonb_build_object('id',m.id,'at',m.created_at,'sender',private.communication_person_name(tid,m.sender_user_id),
    'body',case when m.deleted_at is null then m.body else 'Message removed' end,'safety_level',m.safety_level,
    'attachments',case when m.deleted_at is not null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'mime',a.mime_type,'name',a.file_name)) from public.communication_attachments a where a.message_id=m.id and a.thread_id=th and a.removed_at is null),'[]'::jsonb) end) item
   from public.communication_messages m where m.thread_id=th and (before_time is null or (m.created_at,m.id)<(before_time,before_id))
   order by m.created_at desc,m.id desc limit 81
  ) x;
  insert into private.conversation_review_events(team_id,actor_id,event,thread_id)
   select tid,actor,'viewed',th where not exists(select 1 from private.conversation_review_events where team_id=tid and actor_id=actor and thread_id=th and event='viewed' and created_at>now()-interval '5 minutes');
  return result;
 end if;
 raise exception 'Unsupported reviewer action.';
end $$;
revoke all on function private.conversation_review_request(text,jsonb) from public,anon;
grant execute on function private.conversation_review_request(text,jsonb) to authenticated;
create function public.conversation_review_request(p_action text,p_data jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$select private.conversation_review_request(p_action,p_data)$$;
revoke all on function public.conversation_review_request(text,jsonb) from public,anon;
grant execute on function public.conversation_review_request(text,jsonb) to authenticated;
