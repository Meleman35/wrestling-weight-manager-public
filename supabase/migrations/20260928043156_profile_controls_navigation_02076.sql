-- Parent choices are private, conservative by default, and valid only while linked.
create table private.profile_approval_preferences (
 profile_id uuid primary key references private.wrestling_profiles(id) on delete cascade,
 auto_approve boolean not null default false,
 review_photos boolean not null default true,
 updated_by uuid not null references auth.users(id) on delete cascade,
 updated_at timestamptz not null default now()
);
alter table private.profile_approval_preferences enable row level security;
revoke all on private.profile_approval_preferences from public,anon,authenticated;
create index profile_approval_preferences_parent on private.profile_approval_preferences(updated_by);
alter table private.profile_approval_requests add column auto_approved boolean not null default false,
 add column published_photo jsonb;

create function private.profile_approval_policy(p_profile uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('auto_approve',x.auto_approve,'review_photos',x.review_photos)
 from private.profile_approval_preferences x where x.profile_id=p_profile and exists(
  select 1 from private.wrestling_profiles w join public.athletes a on a.profile_id=w.athlete_profile_id
  join public.athlete_guardians g on g.athlete_id=a.id and g.guardian_user_id=x.updated_by
  join public.team_memberships m on m.athlete_id=a.id and m.user_id=g.guardian_user_id and m.role='parent_guardian' and m.active
  where w.id=p_profile and not exists(select 1 from private.team_logins tl where tl.user_id=x.updated_by)
 )), '{"auto_approve":false,"review_photos":true}'::jsonb)
$$;
revoke all on function private.profile_approval_policy(uuid) from public,anon,authenticated;

create function private.profile_approval_contact(p_profile uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('email',coalesce(c.email,''),'phone',coalesce(c.phone,''),
  'share_email_with_coaches',coalesce(c.share_email_with_coaches,false),
  'share_phone_with_coaches',coalesce(c.share_phone_with_coaches,false))
 from private.wrestling_profiles w join public.athletes a on a.profile_id=w.athlete_profile_id
 left join public.athlete_private_contact c on c.athlete_id=a.id
 where w.id=p_profile order by a.created_at,a.id limit 1
$$;
revoke all on function private.profile_approval_contact(uuid) from public,anon,authenticated;

create or replace function private.profile_approval_snapshot(p_profile uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',w.name,'details',w.details,'sharing',w.sharing,'discoverable',w.discoverable,'photo',w.photo_path,
 'contacts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'email',c.email,'phone',c.phone,
 'share_email_with_coaches',c.share_email_with_coaches,'share_phone_with_coaches',c.share_phone_with_coaches) order by a.id)
 from public.athletes a left join public.athlete_private_contact c on c.athlete_id=a.id where a.profile_id=w.athlete_profile_id),'[]'::jsonb))
 from private.wrestling_profiles w where w.id=p_profile and auth.uid() is not null
 and (private.wrestling_profile_self(w.id) or private.profile_approval_guardian(w.id))
$$;

