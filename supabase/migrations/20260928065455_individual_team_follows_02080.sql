-- Individual team connections do not grant team membership or broaden existing audiences.
create table private.profile_team_follows(
 profile_id uuid not null references private.wrestling_profiles(id), team_id uuid not null references public.teams(id),
 requested_by uuid not null references public.profiles(id), status text not null check(status in ('pending','approved','denied','blocked')),
 revision integer not null default 1, updated_at timestamptz not null default now(),primary key(profile_id,team_id));
create index profile_team_follow_target on private.profile_team_follows(team_id,status);
alter table private.profile_team_follows enable row level security;
revoke all on private.profile_team_follows from public,anon,authenticated;
alter table private.bulletin_parent_choices add column share_individuals boolean not null default false;
alter table private.bulletin_posts drop constraint bulletin_posts_audience_check;
alter table private.bulletin_posts add constraint bulletin_posts_audience_check check(audience in ('team','followers','all_followers'));

create function private.profile_team_actor(pid uuid,media boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m record;found_team boolean=false;u uuid=auth.uid();
begin
 if not private.board_personal(u) then return false;end if;
 if private.wrestling_profile_manager(pid) then return true;end if;
 if not private.wrestling_profile_self(pid) or not exists(select 1 from private.wrestling_profiles where id=pid and sharing->>'outgoing_follow'='true') then return false;end if;
 for m in select distinct tm.team_id from public.team_memberships tm join public.athletes a on a.id=tm.athlete_id join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where w.id=pid and tm.user_id=u and tm.role='athlete' and tm.active loop
  found_team:=true;
  if not private.board_permission(m.team_id,u,'view') or (media and not private.board_media(m.team_id,u,false)) then return false;end if;
 end loop;
 return found_team;
end $$;
revoke all on function private.profile_team_actor(uuid,boolean) from public,anon,authenticated;
create or replace function private.board_permission(t uuid,u uuid,cap text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a uuid;v boolean;found_athlete boolean=false;
begin
 if not private.board_member(t,u) then return false;end if;
 if not private.board_minor(u) then return true;end if;
 for a in select athlete_id from public.team_memberships where team_id=t and user_id=u and role='athlete' and active loop
  found_athlete:=true;
  select bool_or(case cap when 'view' then c.can_view when 'post' then c.can_view and c.can_post when 'individuals' then c.can_view and c.can_post and c.share_followers and c.share_individuals when 'followers' then c.can_view and c.can_post and c.share_followers else false end)
   and not bool_or(case cap when 'view' then not c.can_view when 'post' then not(c.can_view and c.can_post) when 'individuals' then not(c.can_view and c.can_post and c.share_followers and c.share_individuals) when 'followers' then not(c.can_view and c.can_post and c.share_followers) else true end)
   into v from private.bulletin_parent_choices c where c.team_id=t and c.athlete_id=a and private.board_guardian(t,a,c.guardian_id);
  if not coalesce(v,false) then return false;end if;
 end loop;
 return found_athlete;
end $$;
create or replace function private.board_post_access(p private.bulletin_posts,u uuid,media boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if not private.board_personal(u) or p.status='removed' then return false;end if;
 if p.status='draft' then return p.author_id=u and private.board_permission(p.team_id,u,'view') and (not media or private.board_media(p.team_id,u,false));end if;
 if private.board_member(p.team_id,u) and (private.board_leader(p.team_id,u) or private.board_author_guardian(p.team_id,p.author_id,u) or (p.author_id=u and private.board_permission(p.team_id,u,'view'))) then return not media or private.board_media(p.team_id,u,false);end if;
 if p.status<>'published' then return false;end if;
 if private.board_minor(p.author_id) and (not private.board_permission(p.team_id,p.author_id,'post') or (private.board_parent_review(p.team_id,p.author_id) and (p.parent_approved is null or not private.board_author_guardian(p.team_id,p.author_id,p.parent_approved)))) then return false;end if;
 if private.board_permission(p.team_id,u,'view') then return not media or private.board_media(p.team_id,u,false);end if;
 if p.audience not in ('followers','all_followers') or (private.board_minor(p.author_id) and not private.board_permission(p.team_id,p.author_id,case when p.audience='all_followers' then 'individuals' else 'followers' end)) then return false;end if;
 return (p.audience='all_followers' and u=auth.uid() and exists(select 1 from private.profile_team_follows f join private.team_social_profiles sp on sp.team_id=f.team_id and sp.discoverable where f.team_id=p.team_id and f.status='approved' and private.profile_team_actor(f.profile_id,media))) or exists(select 1 from private.team_social_profiles sp join private.team_social_follows f on f.target_id=sp.team_id and f.status='approved' where sp.team_id=p.team_id and sp.discoverable and private.board_permission(f.source_id,u,'view') and (not media or private.board_media(f.source_id,u,false)));
end $$;
create or replace function private.team_board_request(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
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
   update private.bulletin_parent_choices set can_view=(v->>'can_view')::boolean,can_post=(v->>'can_post')::boolean,review_posts=(v->>'review_posts')::boolean,share_followers=(v->>'share_followers')::boolean,share_individuals=coalesce((v->>'share_individuals')::boolean,false),revision=revision+1 where team_id=t and athlete_id=aid and guardian_id=u returning * into pref;
  end if;
  return jsonb_build_object('revision',coalesce(pref.revision,0),'can_view',coalesce(pref.can_view,false),'can_post',coalesce(pref.can_post,false),'review_posts',coalesce(pref.review_posts,true),'share_followers',coalesce(pref.share_followers,false),'share_individuals',coalesce(pref.share_individuals,false));
 end if;
 if p_action in ('review_individual','block_individual','unblock_individual') then
  if not leader then raise exception 'Team leader permission required';end if;
  pid:=(p_data->>'profile_id')::uuid;
  perform 1 from private.profile_team_follows where team_id=t and profile_id=pid for update;
  if not found then raise exception 'Follower no longer available';end if;
  if (p_data->>'revision')::int is distinct from (select revision from private.profile_team_follows where team_id=t and profile_id=pid) then raise exception 'Follow request changed. Refresh first';end if;
  if p_action='review_individual' then
   if p_data->>'decision' not in ('approved','denied') then raise exception 'Accept or deny this request';end if;
   update private.profile_team_follows set status=p_data->>'decision',revision=revision+1,updated_at=now() where team_id=t and profile_id=pid and status='pending';
  elsif p_action='block_individual' then update private.profile_team_follows set status='blocked',revision=revision+1,updated_at=now() where team_id=t and profile_id=pid;
  else delete from private.profile_team_follows where team_id=t and profile_id=pid and status='blocked';end if;
  return '{"saved":true}';
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
  return jsonb_build_object('id',target,'name',(select name from public.teams where id=target),'bio',coalesce(sp.bio,''),'discoverable',coalesce(sp.discoverable,false),'revision',coalesce(sp.revision,1),'leader',leader and target=t,'can_follow',leader and target<>t,'can_post',target=t and private.board_permission(t,u,'post'),'can_photo',target=t and private.board_media(t,u,true),'can_share',target=t and private.board_permission(t,u,'followers'),'can_share_individuals',target=t and private.board_permission(t,u,'individuals'),'individuals',case when leader and target=t then (select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'status',f.status,'revision',f.revision) order by w.name),'[]') from private.profile_team_follows f join private.wrestling_profiles w on w.id=f.profile_id where f.team_id=t) else '[]'::jsonb end,'following',outgoing,'followed_by',incoming,'requests',rows,'blocked_teams',case when leader and target=t then (select coalesce(jsonb_agg(jsonb_build_object('id',f.target_id,'name',tm.name)),'[]') from private.team_social_follows f join public.teams tm on tm.id=f.target_id where f.source_id=t and f.status='blocked') else '[]'::jsonb end,'managed_followers',case when leader and target=t then (select coalesce(jsonb_agg(jsonb_build_object('id',f.source_id,'name',tm.name)),'[]') from private.team_social_follows f join public.teams tm on tm.id=f.source_id where f.target_id=t and f.status='approved') else '[]'::jsonb end,'follow_status',(select status from private.team_social_follows where source_id=t and target_id=target));
 end if;
 if p_action='feed' then
  if target<>t and (not exists(select 1 from private.team_social_profiles where team_id=target and discoverable) or not exists(select 1 from private.team_social_follows where source_id=t and target_id=target and status='approved')) then return '[]';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pinned desc,x.created_at desc,x.id desc),'[]') into rows from (
   select q.id,q.body,q.kind,q.color,q.audience,q.status,q.pinned,q.revision,q.created_at,q.author_id=u is_mine,
    case when q.audience in ('followers','all_followers') and target<>t then 'Team bulletin' else coalesce(pr.display_name,'Team member') end author_name,
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
  if length(body)>4000 or (body='' and not photo) or audience not in ('team','followers','all_followers') then raise exception 'Add a note or picture and choose an audience';end if;
  if audience in ('followers','all_followers') and not private.board_permission(t,u,case when audience='all_followers' then 'individuals' else 'followers' end) then raise exception 'Parent permission is required to share outside the team';end if;
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
  if p.audience in ('followers','all_followers') and not private.board_permission(t,u,case when p.audience='all_followers' then 'individuals' else 'followers' end) then raise exception 'Parent permission to share with followers is required';end if;
  coach_ok:=leader;parent_ok:=not private.board_parent_review(t,u);
  update private.bulletin_posts set coach_approved=case when coach_ok then u end,status=case when coach_ok and parent_ok then 'published' else 'pending' end,revision=revision+1,updated_at=now() where id=pid returning * into p;
 elsif p_action in ('approve','reject') then
  if p.status<>'pending' or not (leader or private.board_author_guardian(t,p.author_id,u)) then raise exception 'A coach or current parent must review this pending post';end if;
  if p_action='reject' then update private.bulletin_posts set status='rejected',revision=revision+1,updated_at=now() where id=pid returning * into p;
  else
   coach_ok:=leader or p.coach_approved is not null;parent_ok:=not private.board_parent_review(t,p.author_id) or private.board_author_guardian(t,p.author_id,u) or (p.parent_approved is not null and private.board_author_guardian(t,p.author_id,p.parent_approved));
   if not private.board_permission(t,p.author_id,'post') or (p.audience in ('followers','all_followers') and not private.board_permission(t,p.author_id,case when p.audience='all_followers' then 'individuals' else 'followers' end)) then raise exception 'The author’s parent posting permission is off';end if;
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

create function private.profile_team_request(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();pid uuid=(p_data->>'profile_id')::uuid;t uuid=(p_data->>'target')::uuid;r jsonb;p private.bulletin_posts%rowtype;body text;
begin
 if not private.board_personal(u) then raise exception 'Use your personal account';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>12000 then raise exception 'Invalid team request';end if;
 if p_action='mine' then
  perform private.wrestling_profiles_request('mine','{}');
  select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'self',private.wrestling_profile_self(w.id),'can_follow',private.profile_team_actor(w.id)) order by private.wrestling_profile_self(w.id) desc,w.name),'[]') into r from private.wrestling_profiles w where private.wrestling_profile_self(w.id) or private.wrestling_profile_manager(w.id);return r;
 end if;
 if not private.profile_team_actor(pid) then raise exception 'A parent must allow following and board viewing in Parent Controls';end if;
 if p_action in ('search','list') then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into r from (
   select sp.team_id id,tm.name,sp.bio,f.status from private.team_social_profiles sp join public.teams tm on tm.id=sp.team_id left join private.profile_team_follows f on f.team_id=sp.team_id and f.profile_id=pid
   where sp.discoverable and coalesce(f.status,'')<>'blocked' and (p_action='search' or f.status in ('pending','approved')) and (p_action='list' or tm.name ilike '%'||left(coalesce(p_data->>'query',''),80)||'%') order by tm.name,tm.id limit 100) x;return r;
 end if;
 if p_action='unfollow' then
  delete from private.profile_team_follows where profile_id=pid and team_id=t and status in ('pending','approved');return '{"saved":true}';
 end if;
 if not exists(select 1 from private.team_social_profiles where team_id=t and discoverable) or exists(select 1 from private.profile_team_follows where profile_id=pid and team_id=t and status='blocked') then raise exception 'Team profile unavailable';end if;
 if p_action='follow' then
  perform pg_advisory_xact_lock(hashtextextended(pid::text,80));
  if (select count(*) from private.profile_team_follows where profile_id=pid and updated_at>now()-interval '1 hour')>=30 then raise exception 'Please pause before requesting more teams';end if;
  insert into private.profile_team_follows(profile_id,team_id,requested_by,status) values(pid,t,u,'pending') on conflict do nothing;return '{"saved":true}';
 end if;
 if p_action='context' then
  select jsonb_build_object('id',t,'name',tm.name,'bio',sp.bio,'leader',false,'can_post',false,'can_photo',false,'can_share',false,'can_follow',true,'following','[]'::jsonb,'followed_by','[]'::jsonb,'follow_status',(select status from private.profile_team_follows where profile_id=pid and team_id=t)) into r from private.team_social_profiles sp join public.teams tm on tm.id=sp.team_id where sp.team_id=t;return r;
 end if;
 if not exists(select 1 from private.profile_team_follows where profile_id=pid and team_id=t and status='approved') then
  if p_action='feed' then return '[]';end if;raise exception 'Approved follow required';
 end if;
 if p_action='feed' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pinned desc,x.created_at desc,x.id desc),'[]') into r from (
   select q.id,q.body,q.kind,q.color,q.audience,q.status,q.pinned,q.revision,q.created_at,'Team bulletin'::text author_name,
    case when private.profile_team_actor(pid,true) and private.board_post_access(q,u,true) then q.photo_path end photo_path,
    q.photo_path is not null and not (private.profile_team_actor(pid,true) and private.board_post_access(q,u,true)) photo_hidden
   from private.bulletin_posts q where q.team_id=t and q.audience='all_followers' and q.status='published' and private.board_post_access(q,u)
   and (nullif(p_data->>'before_at','') is null or (q.pinned,q.created_at,q.id)<((p_data->>'before_pinned')::boolean,(p_data->>'before_at')::timestamptz,(p_data->>'before_id')::uuid))
   order by q.pinned desc,q.created_at desc,q.id desc limit 40) x;return r;
 end if;
 if p_action='report' then
  select * into p from private.bulletin_posts where id=(p_data->>'id')::uuid and team_id=t and audience='all_followers' and status='published';
  if p.id is null or not private.board_post_access(p,u) then raise exception 'Post access required';end if;
  body:=trim(coalesce(p_data->>'reason',''));if length(body) not between 1 and 1000 then raise exception 'Describe the concern';end if;
  insert into private.bulletin_reports(post_id,reporter_id,reason) values(p.id,u,body) on conflict(post_id,reporter_id) do update set reason=excluded.reason,created_at=now();return '{"saved":true}';
 end if;
 raise exception 'Unknown team follow action';
