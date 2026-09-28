-- Athlete profile revisions remain private until a currently linked guardian approves.
create table private.profile_approval_requests(
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references private.wrestling_profiles(id) on delete cascade,
 submitted_by uuid not null references auth.users(id) on delete cascade,
 path text, proposal jsonb not null check(jsonb_typeof(proposal)='object'),
 expected jsonb not null check(jsonb_typeof(expected)='object'),
 status text not null default 'uploading' check(status in ('uploading','draft','pending','approved','rejected','superseded')),
 created_at timestamptz not null default clock_timestamp(), submitted_at timestamptz,
 reviewed_at timestamptz, reviewed_by uuid references auth.users(id) on delete set null
);
alter table private.profile_approval_requests enable row level security;
revoke all on private.profile_approval_requests from public,anon,authenticated;
create unique index profile_approval_one_pending on private.profile_approval_requests(profile_id) where status='pending';
create index profile_approval_owner on private.profile_approval_requests(submitted_by,created_at desc);
create index profile_approval_profile on private.profile_approval_requests(profile_id,created_at desc);
create index profile_approval_path on private.profile_approval_requests(path) where path is not null;
alter table public.communication_notifications add column profile_request_id uuid references private.profile_approval_requests(id) on delete cascade;
create unique index profile_approval_notification_recipient on public.communication_notifications(profile_request_id,user_id) where profile_request_id is not null;

