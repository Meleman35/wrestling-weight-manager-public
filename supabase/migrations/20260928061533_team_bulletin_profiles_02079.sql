-- Team identities expose only explicit profile fields. Following never grants membership.
create table private.team_social_profiles(team_id uuid primary key references public.teams(id),bio text not null default '' check(length(bio)<=1200),discoverable boolean not null default false,revision int not null default 1);
create table private.team_social_follows(source_id uuid references public.teams(id),target_id uuid references public.teams(id),requested_by uuid not null references public.profiles(id),status text not null check(status in ('pending','approved','denied','blocked')),updated_at timestamptz not null default now(),primary key(source_id,target_id),check(source_id<>target_id));
create index team_social_follow_target on private.team_social_follows(target_id,status);
create table private.bulletin_parent_choices(team_id uuid references public.teams(id),athlete_id uuid references public.athletes(id),guardian_id uuid references public.profiles(id),can_view boolean not null default false,can_post boolean not null default false,review_posts boolean not null default true,share_followers boolean not null default false,revision int not null default 1,primary key(team_id,athlete_id,guardian_id));
create table private.bulletin_posts(id uuid primary key default gen_random_uuid(),team_id uuid not null references public.teams(id),author_id uuid not null references public.profiles(id),client_id uuid not null,body text not null default '' check(length(body)<=4000),kind text not null check(kind in ('note','photo','clipping','announcement')),color text not null check(color in ('yellow','blue','pink','white')),audience text not null default 'team' check(audience in ('team','followers')),status text not null default 'draft' check(status in ('draft','pending','published','rejected','removed')),photo_path text unique,coach_approved uuid references public.profiles(id),parent_approved uuid references public.profiles(id),pinned boolean not null default false,revision int not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(team_id,author_id,client_id));
create index bulletin_team_feed on private.bulletin_posts(team_id,pinned desc,created_at desc,id);
create table private.bulletin_reports(id uuid primary key default gen_random_uuid(),post_id uuid not null references private.bulletin_posts(id),reporter_id uuid not null references public.profiles(id),reason text not null check(length(reason) between 1 and 1000),created_at timestamptz not null default now(),unique(post_id,reporter_id));
alter table private.team_social_profiles enable row level security;
alter table private.team_social_follows enable row level security;
alter table private.bulletin_parent_choices enable row level security;
alter table private.bulletin_posts enable row level security;
alter table private.bulletin_reports enable row level security;
revoke all on private.team_social_profiles,private.team_social_follows,private.bulletin_parent_choices,private.bulletin_posts,private.bulletin_reports from public,anon,authenticated;

