-- 0.20.41: one current reaction per account/message, with a private change history.
create table private.message_reactions (
 message_id uuid not null references public.communication_messages(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 reaction text not null check(reaction in ('wrestling','strength','fire','trophy','gold','clap','heart','thumbsup','laugh','celebrate','question','emphasis')),
 updated_at timestamptz not null default now(), primary key(message_id,user_id)
);
create index message_reactions_user on private.message_reactions(user_id);
create table private.message_reaction_events (
 id bigint generated always as identity primary key,
 message_id uuid not null references public.communication_messages(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 reaction text, created_at timestamptz not null default now()
);
create index message_reaction_events_message on private.message_reaction_events(message_id,created_at);
create index message_reaction_events_user on private.message_reaction_events(user_id);
alter table private.message_reactions enable row level security;
alter table private.message_reaction_events enable row level security;
revoke all on private.message_reactions,private.message_reaction_events from public,anon,authenticated;
revoke all on sequence private.message_reaction_events_id_seq from public,anon,authenticated;

create function private.message_reactions_request(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare
 uid uuid=auth.uid(); tid uuid; mid uuid; ids uuid[]; reaction_key text; prior text;
 t public.communication_threads%rowtype; member public.communication_thread_members%rowtype;
 may_react boolean; blocked boolean; result jsonb; participant record;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal account required';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16000 then raise exception 'Invalid reaction request';end if;
 tid:=(p_data->>'thread_id')::uuid;
 select * into t from public.communication_threads where id=tid and archived_at is null;
 if not found or t.is_safety_test then raise exception 'Conversation is unavailable for reactions';end if;
 select * into member from public.communication_thread_members where thread_id=tid and user_id=uid and left_at is null;
 if not found or not private.communication_user_belongs_to_team(t.team_id,uid) then raise exception 'Conversation access required';end if;
 blocked:=t.kind='direct' and exists(
  select 1 from public.communication_blocks b join public.communication_thread_members other on other.thread_id=tid and other.left_at is null and other.user_id<>uid
  where b.team_id=t.team_id and ((b.user_id=uid and b.blocked_user_id=other.user_id) or (b.blocked_user_id=uid and b.user_id=other.user_id))
 );
 may_react:=member.can_post and not blocked;
 -- Respect current parent controls, including changes made after the chat began.
 for participant in select m.user_id from public.communication_thread_members m where m.thread_id=tid and m.left_at is null and m.member_role<>'guardian_mirror' loop
  if (participant.user_id=uid or t.kind='direct') and private.communication_user_is_minor(t.team_id,participant.user_id) then
   if not private.communication_minor_capability(t.team_id,participant.user_id,
    case when t.kind='direct' then case when exists(select 1 from public.communication_thread_members other where other.thread_id=tid and other.left_at is null and other.member_role<>'guardian_mirror' and other.user_id<>participant.user_id and not private.communication_user_is_minor(t.team_id,other.user_id)) then 'coach_to_athlete' else 'peer_to_peer' end
         when t.kind='group' then 'group_chat' else 'team_chat' end) then may_react:=false;end if;
  end if;
 end loop;
 if p_action='set' then
  if not may_react then raise exception 'Reactions are not allowed in this conversation';end if;
  if not p_data ? 'reaction' or jsonb_typeof(p_data->'reaction') not in ('string','null') then raise exception 'Choose a reaction';end if;
  reaction_key:=p_data->>'reaction';
  if reaction_key is not null and reaction_key not in ('wrestling','strength','fire','trophy','gold','clap','heart','thumbsup','laugh','celebrate','question','emphasis') then raise exception 'Choose an available reaction';end if;
  mid:=(p_data->>'message_id')::uuid;
  -- Serialize selections and removal with edits/deletion of the target message.
  perform 1 from public.communication_messages where id=mid and thread_id=tid and deleted_at is null and not is_simulated for update;
  if not found then raise exception 'Message is unavailable for reactions';end if;
  select reaction into prior from private.message_reactions where message_id=mid and user_id=uid;
  if prior is distinct from reaction_key then
   if reaction_key is null then delete from private.message_reactions where message_id=mid and user_id=uid;
   else insert into private.message_reactions(message_id,user_id,reaction) values(mid,uid,reaction_key)
    on conflict(message_id,user_id) do update set reaction=excluded.reaction,updated_at=now();end if;
   insert into private.message_reaction_events(message_id,user_id,reaction) values(mid,uid,reaction_key);
  end if;
  ids:=array[mid];
 elsif p_action='list' then
  if jsonb_typeof(p_data->'message_ids') is distinct from 'array' or jsonb_array_length(p_data->'message_ids')>100 then raise exception 'Choose up to 100 messages';end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into ids from jsonb_array_elements_text(p_data->'message_ids');
  if exists(select 1 from unnest(ids) x where not exists(select 1 from public.communication_messages m where m.id=x and m.thread_id=tid)) then raise exception 'Messages must belong to this conversation';end if;
 else raise exception 'Unknown reaction action';end if;
 select coalesce(jsonb_agg(jsonb_build_object('message_id',m.id,'reactions',q.items) order by m.created_at,m.id),'[]'::jsonb) into result
 from public.communication_messages m cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object('key',g.reaction,'count',g.total,'mine',g.mine,'people',g.people) order by g.reaction),'[]'::jsonb) items from (
   select r.reaction,count(*) total,bool_or(r.user_id=uid) mine,
    (array_agg(private.communication_person_name(t.team_id,r.user_id) order by r.updated_at,r.user_id))[1:12] people
   from private.message_reactions r where r.message_id=m.id group by r.reaction
  ) g
 ) q where m.id=any(ids) and m.thread_id=tid and m.deleted_at is null and not m.is_simulated;
 return jsonb_build_object('can_react',may_react,'messages',result);
end $function$;
revoke all on function private.message_reactions_request(text,jsonb) from public,anon,authenticated;

create function public.message_reactions_request(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language sql security definer set search_path='' as $function$
 select private.message_reactions_request(p_action,p_data);
$function$;
revoke all on function public.message_reactions_request(text,jsonb) from public,anon;
grant execute on function public.message_reactions_request(text,jsonb) to authenticated;