create function private.profile_request_can_auto_approve(p_request uuid,p_profile uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.wrestling_profile_self(p_profile)
 and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and exists(select 1 from private.profile_approval_requests r join private.wrestling_profiles w on w.id=r.profile_id
 where r.id=p_request and r.profile_id=p_profile and r.submitted_by=auth.uid() and r.status='pending'
 and private.profile_approval_policy(p_profile)->>'auto_approve'='true'
 and r.expected=private.profile_approval_snapshot(p_profile)
 and r.proposal->>'name'=w.name
 and (not (r.proposal ? 'contact') or r.proposal->'contact'=private.profile_approval_contact(p_profile))
 and (r.path is null or private.profile_approval_policy(p_profile)->>'review_photos'='false'))
$$;
revoke all on function private.profile_request_can_auto_approve(uuid,uuid) from public,anon,authenticated;

create or replace function private.complete_profile_approval(p_request uuid,p_profile uuid,p_photo_state jsonb default null)
returns void language plpgsql security definer set search_path='' as $$
declare r private.profile_approval_requests%rowtype; is_parent boolean; is_auto boolean; contact jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in to review this profile';end if;
 perform 1 from private.wrestling_profiles where id=p_profile for update;
 select * into r from private.profile_approval_requests where id=p_request for update;
 if not found or r.profile_id<>p_profile or r.status<>'pending' then raise exception 'This request was already reviewed or replaced. Refresh the list';end if;
 is_parent:=private.profile_approval_guardian(p_profile);
 is_auto:=not is_parent and private.profile_request_can_auto_approve(p_request,p_profile);
 if not is_parent and not is_auto then raise exception 'A linked parent or guardian must approve this profile';end if;
 if r.expected is distinct from private.profile_approval_snapshot(p_profile) then raise exception 'The live profile changed. Reopen the draft and send it again';end if;
 if r.path is not null and p_photo_state is null then raise exception 'Review and upload the requested photo before approving';end if;
 if is_auto then
  -- Only a previously validated request can enter this narrow publishing path.
  update private.wrestling_profiles set details=r.proposal->'details',sharing=r.proposal->'sharing',
    discoverable=(r.proposal->>'discoverable')::boolean,updated_at=now() where id=p_profile;
 else
  perform private.wrestling_profiles_request('save',r.proposal||jsonb_build_object('id',p_profile,'music_approved',true));
  if r.proposal ? 'contact' then
   contact:=r.proposal->'contact';
   insert into public.athlete_private_contact(athlete_id,email,phone,share_email_with_coaches,share_phone_with_coaches)
   select a.id,nullif(contact->>'email',''),nullif(contact->>'phone',''),(contact->>'share_email_with_coaches')::boolean,(contact->>'share_phone_with_coaches')::boolean
   from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where w.id=p_profile
   on conflict(athlete_id) do update set email=excluded.email,phone=excluded.phone,
    share_email_with_coaches=excluded.share_email_with_coaches,share_phone_with_coaches=excluded.share_phone_with_coaches,updated_at=now();
   update public.profiles pr set phone=nullif(contact->>'phone','') where exists(
    select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
    join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where w.id=p_profile and m.user_id=pr.id and m.role='athlete' and m.active)
    and (select count(distinct a.profile_id) from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=pr.id and m.role='athlete' and m.active)=1;
  end if;
 end if;
 update private.profile_approval_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid(),auto_approved=is_auto,published_photo=p_photo_state where id=p_request;
 update public.communication_notifications set read_at=coalesce(read_at,now()) where profile_request_id=p_request;
end $$;

-- A photo may be inserted for the current automatic request; publishing still
-- rechecks the parent policy, protected fields and optimistic snapshot atomically.
create function private.profile_auto_photo_upload(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.profile_approval_requests r where split_part(p_path,'/',1)=r.profile_id::text
 and r.path is not null and private.profile_request_can_auto_approve(r.id,r.profile_id))
$$;
revoke all on function private.profile_auto_photo_upload(text) from public,anon;
grant execute on function private.profile_auto_photo_upload(text) to authenticated;
create policy profile_auto_photo_insert on storage.objects for insert to authenticated
 with check(bucket_id='wrestling-profile-photos' and private.profile_auto_photo_upload(name));

-- Existing paths cannot be overwritten to evade approval, even by an older client.
create policy profile_photos_immutable_update on storage.objects as restrictive for update to authenticated
 using(bucket_id not in ('profile-photos','athlete-photos','wrestling-profile-photos'))
 with check(bucket_id not in ('profile-photos','athlete-photos','wrestling-profile-photos'));
create policy profile_photos_immutable_delete on storage.objects as restrictive for delete to authenticated
 using(bucket_id not in ('profile-photos','athlete-photos','wrestling-profile-photos'));

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
  select coalesce(jsonb_agg(jsonb_build_object('profile_id',w.id,'name',w.name,'can_manage',private.profile_approval_guardian(w.id),'policy',private.profile_approval_policy(w.id)) order by w.name),'[]') into result
  from private.wrestling_profiles w where (pid is null or w.id=pid) and w.athlete_profile_id is not null
   and (private.profile_approval_guardian(w.id) or private.wrestling_profile_self(w.id));
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
   return jsonb_build_object('approval_required',true,'profile_id',pid,'expected',snapshot,'policy',private.profile_approval_policy(pid),'contact',private.profile_approval_contact(pid),'draft',case when prior.id is null then null else to_jsonb(prior) end);
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
  rid:=gen_random_uuid();newpath:=case when p_data->>'new_photo'='true' then uid::text||'/'||rid::text||'.jpg' else prior.path end;
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
end $function$
;
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
 if pid is null or not (coalesce(private.wrestling_profile_manager(pid),false) or private.profile_request_can_auto_approve(nullif(p_data->>'approval_id','')::uuid,pid)) then raise exception 'The profile owner or linked parent/guardian must update this picture';end if;
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
  perform private.complete_profile_approval((p_data->>'approval_id')::uuid,pid,jsonb_build_object('legacy',new_legacy,'social',new_social));
 end if;
 update private.wrestling_profiles set photo_path=new_social,updated_at=now() where id=pid;
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
end $function$

;
create function private.profile_auto_photo_committed(p_athlete_profile uuid,p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.profile_approval_requests r join private.wrestling_profiles w on w.id=r.profile_id
 where w.athlete_profile_id=p_athlete_profile and r.submitted_by=auth.uid() and r.status='approved' and r.auto_approved
 and r.published_photo->>'legacy'=p_path and r.published_photo->>'social'=w.photo_path)
$$;
revoke all on function private.profile_auto_photo_committed(uuid,text) from public,anon,authenticated;

create or replace function private.guard_athlete_account_name()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and exists(
  select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id
  join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id
  where m.user_id=new.id and m.role='athlete' and m.active
  and not private.wrestling_profile_manager(w.id)
  and ((new.display_name is distinct from old.display_name and w.name is distinct from new.display_name)
   or new.phone is distinct from old.phone
   or (new.photo_path is distinct from old.photo_path and not private.profile_auto_photo_committed(a.profile_id,new.photo_path)))
 ) then raise exception 'Open My Profile to send name and contact changes for parent approval';end if;
 return new;
end $$;
drop trigger guard_athlete_account_name on public.profiles;
create trigger guard_athlete_account_name before update of display_name,phone,photo_path on public.profiles for each row execute function private.guard_athlete_account_name();

create function private.guard_athlete_protected_edits()
returns trigger language plpgsql security definer set search_path='' as $$
declare a public.athletes%rowtype; contact public.athlete_private_contact%rowtype; birth date; changed boolean=false;
begin
 if auth.uid() is null then return new;end if;
 if tg_table_name='athletes' then a:=old;
 else select * into a from public.athletes where id=new.athlete_id;end if;
 if not public.is_self_athlete(a.id) or public.is_guardian_for_athlete(a.id) then return new;end if;
 select coalesce(i.birth_date,a.birth_date) into birth from public.athlete_private_identity i where i.athlete_id=a.id;
 birth:=coalesce(birth,a.birth_date);
 if birth is not null and birth<=current_date-interval '18 years' then return new;end if;
 if tg_table_name='athletes' then
  changed:=new.first_name is distinct from old.first_name or new.last_name is distinct from old.last_name
   or new.email is distinct from old.email or new.phone is distinct from old.phone or new.birth_date is distinct from old.birth_date
   or (new.photo_path is distinct from old.photo_path and not private.profile_auto_photo_committed(a.profile_id,new.photo_path));
 elsif tg_table_name='athlete_private_contact' then
  select * into contact from public.athlete_private_contact where athlete_id=a.id;
  changed:=coalesce(new.email,'')<>coalesce(contact.email,'') or coalesce(new.phone,'')<>coalesce(contact.phone,'')
   or coalesce(new.share_email_with_coaches,false)<>coalesce(contact.share_email_with_coaches,false)
   or coalesce(new.share_phone_with_coaches,false)<>coalesce(contact.share_phone_with_coaches,false)
   or coalesce(new.sms_opt_in,false)<>coalesce(contact.sms_opt_in,false);
 elsif tg_table_name='athlete_private_identity' then
  changed:=new.birth_date is distinct from birth;
 end if;
 if changed then raise exception 'A linked parent must approve name, contact, birthday or photo changes. Open My Profile';end if;
 return new;
end $$;
revoke all on function private.guard_athlete_protected_edits() from public,anon,authenticated;
create trigger guard_athlete_protected_edits before update of first_name,last_name,email,phone,birth_date,photo_path on public.athletes for each row execute function private.guard_athlete_protected_edits();
create trigger guard_athlete_contact_edits before insert or update on public.athlete_private_contact for each row execute function private.guard_athlete_protected_edits();
create trigger guard_athlete_birth_edits before insert or update on public.athlete_private_identity for each row execute function private.guard_athlete_protected_edits();
