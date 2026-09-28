-- Profile conversations are independent of team membership and never grant team access.
create table private.profile_chats(
 id uuid primary key default gen_random_uuid(),
 profile_a uuid not null references private.wrestling_profiles(id),
 profile_b uuid not null references private.wrestling_profiles(id),
 user_a uuid not null references public.profiles(id),user_b uuid not null references public.profiles(id),
 requested_by uuid not null references public.profiles(id),
 status text not null default 'pending' check(status in ('pending','accepted','denied','cancelled')),
 allow_a boolean not null default true,allow_b boolean not null default true,
 revision integer not null default 1,requested_at timestamptz not null default now(),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(profile_a<profile_b),check(user_a<>user_b),check(requested_by in (user_a,user_b)),unique(profile_a,profile_b)
);
create index profile_chats_user_a on private.profile_chats(user_a,updated_at desc);
create index profile_chats_user_b on private.profile_chats(user_b,updated_at desc);
create table private.profile_chat_guardian_choices(
 chat_id uuid not null references private.profile_chats(id),profile_id uuid not null references private.wrestling_profiles(id),
 guardian_id uuid not null references public.profiles(id),allowed boolean not null,updated_at timestamptz not null default now(),
 primary key(chat_id,profile_id,guardian_id)
);
create table private.profile_chat_messages(
 id uuid primary key default gen_random_uuid(),chat_id uuid not null references private.profile_chats(id),
 sender_id uuid not null references public.profiles(id),client_id uuid not null,
 body text not null check(length(body) between 1 and 4000),
 safety_level text not null check(safety_level in ('none','low','medium','high')),
 created_at timestamptz not null default now(),unique(chat_id,sender_id,client_id)
);
create index profile_chat_messages_timeline on private.profile_chat_messages(chat_id,created_at desc,id desc);
create index profile_chat_messages_rate on private.profile_chat_messages(sender_id,created_at desc);
create table private.profile_chat_reads(chat_id uuid not null references private.profile_chats(id),user_id uuid not null references public.profiles(id),read_at timestamptz not null default now(),primary key(chat_id,user_id));
create table private.profile_chat_reports(
 id uuid primary key default gen_random_uuid(),chat_id uuid not null references private.profile_chats(id),
 message_id uuid references private.profile_chat_messages(id),reported_by uuid not null references public.profiles(id),
 reason text not null check(length(reason) between 1 and 1000),created_at timestamptz not null default now()
);
alter table private.profile_chats enable row level security;
alter table private.profile_chat_guardian_choices enable row level security;
alter table private.profile_chat_messages enable row level security;
alter table private.profile_chat_reads enable row level security;
alter table private.profile_chat_reports enable row level security;
revoke all on private.profile_chats,private.profile_chat_guardian_choices,private.profile_chat_messages,private.profile_chat_reads,private.profile_chat_reports from public,anon,authenticated;

create function private.profile_chat_user(pid uuid) returns uuid language sql stable security definer set search_path='' as $$
 select case when p.user_id is not null then p.user_id else
  (select case when count(distinct m.user_id)=1 then min(m.user_id::text)::uuid end
   from public.athletes a join public.team_memberships m on m.athlete_id=a.id and m.role='athlete' and m.active
   where a.profile_id=p.athlete_profile_id) end
 from private.wrestling_profiles p where p.id=pid