end $$;
revoke all on function private.profile_team_request(text,jsonb) from public,anon;
grant execute on function private.profile_team_request(text,jsonb) to authenticated;
create function public.profile_team_request(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.profile_team_request(p_action,p_data);$$;
revoke all on function public.profile_team_request(text,jsonb) from public,anon;
grant execute on function public.profile_team_request(text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION private.accept_athlete_email_invitation(p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid();v_email text;inv public.athlete_claim_invitations%rowtype;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use a personal account';end if;
 select lower(u.email) into v_email from auth.users u where u.id=uid and u.email_confirmed_at is not null;
 select * into inv from public.athlete_claim_invitations where id=p_id for update;
 if inv.id is null or v_email is null or v_email<>lower(inv.email) then raise exception 'Confirm the email address this invitation was sent to';end if;
 if inv.status='accepted' and exists(select 1 from public.team_memberships where team_id=inv.team_id and athlete_id=inv.athlete_id and user_id=uid and role='athlete' and active) then return inv.athlete_id;end if;
 if inv.status<>'pending' or inv.expires_at<=now() or not public.athlete_on_team(inv.athlete_id,inv.team_id) then raise exception 'Invitation is no longer available';end if;
 -- Lock the athlete too: two different invites cannot claim it concurrently.
 perform 1 from public.athletes where id=inv.athlete_id for update;
 if exists(select 1 from public.team_memberships where team_id=inv.team_id and athlete_id=inv.athlete_id and role='athlete' and user_id<>uid) then raise exception 'This athlete is already connected to another account. Ask your coach for help';end if;
 insert into public.team_memberships(team_id,user_id,role,athlete_id) values(inv.team_id,uid,'athlete',inv.athlete_id) on conflict do nothing;
 update public.athlete_claim_invitations set status='accepted' where id=p_id;
 -- Joining links the saved athlete; sign-in contact never replaces the athlete contact.
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(uid,'claim_athlete_profile','athlete',inv.athlete_id,jsonb_build_object('team_id',inv.team_id));
 return inv.athlete_id;
end $function$;

CREATE OR REPLACE FUNCTION private.wm_profile_approval_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid();pid uuid;rid uuid;n integer;w private.wrestling_profiles%rowtype;
 r private.profile_approval_requests%rowtype;prior private.profile_approval_requests%rowtype;
 result jsonb;prop jsonb;d jsonb;sh jsonb;snapshot jsonb;recipient record;newpath text; c jsonb; policy jsonb;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use your personal account for profile setup';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then raise exception 'Invalid profile request';end if;
 if p_action in ('settings','set_settings') then
  pid:=nullif(p_data->>'profile_id','')::uuid;
  if p_action='set_settings' then
   if pid is null or not private.profile_approval_guardian(pid) then raise exception 'Only a currently linked parent can change approval settings';end if;
   perform 1 from private.wrestling_profiles where id=pid for update;
   if jsonb_typeof(p_data->'auto_approve') is distinct from 'boolean' or jsonb_typeof(p_data->'review_photos') is distinct from 'boolean' then raise exception 'Choose both approval settings';end if;
   insert into private.profile_approval_preferences(profile_id,auto_approve,review_photos,updated_by)
    values(pid,(p_data->>'auto_approve')::boolean,(p_data->>'review_photos')::boolean,uid)
    on conflict(profile_id) do update set auto_approve=excluded.auto_approve,review_photos=excluded.review_photos,updated_by=uid,updated_at=now();
  end if;
  perform private.wrestling_profiles_request('mine','{}');
  select coalesce(jsonb_agg(jsonb_build_object('profile_id',policy_profile.id,'name',policy_profile.name,'can_manage',private.profile_approval_guardian(policy_profile.id),'policy',private.profile_approval_policy(policy_profile.id)) order by policy_profile.name),'[]') into result
  from private.wrestling_profiles policy_profile where (pid is null or policy_profile.id=pid) and policy_profile.athlete_profile_id is not null
   and (private.profile_approval_guardian(policy_profile.id) or private.wrestling_profile_self(policy_profile.id));
  return result;
 end if;
 if p_action in ('context','prepare') then
  perform private.wrestling_profiles_request('mine','{}');
  if p_data->>'kind'='social' then pid:=nullif(p_data->>'id','')::uuid;
  elsif p_data->>'kind'='athlete' then select wp.id into pid from public.athletes a join private.wrestling_profiles wp on wp.athlete_profile_id=a.profile_id where a.id=(p_data->>'id')::uuid;
  elsif p_data->>'kind'='account' then
   select count(distinct a.profile_id) into n from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=uid and m.role='athlete' and m.active;
   if n>1 then raise exception 'Choose your athlete profile from My profiles';end if;
   if n=1 then select wp.id into pid from public.team_memberships m join public.athletes a on a.id=m.athlete_id join private.wrestling_profiles wp on wp.athlete_profile_id=a.profile_id where m.user_id=uid and m.role='athlete' and m.active limit 1;
   else select id into pid from private.wrestling_profiles where user_id=uid;end if;
  else raise exception 'Choose a profile to edit';end if;
  if pid is null then raise exception 'Finish joining your team, then open your athlete profile';end if;
  if private.wrestling_profile_manager(pid) then return jsonb_build_object('approval_required',false,'profile_id',pid);end if;
  if not private.wrestling_profile_self(pid) then raise exception 'Choose your own athlete profile';end if;
  select * into w from private.wrestling_profiles where id=pid for update;
  snapshot:=private.profile_approval_snapshot(pid);
  select * into prior from private.profile_approval_requests where profile_id=pid and submitted_by=uid and status in ('draft','pending','rejected') order by created_at desc limit 1;
  if p_action='context' then
   return jsonb_build_object('approval_required',true,'profile_id',pid,'expected',snapshot,'policy',private.profile_approval_policy(pid),'contact',private.profile_approval_contact(pid),'draft_stale',prior.id is not null and prior.expected is distinct from snapshot,'draft',case when prior.id is null then null else to_jsonb(prior) end);
  end if;
  if p_data ? 'expected' and p_data->'expected' is distinct from snapshot then raise exception 'The profile changed. Reopen it before saving your draft';end if;
  if not (p_data ? 'proposal') and prior.id is not null and prior.expected is distinct from snapshot then raise exception 'Your saved draft needs review. Open Edit profile and send it again';end if;
  prop:=coalesce(p_data->'proposal',prior.proposal,jsonb_build_object('name',w.name,'details',w.details,'sharing',w.sharing,'discoverable',w.discoverable));
  if jsonb_typeof(prop)<>'object' or jsonb_typeof(prop->'name') is distinct from 'string' or length(trim(prop->>'name')) not between 1 and 120 then raise exception 'Enter your name (up to 120 characters)';end if;
  d:=coalesce(prop->'details','{}');sh:=coalesce(prop->'sharing','{}');
  if jsonb_typeof(d)<>'object' or jsonb_typeof(sh)<>'object' then raise exception 'Invalid profile details';end if;
  if exists(select 1 from jsonb_each(d) where key in ('roles','bio','age_division','affiliation','mat_rank','pairing_rank','music_title','music_url') and jsonb_typeof(value)<>'string') then raise exception 'Profile text must be text';end if;
  if length(coalesce(d->>'bio',''))>1200 or exists(select 1 from jsonb_each_text(d) where key in ('roles','age_division','affiliation','mat_rank','pairing_rank','music_title') and length(value)>160) then raise exception 'Please shorten the profile text';end if;
  if length(coalesce(d->>'music_url',''))>1000 or (coalesce(d->>'music_url','')<>'' and d->>'music_url' !~ '^https://(music[.]apple[.]com|open[.]spotify[.]com)/[^[:space:]]+$') then raise exception 'Use an Apple Music or Spotify HTTPS link';end if;
  if d ? 'results' then
   if jsonb_typeof(d->'results')<>'array' then raise exception 'Invalid tournament results';end if;
   if jsonb_array_length(d->'results')>30 or exists(select 1 from jsonb_array_elements(d->'results') x where jsonb_typeof(x)<>'object' or octet_length(x::text)>2500) then raise exception 'Use up to 30 short tournament results';end if;
  end if;
  select coalesce(jsonb_object_agg(key,value),'{}') into d from jsonb_each(d) where key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url']);
  select coalesce(jsonb_object_agg(key,value),'{}') into sh from jsonb_each(sh) where value in ('true'::jsonb,'false'::jsonb) and key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url','photo','corner','follow','outgoing_follow']);
  prop:=jsonb_build_object('name',trim(prop->>'name'),'details',d||'{"roles":"Athlete"}','sharing',sh,'discoverable',coalesce((prop->>'discoverable')::boolean,false));
  if coalesce(p_data->'proposal',prior.proposal) ? 'contact' then
   c:=coalesce(p_data->'proposal',prior.proposal)->'contact';
   if jsonb_typeof(c)<>'object' or jsonb_typeof(c->'email') is distinct from 'string' or jsonb_typeof(c->'phone') is distinct from 'string'
    or jsonb_typeof(c->'share_email_with_coaches') is distinct from 'boolean' or jsonb_typeof(c->'share_phone_with_coaches') is distinct from 'boolean'
    then raise exception 'Check your contact details';end if;
   if length(c->>'email')>254 or (trim(c->>'email')<>'' and c->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then raise exception 'Enter a valid contact email';end if;
   if length(c->>'phone')>32 or c->>'phone' !~ '^[+0-9() .-]*$' then raise exception 'Enter a valid phone number';end if;
   c:=jsonb_build_object('email',lower(trim(c->>'email')),'phone',trim(c->>'phone'),'share_email_with_coaches',(c->>'share_email_with_coaches')::boolean,'share_phone_with_coaches',(c->>'share_phone_with_coaches')::boolean);
   prop:=prop||jsonb_build_object('contact',c);
  end if;
  rid:=gen_random_uuid();newpath:=case when p_data->>'new_photo'='true' then uid::text||'/'||rid::text||'.jpg' when prior.expected=snapshot then prior.path else null end;
  insert into private.profile_approval_requests(id,profile_id,submitted_by,path,proposal,expected) values(rid,pid,uid,newpath,prop,snapshot);
  return jsonb_build_object('approval_required',true,'id',rid,'profile_id',pid,'bucket','profile-photo-requests','path',newpath);
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]') into result from (
   select req.id,req.profile_id,wp.name,req.path,req.proposal,req.status,req.created_at,req.auto_approved,private.profile_approval_guardian(req.profile_id) as can_review
   from private.profile_approval_requests req join private.wrestling_profiles wp on wp.id=req.profile_id
   where req.status not in ('uploading','superseded') and
    ((req.status<>'draft' and private.profile_approval_guardian(req.profile_id)) or (req.submitted_by=uid and private.wrestling_profile_self(req.profile_id)))
   and (nullif(p_data->>'profile_id','') is null or req.profile_id=(p_data->>'profile_id')::uuid)
   and (nullif(p_data->>'id','') is null or req.id=(p_data->>'id')::uuid)
   order by (req.status='pending') desc,req.created_at desc limit 50
  ) q;return result;
 end if;
 rid:=nullif(p_data->>'id','')::uuid;
 select profile_id into pid from private.profile_approval_requests where id=rid;
 if pid is null then raise exception 'Profile request is no longer available';end if;
 perform 1 from private.wrestling_profiles where id=pid for update;
 select * into r from private.profile_approval_requests where id=rid for update;
 if p_action in ('save_draft','submit') then
  if r.submitted_by<>uid or not private.wrestling_profile_self(pid) then raise exception 'Only the athlete can send their own draft';end if;
  if r.status in ('pending','approved') then return jsonb_build_object('id',rid,'pending',r.status='pending','status',r.status);end if;
  if r.status not in ('uploading','draft') then raise exception 'Reopen your profile to start a new draft';end if;
  if r.expected is distinct from private.profile_approval_snapshot(pid) then raise exception 'The profile changed. Reopen it before sending this draft';end if;
  if r.path is not null and not exists(select 1 from storage.objects where bucket_id='profile-photo-requests' and name=r.path and owner_id=uid::text and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 1 and 12000000) then raise exception 'Upload the complete photo before saving';end if;
  update private.profile_approval_requests set status='superseded',reviewed_at=now() where profile_id=pid and status in ('pending','draft') and id<>rid;
  update public.communication_notifications cn set read_at=coalesce(read_at,now()) where profile_request_id in (select id from private.profile_approval_requests where profile_id=pid and status='superseded');
  update private.profile_approval_requests set status=case when p_action='submit' then 'pending' else 'draft' end,submitted_at=case when p_action='submit' then now() else null end where id=rid;
  if p_action='save_draft' then return jsonb_build_object('id',rid,'status','draft');end if;
  if r.path is null and private.profile_request_can_auto_approve(rid,pid) then
   perform private.complete_profile_approval(rid,pid);
   return jsonb_build_object('id',rid,'status','approved','auto_approved',true,'pending',false);
  end if;
  n:=0;
  for recipient in
   select distinct on(g.guardian_user_id) g.guardian_user_id,m.team_id,a.id as athlete_id
   from private.wrestling_profiles wp join public.athletes a on a.profile_id=wp.athlete_profile_id join public.athlete_guardians g on g.athlete_id=a.id
   join public.team_memberships m on m.athlete_id=a.id and m.user_id=g.guardian_user_id and m.role='parent_guardian' and m.active
   where wp.id=pid and not exists(select 1 from private.team_logins where user_id=g.guardian_user_id) order by g.guardian_user_id,m.created_at
  loop
   insert into public.communication_notifications(team_id,user_id,category,title,body,athlete_id,profile_request_id)
   values(recipient.team_id,recipient.guardian_user_id,'system','Review athlete profile','Your athlete sent a profile for approval. Review the name, photo, details and sharing choices before they go live.',recipient.athlete_id,rid);
   n:=n+1;
  end loop;
  if n=0 then raise exception 'Ask your coach to link a parent or guardian, then send your saved draft for approval';end if;
  return jsonb_build_object('id',rid,'pending',true,'status','pending','auto_photo',r.path is not null and private.profile_request_can_auto_approve(rid,pid));
 end if;
 if p_action in ('reject','approve') then
  if not private.profile_approval_guardian(pid) then raise exception 'A linked parent or guardian must review this profile';end if;
  if r.status=p_action||'d' or (p_action='reject' and r.status='rejected') then return jsonb_build_object('id',rid,'status',r.status);end if;
  if r.status<>'pending' then raise exception 'This request was already reviewed or replaced. Refresh the list';end if;
  if p_action='approve' then perform private.complete_profile_approval(rid,pid);return jsonb_build_object('id',rid,'status','approved');end if;
  update private.profile_approval_requests set status='rejected',reviewed_at=now(),reviewed_by=uid where id=rid;
  update public.communication_notifications set read_at=coalesce(read_at,now()) where profile_request_id=rid;
  return jsonb_build_object('id',rid,'status','rejected');
 end if;
 raise exception 'Unknown profile approval action';
end $function$;
