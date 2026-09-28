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