create function private.board_personal(u uuid) returns boolean language sql stable security definer set search_path='' as $$select u is not null and not exists(select 1 from private.team_logins where user_id=u);$$;
create function private.board_minor(u uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id left join public.athlete_private_identity i on i.athlete_id=a.id where m.user_id=u and m.role='athlete' and m.active and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years'));$$;
create function private.board_member(t uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$select private.board_personal(u) and (exists(select 1 from public.team_memberships where team_id=t and user_id=u and active) or private.communication_user_is_staff(t,u));$$;
create function private.board_leader(t uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$select private.board_personal(u) and not private.board_minor(u) and private.communication_authorized_adult(t,u);$$;
create function private.board_guardian(t uuid,a uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$select private.board_personal(u) and not private.board_minor(u) and exists(select 1 from public.athlete_guardians g join public.team_memberships m on m.athlete_id=g.athlete_id and m.user_id=g.guardian_user_id and m.team_id=t and m.role='parent_guardian' and m.active where g.athlete_id=a and g.guardian_user_id=u);$$;
create function private.board_permission(t uuid,u uuid,cap text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a uuid;v boolean;found_athlete boolean=false;
begin
 if not private.board_member(t,u) then return false;end if;
 if not private.board_minor(u) then return true;end if;
 for a in select athlete_id from public.team_memberships where team_id=t and user_id=u and role='athlete' and active loop
  found_athlete:=true;
  select bool_or(case cap when 'view' then c.can_view when 'post' then c.can_view and c.can_post when 'followers' then c.can_view and c.can_post and c.share_followers else false end)
   and not bool_or(case cap when 'view' then not c.can_view when 'post' then not(c.can_view and c.can_post) when 'followers' then not(c.can_view and c.can_post and c.share_followers) else true end)
   into v from private.bulletin_parent_choices c where c.team_id=t and c.athlete_id=a and private.board_guardian(t,a,c.guardian_id);
  if not coalesce(v,false) then return false;end if;
 end loop;
 return found_athlete;
end $$;
create function private.board_media(t uuid,u uuid,upload boolean) returns boolean language sql stable security definer set search_path='' as $$select private.board_permission(t,u,case when upload then 'post' else 'view' end) and (not private.board_minor(u) or (exists(select 1 from public.team_memberships where team_id=t and user_id=u and role='athlete' and active) and not exists(select 1 from public.team_memberships m left join public.athlete_chat_permissions c on c.team_id=m.team_id and c.athlete_id=m.athlete_id where m.team_id=t and m.user_id=u and m.role='athlete' and m.active and not coalesce(case when upload then c.media_send_group else c.media_view end,false))));$$;
create function private.board_parent_review(t uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$select private.board_minor(u) and exists(select 1 from public.team_memberships m join public.athlete_guardians g on g.athlete_id=m.athlete_id left join private.bulletin_parent_choices c on c.team_id=t and c.athlete_id=m.athlete_id and c.guardian_id=g.guardian_user_id where m.team_id=t and m.user_id=u and m.role='athlete' and m.active and private.board_guardian(t,m.athlete_id,g.guardian_user_id) and coalesce(c.review_posts,true));$$;
create function private.board_author_guardian(t uuid,u uuid,g uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=u and m.role='athlete' and m.active and private.board_guardian(t,m.athlete_id,g)) and private.board_minor(u);$$;
create function private.board_post_access(p private.bulletin_posts,u uuid,media boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if not private.board_personal(u) or p.status='removed' then return false;end if;
 if p.status='draft' then return p.author_id=u and private.board_permission(p.team_id,u,'view') and (not media or private.board_media(p.team_id,u,false));end if;
 if private.board_member(p.team_id,u) and (private.board_leader(p.team_id,u) or private.board_author_guardian(p.team_id,p.author_id,u) or (p.author_id=u and private.board_permission(p.team_id,u,'view'))) then return not media or private.board_media(p.team_id,u,false);end if;
 if p.status<>'published' then return false;end if;
 if private.board_minor(p.author_id) and (not private.board_permission(p.team_id,p.author_id,'post') or (private.board_parent_review(p.team_id,p.author_id) and (p.parent_approved is null or not private.board_author_guardian(p.team_id,p.author_id,p.parent_approved)))) then return false;end if;
 if private.board_permission(p.team_id,u,'view') then return not media or private.board_media(p.team_id,u,false);end if;
 if p.audience<>'followers' or (private.board_minor(p.author_id) and not private.board_permission(p.team_id,p.author_id,'followers')) then return false;end if;
 return exists(select 1 from private.team_social_profiles sp join private.team_social_follows f on f.target_id=sp.team_id and f.status='approved' where sp.team_id=p.team_id and sp.discoverable and private.board_permission(f.source_id,u,'view') and (not media or private.board_media(f.source_id,u,false)));
end $$;
create function private.board_storage(path text,upload boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare p private.bulletin_posts%rowtype;u uuid=auth.uid();
begin
 select * into p from private.bulletin_posts where photo_path=path;
 if p.id is null then return false;end if;
 if upload then return p.status='draft' and p.author_id=u and private.board_media(p.team_id,u,true);end if;
 return private.board_post_access(p,u,true);
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('team-bulletins','team-bulletins',false,5242880,array['image/jpeg','image/png','image/webp']);
revoke all on function private.board_personal(uuid),private.board_minor(uuid),private.board_member(uuid,uuid),private.board_leader(uuid,uuid),private.board_guardian(uuid,uuid,uuid),private.board_permission(uuid,uuid,text),private.board_media(uuid,uuid,boolean),private.board_parent_review(uuid,uuid),private.board_author_guardian(uuid,uuid,uuid),private.board_post_access(private.bulletin_posts,uuid,boolean),private.board_storage(text,boolean) from public,anon,authenticated;
grant execute on function private.board_storage(text,boolean) to authenticated;
create policy bulletin_upload on storage.objects for insert to authenticated with check(bucket_id='team-bulletins' and private.board_storage(name,true));
create policy bulletin_read on storage.objects for select to authenticated using(bucket_id='team-bulletins' and private.board_storage(name,false));

create function private.team_board_request(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();t uuid=(p_data->>'team_id')::uuid;target uuid;aid uuid;cid uuid;pid uuid;leader boolean;p private.bulletin_posts%rowtype;sp private.team_social_profiles%rowtype;pref private.bulletin_parent_choices%rowtype;rows jsonb;incoming jsonb;outgoing jsonb;body text;audience text;photo boolean;parent_ok boolean;coach_ok boolean;v jsonb;
begin
 if not private.board_personal(u) then raise exception 'Use your personal account';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'Invalid board request';end if;
 if t is null or not private.board_member(t,u) then raise exception 'Current team membership required';end if;
 leader:=private.board_leader(t,u);
 if p_action in ('parent','save_parent') then
  aid:=(p_data->>'athlete_id')::uuid;
  if aid is null or not private.board_guardian(t,aid,u) or not exists(select 1 from public.athletes a left join public.athlete_private_identity i on i.athlete_id=a.id where a.id=aid and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years')) then raise exception 'A current linked parent of a minor athlete is required';end if;
  perform pg_advisory_xact_lock(hashtextextended(t::text||aid::text||u::text,80));
  select * into pref from private.bulletin_parent_choices where team_id=t and athlete_id=aid and guardian_id=u for update;
  if p_action='save_parent' then
   v:=p_data->'values';if (p_data->>'revision')::int is distinct from coalesce(pref.revision,0) then raise exception 'Preferences changed. Reload before saving';end if;
   if jsonb_typeof(v->'can_view') is distinct from 'boolean' or jsonb_typeof(v->'can_post') is distinct from 'boolean' or jsonb_typeof(v->'review_posts') is distinct from 'boolean' or jsonb_typeof(v->'share_followers') is distinct from 'boolean' then raise exception 'Choose all four preferences';end if;
   insert into private.bulletin_parent_choices(team_id,athlete_id,guardian_id,revision) values(t,aid,u,0) on conflict do nothing;
   update private.bulletin_parent_choices set can_view=(v->>'can_view')::boolean,can_post=(v->>'can_post')::boolean,review_posts=(v->>'review_posts')::boolean,share_followers=(v->>'share_followers')::boolean,revision=revision+1 where team_id=t and athlete_id=aid and guardian_id=u returning * into pref;
  end if;
  return jsonb_build_object('revision',coalesce(pref.revision,0),'can_view',coalesce(pref.can_view,false),'can_post',coalesce(pref.can_post,false),'review_posts',coalesce(pref.review_posts,true),'share_followers',coalesce(pref.share_followers,false));
 end if;
 if p_action='profile_save' then
  if not leader then raise exception 'Team leader permission required';end if;
  insert into private.team_social_profiles(team_id) values(t) on conflict do nothing;
  select * into sp from private.team_social_profiles where team_id=t for update;
  if (p_data->>'revision')::int is distinct from sp.revision then raise exception 'Team profile changed. Refresh before saving';end if;
  body:=trim(coalesce(p_data->>'bio',''));if length(body)>1200 or jsonb_typeof(p_data->'discoverable') is distinct from 'boolean' then raise exception 'Add a short team description and choose visibility';end if;
  update private.team_social_profiles set bio=body,discoverable=(p_data->>'discoverable')::boolean,revision=revision+1 where team_id=t returning * into sp;return to_jsonb(sp);
 end if;
 if not private.board_permission(t,u,'view') and not leader then raise exception 'A parent needs to enable bulletin board access in Parent Controls';end if;
 if p_action='search' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from (select q.team_id id,tm.name,q.bio from private.team_social_profiles q join public.teams tm on tm.id=q.team_id where q.discoverable and q.team_id<>t and tm.name ilike '%'||left(coalesce(p_data->>'query',''),80)||'%' and not exists(select 1 from private.team_social_follows f where f.status='blocked' and ((f.source_id=t and f.target_id=q.team_id) or (f.target_id=t and f.source_id=q.team_id))) order by tm.name,tm.id limit 50) x;return rows;
 end if;
 target:=coalesce((p_data->>'target')::uuid,t);
 if p_action in ('follow','review_follow','unfollow','block_follow','unblock_follow') then
  if not leader or target=t then raise exception 'A team leader must manage connections to another team';end if;
  if p_action='follow' then
   if not exists(select 1 from private.team_social_profiles where team_id=target and discoverable) or exists(select 1 from private.team_social_follows where status='blocked' and ((source_id=t and target_id=target) or (target_id=t and source_id=target))) then raise exception 'Team connection unavailable';end if;
   if (select count(*) from private.team_social_follows where source_id=t and updated_at>now()-interval '1 hour')>=30 then raise exception 'Please pause before requesting more teams';end if;
   insert into private.team_social_follows(source_id,target_id,requested_by,status) values(t,target,u,'pending') on conflict do nothing;
  elsif p_action='review_follow' then
   if p_data->>'decision' not in ('approved','denied') then raise exception 'Accept or deny the follow request';end if;
   update private.team_social_follows set status=p_data->>'decision',updated_at=now() where source_id=target and target_id=t and status='pending';
  elsif p_action='unfollow' then delete from private.team_social_follows where source_id=t and target_id=target and status<>'blocked';
  elsif p_action='unblock_follow' then delete from private.team_social_follows where source_id=t and target_id=target and status='blocked';
  else insert into private.team_social_follows(source_id,target_id,requested_by,status) values(t,target,u,'blocked') on conflict(source_id,target_id) do update set status='blocked',updated_at=now();delete from private.team_social_follows where source_id=target and target_id=t and status<>'blocked';end if;
  return jsonb_build_object('saved',true);
 end if;
 if p_action='context' then
  select * into sp from private.team_social_profiles where team_id=target;
  if target<>t and (not coalesce(sp.discoverable,false) or exists(select 1 from private.team_social_follows where status='blocked' and ((source_id=t and target_id=target) or (target_id=t and source_id=target)))) then raise exception 'Team profile unavailable';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.team_id,'name',tm.name) order by tm.name),'[]') into outgoing from private.team_social_follows f join private.team_social_profiles q on q.team_id=f.target_id and q.discoverable join public.teams tm on tm.id=q.team_id where f.source_id=target and f.status='approved';
  select coalesce(jsonb_agg(jsonb_build_object('id',q.team_id,'name',tm.name) order by tm.name),'[]') into incoming from private.team_social_follows f join private.team_social_profiles q on q.team_id=f.source_id and q.discoverable join public.teams tm on tm.id=q.team_id where f.target_id=target and f.status='approved';
  select coalesce(jsonb_agg(jsonb_build_object('id',f.source_id,'name',tm.name)),'[]') into rows from private.team_social_follows f join public.teams tm on tm.id=f.source_id where f.target_id=t and target=t and leader and f.status='pending';
  return jsonb_build_object('id',target,'name',(select name from public.teams where id=target),'bio',coalesce(sp.bio,''),'discoverable',coalesce(sp.discoverable,false),'revision',coalesce(sp.revision,1),'leader',leader and target=t,'can_follow',leader and target<>t,'can_post',target=t and private.board_permission(t,u,'post'),'can_photo',target=t and private.board_media(t,u,true),'can_share',target=t and private.board_permission(t,u,'followers'),'following',outgoing,'followed_by',incoming,'requests',rows,'blocked_teams',case when leader and target=t then (select coalesce(jsonb_agg(jsonb_build_object('id',f.target_id,'name',tm.name)),'[]') from private.team_social_follows f join public.teams tm on tm.id=f.target_id where f.source_id=t and f.status='blocked') else '[]'::jsonb end,'managed_followers',case when leader and target=t then (select coalesce(jsonb_agg(jsonb_build_object('id',f.source_id,'name',tm.name)),'[]') from private.team_social_follows f join public.teams tm on tm.id=f.source_id where f.target_id=t and f.status='approved') else '[]'::jsonb end,'follow_status',(select status from private.team_social_follows where source_id=t and target_id=target));
 end if;
 if p_action='feed' then
  if target<>t and (not exists(select 1 from private.team_social_profiles where team_id=target and discoverable) or not exists(select 1 from private.team_social_follows where source_id=t and target_id=target and status='approved')) then return '[]';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pinned desc,x.created_at desc,x.id desc),'[]') into rows from (
   select q.id,q.body,q.kind,q.color,q.audience,q.status,q.pinned,q.revision,q.created_at,q.author_id=u is_mine,
    case when q.audience='followers' and target<>t then 'Team bulletin' else coalesce(pr.display_name,'Team member') end author_name,
    case when private.board_post_access(q,u,true) then q.photo_path end photo_path,
    q.photo_path is not null and not private.board_post_access(q,u,true) photo_hidden,
    leader and target=t can_moderate,private.board_author_guardian(q.team_id,q.author_id,u) can_parent_review,
    q.coach_approved is not null coach_approved,q.parent_approved is not null parent_approved,
    case when leader and target=t then (select coalesce(jsonb_agg(jsonb_build_object('reason',r.reason,'created_at',r.created_at)),'[]') from private.bulletin_reports r where r.post_id=q.id) else '[]'::jsonb end reports
   from private.bulletin_posts q left join public.profiles pr on pr.id=q.author_id
   where q.team_id=target and q.status<>'removed' and private.board_post_access(q,u)
    and (nullif(p_data->>'before_at','') is null or (q.pinned,q.created_at,q.id)<((p_data->>'before_pinned')::boolean,(p_data->>'before_at')::timestamptz,(p_data->>'before_id')::uuid))
   order by q.pinned desc,q.created_at desc,q.id desc limit 40) x;return rows;
 end if;
 if p_action='create' then
  if not private.board_permission(t,u,'post') then raise exception 'Parent permission to post is required';end if;
  cid:=(p_data->>'client_id')::uuid;if cid is null then raise exception 'A post ID is required';end if;
  select * into p from private.bulletin_posts where team_id=t and author_id=u and client_id=cid;if p.id is not null then return to_jsonb(p)||jsonb_build_object('photo_uploaded',p.photo_path is not null and exists(select 1 from storage.objects where bucket_id='team-bulletins' and name=p.photo_path));end if;
  if (select count(*) from private.bulletin_posts where author_id=u and created_at>now()-interval '1 hour')>=20 then raise exception 'Please pause before posting more';end if;
  body:=trim(coalesce(p_data->>'body',''));photo:=coalesce((p_data->>'photo')::boolean,false);audience:=coalesce(p_data->>'audience','team');
  if length(body)>4000 or (body='' and not photo) or audience not in ('team','followers') then raise exception 'Add a note or picture and choose an audience';end if;
  if audience='followers' and not private.board_permission(t,u,'followers') then raise exception 'Parent permission is required to share outside the team';end if;
  if photo and not private.board_media(t,u,true) then raise exception 'Parent media-sending permission is required';end if;
  pid:=gen_random_uuid();insert into private.bulletin_posts(id,team_id,author_id,client_id,body,kind,color,audience,photo_path) values(pid,t,u,cid,body,coalesce(p_data->>'kind','note'),coalesce(p_data->>'color','yellow'),audience,case when photo then t::text||'/'||u::text||'/'||pid::text||'.jpg' end) returning * into p;return to_jsonb(p);
 end if;
 pid:=(p_data->>'id')::uuid;select * into p from private.bulletin_posts where id=pid and team_id=target for update;
 if p.id is null or not private.board_post_access(p,u) then raise exception 'Post access required';end if;
 if p_action='report' then
  body:=trim(coalesce(p_data->>'reason',''));if length(body) not between 1 and 1000 then raise exception 'Describe the concern';end if;
  insert into private.bulletin_reports(post_id,reporter_id,reason) values(pid,u,body) on conflict(post_id,reporter_id) do update set reason=excluded.reason,created_at=now();return jsonb_build_object('saved',true);
 end if;
 if target<>t then raise exception 'Manage posts from their own team';end if;
 if (p_data->>'revision')::int is distinct from p.revision then raise exception 'Post changed. Refresh before saving';end if;
 if p_action='submit' then
  if p.author_id<>u or p.status<>'draft' or not private.board_permission(t,u,'post') then raise exception 'Only your permitted draft can be submitted';end if;
  if p.photo_path is not null and (not private.board_media(t,u,true) or not exists(select 1 from storage.objects where bucket_id='team-bulletins' and name=p.photo_path)) then raise exception 'Finish uploading the picture before posting';end if;
  if p.audience='followers' and not private.board_permission(t,u,'followers') then raise exception 'Parent permission to share with followers is required';end if;
  coach_ok:=leader;parent_ok:=not private.board_parent_review(t,u);
  update private.bulletin_posts set coach_approved=case when coach_ok then u end,status=case when coach_ok and parent_ok then 'published' else 'pending' end,revision=revision+1,updated_at=now() where id=pid returning * into p;
 elsif p_action in ('approve','reject') then
  if p.status<>'pending' or not (leader or private.board_author_guardian(t,p.author_id,u)) then raise exception 'A coach or current parent must review this pending post';end if;
  if p_action='reject' then update private.bulletin_posts set status='rejected',revision=revision+1,updated_at=now() where id=pid returning * into p;
  else
   coach_ok:=leader or p.coach_approved is not null;parent_ok:=not private.board_parent_review(t,p.author_id) or private.board_author_guardian(t,p.author_id,u) or (p.parent_approved is not null and private.board_author_guardian(t,p.author_id,p.parent_approved));
   if not private.board_permission(t,p.author_id,'post') or (p.audience='followers' and not private.board_permission(t,p.author_id,'followers')) then raise exception 'The author’s parent posting permission is off';end if;
   update private.bulletin_posts set coach_approved=case when leader then u else coach_approved end,parent_approved=case when private.board_author_guardian(t,p.author_id,u) then u else parent_approved end,status=case when coach_ok and parent_ok then 'published' else 'pending' end,revision=revision+1,updated_at=now() where id=pid returning * into p;
  end if;
 elsif p_action='remove' then
  if p.author_id<>u and not leader and not private.board_author_guardian(t,p.author_id,u) then raise exception 'Only the author, coach or linked parent may remove a post';end if;
  update private.bulletin_posts set status='removed',revision=revision+1,updated_at=now() where id=pid returning * into p;
 elsif p_action='pin' then
  if not leader or p.status<>'published' or jsonb_typeof(p_data->'pinned') is distinct from 'boolean' then raise exception 'Coaches can pin published bulletins';end if;
  update private.bulletin_posts set pinned=(p_data->>'pinned')::boolean,revision=revision+1,updated_at=now() where id=pid returning * into p;
 else raise exception 'Unknown board action';end if;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(u,'bulletin_'||p_action,'bulletin_post',pid,jsonb_build_object('team_id',t,'revision',p.revision));
 return to_jsonb(p);
end $$;
revoke all on function private.team_board_request(text,jsonb) from public,anon;
grant execute on function private.team_board_request(text,jsonb) to authenticated;
create function public.team_board_request(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.team_board_request(p_action,p_data);$$;
revoke all on function public.team_board_request(text,jsonb) from public,anon;
grant execute on function public.team_board_request(text,jsonb) to authenticated;