$$;
create function private.profile_chat_minor(pid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.wrestling_profiles p join public.athletes a on a.profile_id=p.athlete_profile_id
  left join public.athlete_private_identity i on i.athlete_id=a.id where p.id=pid and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'))
 or exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
  left join public.athlete_private_identity i on i.athlete_id=a.id where m.user_id=private.profile_chat_user(pid) and m.role='athlete' and m.active
  and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'))
$$;
create function private.profile_chat_guardians(pid uuid) returns uuid[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(distinct g.guardian_user_id),'{}'::uuid[]) from private.wrestling_profiles p
 join public.athletes a on a.profile_id=p.athlete_profile_id join public.athlete_guardians g on g.athlete_id=a.id
 join public.team_memberships m on m.athlete_id=a.id and m.user_id=g.guardian_user_id and m.role='parent_guardian' and m.active
 where p.id=pid and private.profile_chat_minor(pid) and g.guardian_user_id is not null
 and not exists(select 1 from private.team_logins l where l.user_id=g.guardian_user_id)
$$;
create function private.profile_chat_participant(c private.profile_chats,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select (u=c.user_a and private.profile_chat_user(c.profile_a)=u) or (u=c.user_b and private.profile_chat_user(c.profile_b)=u)
$$;
create function private.profile_chat_access(c private.profile_chats,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select u is not null and not exists(select 1 from private.team_logins l where l.user_id=u)
 and (private.profile_chat_participant(c,u) or u=any(private.profile_chat_guardians(c.profile_a)||private.profile_chat_guardians(c.profile_b)))
$$;
create function private.profile_chat_pair_allowed(pa uuid,pb uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare ua uuid=private.profile_chat_user(pa);ub uuid=private.profile_chat_user(pb);ma boolean=private.profile_chat_minor(pa);mb boolean=private.profile_chat_minor(pb);minor_id uuid;adult_id uuid;
begin
 if ua is null or ub is null or ua=ub or exists(select 1 from private.team_logins where user_id in (ua,ub)) then return false;end if;
 if exists(select 1 from private.wrestling_follows where status='blocked' and ((source_id=pa and target_id=pb) or (source_id=pb and target_id=pa)))
 or exists(select 1 from public.communication_blocks where (user_id=ua and blocked_user_id=ub) or (user_id=ub and blocked_user_id=ua)) then return false;end if;
 if ma<>mb then
  minor_id:=case when ma then pa else pb end;adult_id:=case when ma then ub else ua end;
  -- A follow never promotes an unrelated adult into a coach or guardian.
  if not (adult_id=any(private.profile_chat_guardians(minor_id)) or exists(
   select 1 from private.wrestling_profiles p join public.athletes a on a.profile_id=p.athlete_profile_id
   join public.team_memberships m on m.athlete_id=a.id and m.role='athlete' and m.active
   where p.id=minor_id and private.communication_authorized_adult(m.team_id,adult_id))) then return false;end if;
 end if;
 return true;
end $$;
create function private.profile_chat_gate(c private.profile_chats) returns text language plpgsql stable security definer set search_path='' as $$
declare pid uuid;other_pid uuid;cap text;guardians uuid[];
begin
 if private.profile_chat_user(c.profile_a) is distinct from c.user_a or private.profile_chat_user(c.profile_b) is distinct from c.user_b then return 'A profile account connection has changed';end if;
 if not private.profile_chat_pair_allowed(c.profile_a,c.profile_b) then return 'This profile connection is unavailable for chat';end if;
 if c.status<>'accepted' then return case c.status when 'pending' then 'Waiting for the recipient to accept' when 'denied' then 'Chat request declined' else 'Chat request withdrawn' end;end if;
 if not c.allow_a or not c.allow_b then return 'Chat stopped in conversation preferences';end if;
 foreach pid in array array[c.profile_a,c.profile_b] loop
  if private.profile_chat_minor(pid) then
   other_pid:=case when pid=c.profile_a then c.profile_b else c.profile_a end;
   cap:=case when private.profile_chat_minor(other_pid) then 'peer_to_peer' else 'coach_to_athlete' end;
   if not exists(select 1 from private.wrestling_profiles p join public.athletes a on a.profile_id=p.athlete_profile_id
     join public.team_memberships m on m.athlete_id=a.id and m.user_id=private.profile_chat_user(pid) and m.role='athlete' and m.active
     where p.id=pid)
    or exists(select 1 from private.wrestling_profiles p join public.athletes a on a.profile_id=p.athlete_profile_id
     join public.team_memberships m on m.athlete_id=a.id and m.user_id=private.profile_chat_user(pid) and m.role='athlete' and m.active
     where p.id=pid and not coalesce((select case cap when 'peer_to_peer' then cp.peer_to_peer else cp.coach_to_athlete end from public.athlete_chat_permissions cp where cp.team_id=m.team_id and cp.athlete_id=a.id),false)) then
     return 'A parent needs to enable the athlete’s direct-chat category on their active teams';end if;
   guardians:=private.profile_chat_guardians(pid);
   if cardinality(guardians)=0 then return 'A current linked parent is required';end if;
   if not exists(select 1 from private.profile_chat_guardian_choices x where x.chat_id=c.id and x.profile_id=pid and x.guardian_id=any(guardians) and x.allowed)
    or exists(select 1 from private.profile_chat_guardian_choices x where x.chat_id=c.id and x.profile_id=pid and x.guardian_id=any(guardians) and not x.allowed) then
     return 'Waiting for parent approval of this profile chat';end if;
  end if;
 end loop;
 return '';
end $$;
create function private.profile_chat_card(c private.profile_chats) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid=auth.uid();gate text;participant boolean;read_at timestamptz;alerts_only boolean=false;guards jsonb;unread bigint;
begin
 if not private.profile_chat_access(c,u) then return null;end if;
 participant:=private.profile_chat_participant(c,u);gate:=private.profile_chat_gate(c);
 select r.read_at into read_at from private.profile_chat_reads r where r.chat_id=c.id and r.user_id=u;
 if not participant then
  select exists(select 1 from public.communication_preferences cp join public.team_memberships tm on tm.team_id=cp.team_id and tm.user_id=u and tm.role='parent_guardian' and tm.active
   join public.athletes a on a.id=tm.athlete_id join private.wrestling_profiles p on p.athlete_profile_id=a.profile_id
   where cp.user_id=u and cp.guardian_alerts_only and p.id in (c.profile_a,c.profile_b)) into alerts_only;
 end if;
 select count(*) into unread from private.profile_chat_messages m where m.chat_id=c.id and m.sender_id<>u and m.created_at>coalesce(read_at,'-infinity') and (not alerts_only or m.safety_level in ('medium','high'));
 select coalesce(jsonb_agg(jsonb_build_object('profile_id',p.id,'name',p.name,'my_choice',g.allowed,'can_manage',u=any(private.profile_chat_guardians(p.id))) order by p.name),'[]') into guards
 from private.wrestling_profiles p left join private.profile_chat_guardian_choices g on g.chat_id=c.id and g.profile_id=p.id and g.guardian_id=u
 where p.id in (c.profile_a,c.profile_b) and private.profile_chat_minor(p.id);
 return jsonb_build_object('id',c.id,'profile_a',c.profile_a,'profile_b',c.profile_b,'name_a',(select name from private.wrestling_profiles where id=c.profile_a),'name_b',(select name from private.wrestling_profiles where id=c.profile_b),
  'my_profile',case when participant then case when u=c.user_a then c.profile_a else c.profile_b end end,
  'status',c.status,'revision',c.revision,'incoming',participant and c.requested_by<>u,'participant',participant,
  'my_allowed',case when u=c.user_a then c.allow_a when u=c.user_b then c.allow_b else false end,
  'can_send',participant and gate='','reason',gate,'guardians',guards,'guardian_mirror',not participant,
  'unread',unread,'needs_response',participant and c.status='pending' and c.requested_by<>u,
  'needs_parent_review',not participant and c.status in ('pending','accepted') and exists(select 1 from jsonb_array_elements(guards) x where x->>'can_manage'='true' and x->'my_choice'='null'::jsonb),
  'updated_at',c.updated_at);
end $$;

create function private.profile_connections_request(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();pid uuid;target uuid;ua uuid;ub uuid;cid uuid;mid uuid;clientid uuid;c private.profile_chats%rowtype;
 rows jsonb;result jsonb;incoming jsonb;outgoing jsonb;body text;normalized text;level text;allowed boolean;own boolean;before_at timestamptz;before_id uuid;
begin
 if u is null or exists(select 1 from private.team_logins where user_id=u) then raise exception 'Use your personal account';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'Invalid profile chat request';end if;
 if p_action='connections' then
  pid:=(p_data->>'profile_id')::uuid;if not private.wrestling_profile_visible(pid) then raise exception 'Profile unavailable';end if;
  own:=private.wrestling_profile_self(pid) or private.wrestling_profile_manager(pid);
  -- Shared lists exclude family-only pins, private profiles, pending follows and blocked connections.
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'name',x.name) order by x.name,x.id),'[]') into outgoing from (
   select p.id,p.name from private.wrestling_follows f join private.wrestling_profiles p on p.id=f.target_id
   where f.source_id=pid and f.status='approved' and p.discoverable and private.wrestling_profile_visible(p.id) order by p.name,p.id limit 100) x;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'name',x.name) order by x.name,x.id),'[]') into incoming from (
   select p.id,p.name from private.wrestling_follows f join private.wrestling_profiles p on p.id=f.source_id
   where f.target_id=pid and f.status='approved' and p.discoverable and private.wrestling_profile_visible(p.id) order by p.name,p.id limit 100) x;
  return jsonb_build_object('following',outgoing,'followed_by',incoming);
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(x.card order by x.updated_at desc,x.id),'[]') into rows from (
   select c0.id,c0.updated_at,private.profile_chat_card(c0) card from private.profile_chats c0
   where private.profile_chat_access(c0,u) order by c0.updated_at desc,c0.id limit 100) x;
  return rows;
 end if;
 if p_action in ('pair','request') then
  pid:=(p_data->>'profile_id')::uuid;target:=(p_data->>'target')::uuid;
  if pid is null or target is null or pid=target or not private.wrestling_profile_self(pid) or private.profile_chat_user(pid) is distinct from u then raise exception 'Choose your own connected profile to chat';end if;
  ua:=private.profile_chat_user(least(pid,target));ub:=private.profile_chat_user(greatest(pid,target));
  select * into c from private.profile_chats where profile_a=least(pid,target) and profile_b=greatest(pid,target);
  allowed:=private.wrestling_profile_visible(target) and private.profile_chat_pair_allowed(pid,target)
    and exists(select 1 from private.wrestling_follows where status='approved' and ((source_id=pid and target_id=target) or (source_id=target and target_id=pid)));
  if p_action='pair' then return jsonb_build_object('chat',case when c.id is not null then private.profile_chat_card(c) end,'can_request',allowed and (c.id is null or c.status='cancelled'),
    'following',exists(select 1 from private.wrestling_follows where source_id=pid and target_id=target and status='approved'),
    'followed_by',exists(select 1 from private.wrestling_follows where target_id=pid and source_id=target and status='approved'),
    'reason',case when allowed then '' else 'Chat needs an approved follow, a connected account and permitted contact. Athlete safeguards still apply.' end);end if;
  if not allowed then raise exception 'This follow connection is not available for chat';end if;
  perform pg_advisory_xact_lock(hashtextextended(least(pid,target)::text||greatest(pid,target)::text,79));
  select * into c from private.profile_chats where profile_a=least(pid,target) and profile_b=greatest(pid,target) for update;
  if c.id is not null and c.status<>'cancelled' then return private.profile_chat_card(c);end if;
  if c.id is not null and c.requested_at>now()-interval '10 minutes' then raise exception 'Please wait before sending another chat request';end if;
  if (select count(*) from private.profile_chats where requested_by=u and requested_at>now()-interval '1 hour')>=20 then raise exception 'Please pause before sending more chat requests';end if;
  if c.id is null then
   insert into private.profile_chats(profile_a,profile_b,user_a,user_b,requested_by) values(least(pid,target),greatest(pid,target),ua,ub,u) returning * into c;
  else
   if c.user_a is distinct from ua or c.user_b is distinct from ub then raise exception 'The connected profile account changed';end if;
   update private.profile_chats set requested_by=u,status='pending',requested_at=now(),updated_at=now(),revision=revision+1 where id=c.id returning * into c;
  end if;
  return private.profile_chat_card(c);
 end if;
 cid:=(p_data->>'id')::uuid;select * into c from private.profile_chats where id=cid for update;
 if c.id is null or not private.profile_chat_access(c,u) then raise exception 'Conversation access required';end if;
 if p_action='read' then
  before_at:=nullif(p_data->>'before_at','')::timestamptz;before_id:=nullif(p_data->>'before_id','')::uuid;
  if before_at is null then insert into private.profile_chat_reads(chat_id,user_id) values(cid,u) on conflict(chat_id,user_id) do update set read_at=excluded.read_at;end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]') into rows from (
   select m.id,m.body,m.safety_level,m.created_at,m.sender_id=u is_mine,
    case when m.sender_id=c.user_a then (select name from private.wrestling_profiles where id=c.profile_a) else (select name from private.wrestling_profiles where id=c.profile_b) end sender_name
   from private.profile_chat_messages m where m.chat_id=cid and (before_at is null or (m.created_at,m.id)<(before_at,coalesce(before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
   order by m.created_at desc,m.id desc limit 60) x;
  return jsonb_build_object('chat',private.profile_chat_card(c),'messages',rows,'more',jsonb_array_length(rows)=60);
 end if;
 if p_action='send' then
  if not private.profile_chat_participant(c,u) then raise exception 'Guardian mirrors are read-only';end if;
  if private.profile_chat_gate(c)<>'' then raise exception '%',private.profile_chat_gate(c);end if;
  body:=trim(coalesce(p_data->>'body',''));clientid:=(p_data->>'client_id')::uuid;
  if clientid is null or length(body) not between 1 and 4000 then raise exception 'Write a message up to 4,000 characters';end if;
  select id into mid from private.profile_chat_messages where chat_id=cid and sender_id=u and client_id=clientid;
  if mid is not null then return jsonb_build_object('message_id',mid);end if;
  if (select count(*) from private.profile_chat_messages where sender_id=u and created_at>now()-interval '1 minute')>=30 then raise exception 'Please pause before sending more messages';end if;
  normalized:=lower(translate(body,'’‘`',''''));level:=private.communication_scan_level(normalized);
  if private.profile_chat_minor(c.profile_a)<>private.profile_chat_minor(c.profile_b) then
   if normalized ~ '(keep|this is).{0,24}(a )?secret|(don''?t|do not).{0,30}(tell|show).{0,25}(parent|mom|dad|guardian|coach|anyone)|delete.{0,16}(message|chat|conversation)|(nude|naked).{0,24}(photo|picture|pic)|(dm|message|contact|add).{0,12}(me|my).{0,18}(snapchat|instagram|whatsapp|signal|telegram|discord)|(message|talk).{0,10}(privately|somewhere else|off app)' then level:='high';
   elsif level not in ('medium','high') and (body ~ '(^|[^0-9])(\+?1[ .-]?)?\(?[2-9][0-9]{2}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}([^0-9]|$)' or normalized ~ '(my|personal|cell|phone).{0,10}number.{0,8}(is|:)|text me.{0,8}(at|on)') then level:='medium';end if;
  end if;
  insert into private.profile_chat_messages(chat_id,sender_id,client_id,body,safety_level) values(cid,u,clientid,body,level) returning id into mid;
  update private.profile_chats set updated_at=now() where id=cid;
  return jsonb_build_object('message_id',mid);
 end if;
 if p_action='report' then
  mid:=nullif(p_data->>'message_id','')::uuid;body:=trim(coalesce(p_data->>'reason',''));
  if length(body) not between 1 and 1000 or (mid is not null and not exists(select 1 from private.profile_chat_messages where id=mid and chat_id=cid)) then raise exception 'Choose a message in this chat and describe the concern';end if;
  insert into private.profile_chat_reports(chat_id,message_id,reported_by,reason) values(cid,mid,u,body);
  if private.profile_chat_participant(c,u) then update private.profile_chats set allow_a=case when user_a=u then false else allow_a end,allow_b=case when user_b=u then false else allow_b end,revision=revision+1,updated_at=now() where id=cid;end if;
  return jsonb_build_object('saved',true);
 end if;
 if (p_data->>'revision')::int is distinct from c.revision then raise exception 'Chat preferences changed. Refresh before saving';end if;
 if p_action in ('accept','deny','withdraw','preferences') then
  if not private.profile_chat_participant(c,u) then raise exception 'Only a participant can change chat consent';end if;
  if p_action in ('accept','deny') then
   if c.requested_by=u or c.status not in ('pending','denied') then raise exception 'Only the recipient can accept or deny this request';end if;
   update private.profile_chats set status=case when p_action='accept' then 'accepted' else 'denied' end,revision=revision+1,updated_at=now() where id=cid returning * into c;
  elsif p_action='withdraw' then
   if c.requested_by<>u or c.status<>'pending' then raise exception 'Only a pending request can be withdrawn';end if;
   update private.profile_chats set status='cancelled',revision=revision+1,updated_at=now() where id=cid returning * into c;
  else
   if c.status<>'accepted' or jsonb_typeof(p_data->'allowed') is distinct from 'boolean' then raise exception 'Choose a preference for an accepted chat';end if;
   update private.profile_chats set allow_a=case when user_a=u then (p_data->>'allowed')::boolean else allow_a end,allow_b=case when user_b=u then (p_data->>'allowed')::boolean else allow_b end,revision=revision+1,updated_at=now() where id=cid returning * into c;
  end if;
 elsif p_action='guardian' then
  pid:=(p_data->>'profile_id')::uuid;
  if pid is null or pid not in (c.profile_a,c.profile_b) or not u=any(private.profile_chat_guardians(pid)) or jsonb_typeof(p_data->'allowed') is distinct from 'boolean' then raise exception 'Current linked parent permission is required';end if;
  insert into private.profile_chat_guardian_choices(chat_id,profile_id,guardian_id,allowed) values(cid,pid,u,(p_data->>'allowed')::boolean)
   on conflict(chat_id,profile_id,guardian_id) do update set allowed=excluded.allowed,updated_at=now();
  update private.profile_chats set revision=revision+1,updated_at=now() where id=cid returning * into c;
 else raise exception 'Unknown profile chat action';end if;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(u,'profile_chat_'||p_action,'profile_chat',cid,jsonb_build_object('revision',c.revision));
 return private.profile_chat_card(c);
end $$;
revoke all on function private.profile_chat_user(uuid),private.profile_chat_minor(uuid),private.profile_chat_guardians(uuid),private.profile_chat_participant(private.profile_chats,uuid),private.profile_chat_access(private.profile_chats,uuid),private.profile_chat_pair_allowed(uuid,uuid),private.profile_chat_gate(private.profile_chats),private.profile_chat_card(private.profile_chats) from public,anon,authenticated;
revoke all on function private.profile_connections_request(text,jsonb) from public,anon;
grant execute on function private.profile_connections_request(text,jsonb) to authenticated;
create function public.profile_connections_request(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.profile_connections_request(p_action,p_data);$$;
revoke all on function public.profile_connections_request(text,jsonb) from public,anon;
grant execute on function public.profile_connections_request(text,jsonb) to authenticated;