create function private.profile_approval_guardian(p_profile uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.wrestling_profile_manager(p_profile) and exists(
  select 1 from private.wrestling_profiles w join public.athletes a on a.profile_id=w.athlete_profile_id
  where w.id=p_profile and public.is_guardian_for_athlete(a.id)
 )
$$;
revoke all on function private.profile_approval_guardian(uuid) from public,anon,authenticated;

-- Only these published fields participate in optimistic concurrency checks.
create function private.profile_approval_snapshot(p_profile uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',w.name,'details',w.details,'sharing',w.sharing,'discoverable',w.discoverable,'photo',w.photo_path)
 from private.wrestling_profiles w where w.id=p_profile and auth.uid() is not null
 and (private.wrestling_profile_self(w.id) or private.profile_approval_guardian(w.id))
$$;
revoke all on function private.profile_approval_snapshot(uuid) from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photo-requests','profile-photo-requests',false,12000000,array['image/jpeg']);
create function private.profile_approval_storage(p_path text,p_write boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from private.team_logins where user_id=auth.uid()) and exists(
  select 1 from private.profile_approval_requests r where r.path=p_path and
  case when p_write then r.submitted_by=auth.uid() and r.status='uploading' and r.created_at>now()-interval '1 day'
    and r.path=auth.uid()::text||'/'||r.id::text||'.jpg' and private.wrestling_profile_self(r.profile_id)
  else (r.submitted_by=auth.uid() and private.wrestling_profile_self(r.profile_id))
    or (r.status in ('pending','approved','rejected') and private.profile_approval_guardian(r.profile_id)) end
 )
$$;
revoke all on function private.profile_approval_storage(text,boolean) from public,anon;
grant execute on function private.profile_approval_storage(text,boolean) to authenticated;
create policy profile_approval_upload on storage.objects for insert to authenticated
 with check(bucket_id='profile-photo-requests' and private.profile_approval_storage(name,true));
create policy profile_approval_read on storage.objects for select to authenticated
 using(bucket_id='profile-photo-requests' and private.profile_approval_storage(name,false));
-- Uploaded candidates are immutable. No UPDATE or DELETE grant can replace an item under review.

create function private.complete_profile_approval(p_request uuid,p_profile uuid,p_photo_state jsonb default null)
returns void language plpgsql security definer set search_path='' as $$
declare r private.profile_approval_requests%rowtype;
begin
 if auth.uid() is null or not private.profile_approval_guardian(p_profile) then raise exception 'A linked parent or guardian must approve this profile';end if;
 perform 1 from private.wrestling_profiles where id=p_profile for update;
 select * into r from private.profile_approval_requests where id=p_request for update;
 if not found or r.profile_id<>p_profile or r.status<>'pending' then raise exception 'This request was already reviewed or replaced. Refresh the list';end if;
 if r.expected is distinct from private.profile_approval_snapshot(p_profile) then raise exception 'The live profile changed. Ask the athlete to reopen their profile and send an updated request';end if;
 if r.path is not null and p_photo_state is null then raise exception 'Review and upload the requested photo before approving';end if;
 perform private.wrestling_profiles_request('save',r.proposal||jsonb_build_object('id',p_profile,'music_approved',true));
 update private.profile_approval_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request;
 update public.communication_notifications set read_at=coalesce(read_at,now()) where profile_request_id=p_request;
end $$;
revoke all on function private.complete_profile_approval(uuid,uuid,jsonb) from public,anon,authenticated;

create function private.wm_profile_approval_request(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();pid uuid;rid uuid;n integer;w private.wrestling_profiles%rowtype;
 r private.profile_approval_requests%rowtype;prior private.profile_approval_requests%rowtype;
 result jsonb;prop jsonb;d jsonb;sh jsonb;snapshot jsonb;recipient record;newpath text;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use your personal account for profile setup';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then raise exception 'Invalid profile request';end if;
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
   return jsonb_build_object('approval_required',true,'profile_id',pid,'expected',snapshot,'draft',case when prior.id is null then null else to_jsonb(prior) end);
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
  rid:=gen_random_uuid();newpath:=case when p_data->>'new_photo'='true' then uid::text||'/'||rid::text||'.jpg' else prior.path end;
  insert into private.profile_approval_requests(id,profile_id,submitted_by,path,proposal,expected) values(rid,pid,uid,newpath,prop,snapshot);
  return jsonb_build_object('approval_required',true,'id',rid,'profile_id',pid,'bucket','profile-photo-requests','path',newpath);
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]') into result from (
   select req.id,req.profile_id,wp.name,req.path,req.proposal,req.status,req.created_at,private.profile_approval_guardian(req.profile_id) as can_review
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
  return jsonb_build_object('id',rid,'pending',true,'status','pending');
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
end $$;
revoke all on function private.wm_profile_approval_request(text,jsonb) from public,anon;
grant execute on function private.wm_profile_approval_request(text,jsonb) to authenticated;
create function public.wm_profile_approval_request(p_action text,p_data jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$select private.wm_profile_approval_request(p_action,p_data)$$;
revoke all on function public.wm_profile_approval_request(text,jsonb) from public,anon;
grant execute on function public.wm_profile_approval_request(text,jsonb) to authenticated;

-- Older clients cannot bypass guardian review through the name-only endpoint.
create or replace function private.update_profile_name(p_profile_id uuid,p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();clean_name text=trim(p_name);
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use your personal account to edit your name';end if;
 if clean_name is null or length(clean_name) not between 1 and 120 then raise exception 'Enter a name between 1 and 120 characters';end if;
 if not private.wrestling_profile_manager(p_profile_id) then raise exception 'Open Edit profile to send your name and profile for parent approval';end if;
 update private.wrestling_profiles set name=clean_name,updated_at=now() where id=p_profile_id;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id) values(uid,'update_profile_name','wrestling_profile',p_profile_id);
 return jsonb_build_object('id',p_profile_id,'name',clean_name);
end $$;

-- The approved shared-name trigger may sync the athlete account, but a direct
-- account update cannot publish a different name around the approval process.
create function private.guard_athlete_account_name()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and (new.display_name is distinct from old.display_name or new.photo_path is distinct from old.photo_path) and exists(
  select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
  join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id
  where m.user_id=new.id and m.role='athlete' and m.active and (a.birth_date is null or a.birth_date>current_date-interval '18 years')
  and (w.name is distinct from new.display_name or new.photo_path is distinct from old.photo_path) and not private.wrestling_profile_manager(w.id)
 ) then raise exception 'Open Edit profile to send your name for parent approval';end if;
 return new;
end $$;
revoke all on function private.guard_athlete_account_name() from public,anon,authenticated;
create trigger guard_athlete_account_name before update of display_name,photo_path on public.profiles for each row execute function private.guard_athlete_account_name();

CREATE OR REPLACE FUNCTION private.wm_profile_photo_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); pid uuid; ap uuid; aid uuid; requested_aid uuid;
 p private.wrestling_profiles%rowtype; legacy_path text; legacy_bucket text;
 current_state jsonb; new_legacy text=p_data->>'legacy_path'; new_social text=p_data->>'social_path';
 count_ap integer;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Use your personal account to change a profile picture';end if;
 if p_action not in ('prepare','commit') or p_action is null then raise exception 'Unknown photo action';end if;
 if octet_length(p_data::text)>5000 then raise exception 'Invalid photo request';end if;
 if p_action='prepare' then
  perform private.wrestling_profiles_request('mine','{}');
  if p_data->>'kind'='social' then pid:=nullif(p_data->>'id','')::uuid;
  elsif p_data->>'kind'='athlete' then
   requested_aid:=nullif(p_data->>'id','')::uuid;
   select w.id into pid from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where a.id=requested_aid;
  elsif p_data->>'kind'='account' then select id into pid from private.wrestling_profiles where user_id=uid;
  else raise exception 'Choose the person whose photo you want to change';end if;
 else pid:=nullif(p_data->>'id','')::uuid;requested_aid:=nullif(p_data->>'athlete_id','')::uuid;
 end if;
 -- An adult athlete's account and athlete profile describe the same person.
 -- Parent/guardian memberships must never be used for this mapping.
 select * into p from private.wrestling_profiles where id=pid;
 if p.user_id=uid or (p_action='prepare' and p_data->>'kind'='account') then
  select count(distinct a.profile_id) into count_ap from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=uid and m.role='athlete' and m.active;
  if count_ap=1 then
   select a.profile_id into ap from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=uid and m.role='athlete' and m.active limit 1;
   select id into pid from private.wrestling_profiles where athlete_profile_id=ap;
  elsif count_ap>1 then raise exception 'Choose your athlete profile to change its photo';end if;
 end if;
 if pid is null or not coalesce(private.wrestling_profile_manager(pid),false) then raise exception 'The profile owner or linked parent/guardian must update this picture';end if;
 select * into p from private.wrestling_profiles where id=pid for update;
 if p.user_id is not null then
  select photo_path into legacy_path from public.profiles where id=p.user_id for update;
  legacy_bucket:='profile-photos';
 else
  perform 1 from public.athlete_profiles where id=p.athlete_profile_id for update;
  select a.id,a.photo_path into aid,legacy_path from public.athletes a
  where a.profile_id=p.athlete_profile_id and (requested_aid is null or a.id=requested_aid)
   and (public.is_guardian_for_athlete(a.id) or exists(select 1 from public.team_memberships m where m.user_id=uid and m.athlete_id=a.id and m.role='athlete' and m.active))
  order by a.created_at,a.id limit 1 for update;
  if aid is null then raise exception 'Reopen this athlete from your linked profiles';end if;
  legacy_bucket:='athlete-photos';
 end if;
 current_state:=jsonb_build_object('legacy',legacy_path,'social',p.photo_path);
 if p_action='prepare' then return jsonb_build_object('id',pid,'athlete_id',aid,'bucket',legacy_bucket,'prefix',coalesce(p.user_id,aid)::text,'expected',current_state);end if;
 if p_data->'expected' is distinct from current_state then raise exception 'This picture changed on another device. Reopen the profile before replacing it';end if;
 if new_legacy is null or new_social is null
  or new_legacy !~ ('^'||coalesce(p.user_id,aid)::text||'/[0-9a-f-]{36}[.]jpg$')
  or new_social !~ ('^'||pid::text||'/[0-9a-f-]{36}[.]jpg$')
  or not exists(select 1 from storage.objects where bucket_id=legacy_bucket and name=new_legacy and owner_id=uid::text and metadata->>'mimetype'='image/jpeg')
  or not exists(select 1 from storage.objects where bucket_id='wrestling-profile-photos' and name=new_social and owner_id=uid::text and metadata->>'mimetype'='image/jpeg')
 then raise exception 'Upload the complete profile picture before saving';end if;
 if nullif(p_data->>'approval_id','') is not null then
  perform private.complete_profile_approval((p_data->>'approval_id')::uuid,pid,current_state);
 end if;
 if p.user_id is not null then
  update public.profiles set photo_path=new_legacy,updated_at=now() where id=p.user_id;
 else
  update public.athletes set photo_path=new_legacy,updated_at=now() where profile_id=p.athlete_profile_id;
  -- Only the athlete's own personal login follows this picture; never their guardian's.
  update public.profiles pr set photo_path=new_legacy,updated_at=now()
  where exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=pr.id and m.role='athlete' and m.active and a.profile_id=p.athlete_profile_id)
   and not exists(select 1 from private.team_logins where user_id=pr.id)
   and (select count(distinct a.profile_id) from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=pr.id and m.role='athlete' and m.active)=1;
 end if;
 update private.wrestling_profiles set photo_path=new_social,updated_at=now() where id=pid;
 return jsonb_build_object('saved',true,'id',pid);
end $function$;
