-- Ordinary team-profile edits use the same parent policy and approval inbox.
create table private.profile_publish_context(transaction_id bigint not null,profile_id uuid not null,actor_id uuid not null,primary key(transaction_id,profile_id));
alter table private.profile_publish_context enable row level security;
revoke all on private.profile_publish_context from public,anon,authenticated;
create function private.profile_team_values(aid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('graduation_year',a.graduation_year,'school_level',d.school_level,'grade_level',d.grade_level,'shirt_size',d.shirt_size,'shorts_size',d.shorts_size,'shoe_size',d.shoe_size,'singlet_size',d.singlet_size,'warmup_top_size',d.warmup_top_size,'warmup_bottom_size',d.warmup_bottom_size,'medical_conditions',to_jsonb(coalesce(m.conditions,'{}'::text[])),'medical_notes',m.notes,'rescue_item_location',m.rescue_item_location)
 from public.athletes a left join public.athlete_profile_details d on d.athlete_id=a.id left join public.athlete_medical_private m on m.athlete_id=a.id where a.id=aid
$$;
create function private.normalize_profile_team_edit(pid uuid,edit jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare aid uuid=(edit->>'athlete_id')::uuid;v jsonb=edit->'values';normalized jsonb;
begin
 if not exists(select 1 from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where w.id=pid and a.id=aid) or not public.is_self_athlete(aid) then raise exception 'Choose your own team profile';end if;
 if jsonb_typeof(v) is distinct from 'object' or octet_length(v::text)>12000 then raise exception 'Invalid team profile details';end if;
 select coalesce(jsonb_object_agg(key,value),'{}') into normalized from jsonb_each(v) where key=any(array['graduation_year','school_level','grade_level','shirt_size','shorts_size','shoe_size','singlet_size','warmup_top_size','warmup_bottom_size','medical_conditions','medical_notes','rescue_item_location']);
 normalized:=private.profile_team_values(aid)||normalized;
 if exists(select 1 from jsonb_each(normalized) where key not in ('graduation_year','medical_conditions') and (jsonb_typeof(value) not in ('string','null') or length(value#>>'{}')>2000)) then raise exception 'Please shorten the team profile details';end if;
 if normalized->>'graduation_year' is not null and ((normalized->>'graduation_year')::int not between 1900 and 2200) then raise exception 'Choose a valid graduation year';end if;
 if jsonb_typeof(normalized->'medical_conditions') is distinct from 'array' or jsonb_array_length(normalized->'medical_conditions')>30 or exists(select 1 from jsonb_array_elements(normalized->'medical_conditions') x where jsonb_typeof(x)<>'string' or length(x#>>'{}')>160) then raise exception 'Check the medical selections';end if;
 return jsonb_build_object('athlete_id',aid,'values',normalized);
end $$;
create function private.guard_team_profile_edit() returns trigger language plpgsql security definer set search_path='' as $$
declare aid uuid;pid uuid;v jsonb;prior jsonb;current_row jsonb;col text;changed boolean=false;
begin
 if auth.uid() is null then return new;end if;
 aid:=case when tg_table_name='athletes' then new.id else new.athlete_id end;
 if not public.is_self_athlete(aid) or public.is_guardian_for_athlete(aid) then return new;end if;
 if exists(select 1 from public.athletes a left join public.athlete_private_identity i on i.athlete_id=a.id where a.id=aid and coalesce(i.birth_date,a.birth_date)<=current_date-interval '18 years') then return new;end if;
 select w.id into pid from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where a.id=aid;
 if exists(select 1 from private.profile_publish_context where transaction_id=txid_current() and profile_id=pid and actor_id=auth.uid()) then return new;end if;
 if tg_table_name='athletes' then changed:=new.graduation_year is distinct from old.graduation_year;
 else
  v:=to_jsonb(new)-array['athlete_id','updated_at','updated_by','id','created_at'];
  if tg_op='UPDATE' then prior:=to_jsonb(old)-array['athlete_id','updated_at','updated_by','id','created_at'];
  else
   if tg_table_name='athlete_profile_details' then select to_jsonb(d) into current_row from public.athlete_profile_details d where athlete_id=aid;
   else select to_jsonb(d) into current_row from public.athlete_medical_private d where athlete_id=aid;end if;
   prior:=coalesce(current_row,'{}')-array['athlete_id','updated_at','updated_by','id','created_at'];
  end if;
  -- An unchanged upsert or empty insert is safe; changed values must use the approval path.
  for col in select key from jsonb_each(v) loop
   if coalesce(v->col,'null') is distinct from coalesce(prior->col,'null') and not (prior->col is null and v->col in ('null','false','[]')) then changed:=true;end if;
  end loop;
 end if;
 if changed then raise exception 'Save team-profile edits through the parent approval form';end if;
 return new;
end $$;
create trigger team_profile_parent_guard before update of graduation_year on public.athletes for each row execute function private.guard_team_profile_edit();
create trigger team_details_parent_guard before insert or update on public.athlete_profile_details for each row execute function private.guard_team_profile_edit();
create trigger team_medical_parent_guard before insert or update on public.athlete_medical_private for each row execute function private.guard_team_profile_edit();
create function private.publish_team_profile(edit jsonb) returns void language plpgsql security definer set search_path='' as $$
declare aid uuid=(edit->>'athlete_id')::uuid;v jsonb=edit->'values';
begin
 update public.athletes set graduation_year=(v->>'graduation_year')::int,updated_at=now() where id=aid;
 insert into public.athlete_profile_details(athlete_id,school_level,grade_level,shirt_size,shorts_size,shoe_size,singlet_size,warmup_top_size,warmup_bottom_size,updated_by)
 values(aid,v->>'school_level',v->>'grade_level',v->>'shirt_size',v->>'shorts_size',v->>'shoe_size',v->>'singlet_size',v->>'warmup_top_size',v->>'warmup_bottom_size',auth.uid())
 on conflict(athlete_id) do update set school_level=excluded.school_level,grade_level=excluded.grade_level,shirt_size=excluded.shirt_size,shorts_size=excluded.shorts_size,shoe_size=excluded.shoe_size,singlet_size=excluded.singlet_size,warmup_top_size=excluded.warmup_top_size,warmup_bottom_size=excluded.warmup_bottom_size,updated_by=auth.uid(),updated_at=now();
 insert into public.athlete_medical_private(athlete_id,conditions,notes,rescue_item_location)
 values(aid,array(select jsonb_array_elements_text(v->'medical_conditions')),v->>'medical_notes',v->>'rescue_item_location')
 on conflict(athlete_id) do update set conditions=excluded.conditions,notes=excluded.notes,rescue_item_location=excluded.rescue_item_location,updated_at=now();
end $$;
revoke all on function private.profile_team_values(uuid),private.normalize_profile_team_edit(uuid,jsonb),private.guard_team_profile_edit(),private.publish_team_profile(jsonb) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.profile_approval_snapshot(p_profile uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('name',w.name,'details',w.details,'sharing',w.sharing,'discoverable',w.discoverable,'photo',w.photo_path,
 'team_profiles',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'values',private.profile_team_values(a.id)) order by a.id) from public.athletes a where a.profile_id=w.athlete_profile_id),'[]'::jsonb),'contacts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'email',c.email,'phone',c.phone,
 'share_email_with_coaches',c.share_email_with_coaches,'share_phone_with_coaches',c.share_phone_with_coaches) order by a.id)
 from public.athletes a left join public.athlete_private_contact c on c.athlete_id=a.id where a.profile_id=w.athlete_profile_id),'[]'::jsonb))
 from private.wrestling_profiles w where w.id=p_profile and auth.uid() is not null
 and (private.wrestling_profile_self(w.id) or private.profile_approval_guardian(w.id))
$function$;
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
  if p_data->'proposal' ? 'team_profile' then prop:=prop||jsonb_build_object('team_profile',private.normalize_profile_team_edit(pid,p_data->'proposal'->'team_profile'));end if;
  rid:=gen_random_uuid();newpath:=case when p_data->>'new_photo'='true' then uid::text||'/'||rid::text||'.jpg' when p_data->'proposal' ? 'team_profile' then null when prior.expected=snapshot then prior.path else null end;
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

CREATE OR REPLACE FUNCTION private.complete_profile_approval(p_request uuid, p_profile uuid, p_photo_state jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if r.proposal ? 'team_profile' then
  insert into private.profile_publish_context values(txid_current(),p_profile,auth.uid());
  perform private.publish_team_profile(r.proposal->'team_profile');
  delete from private.profile_publish_context where transaction_id=txid_current() and profile_id=p_profile;
 end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.update_athlete_profile_v2(p_athlete_id uuid, p_team_id uuid, p_profile jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_self boolean;
  v_is_guardian boolean;
  v_is_staff boolean;
  v_is_admin boolean;
  v_can_edit_private boolean;
  v_existing_birth date;
  v_birth date;
  v_is_adult boolean := false;
  v_can_control_sensitive boolean := false;
  v_conditions text[];
  pid uuid;ctx jsonb;req jsonb;outcome jsonb;cur jsonb;k text;prop jsonb;vals jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.athlete_on_team(p_athlete_id,p_team_id) then raise exception 'athlete is not on this team'; end if;

  v_is_self := public.is_self_athlete(p_athlete_id);
  v_is_guardian := public.is_guardian_for_athlete(p_athlete_id);
  v_is_staff := public.is_team_staff(p_team_id);
  v_is_admin := public.is_team_admin(p_team_id);
  v_can_edit_private := v_is_self or v_is_guardian or v_is_admin;

  if not (v_is_self or v_is_guardian or v_is_staff) then raise exception 'not authorized'; end if;
  if v_is_self and not v_is_guardian and exists(select 1 from public.athletes a left join public.athlete_private_identity i on i.athlete_id=a.id where a.id=p_athlete_id and (coalesce(i.birth_date,a.birth_date) is null or coalesce(i.birth_date,a.birth_date)>current_date-interval '18 years')) then
   perform private.wrestling_profiles_request('mine','{}');
   select w.id into pid from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where a.id=p_athlete_id;
   cur:=public.get_athlete_profile_for_team(p_athlete_id,p_team_id);
   foreach k in array array['first_name','last_name','birth_date','email','phone','share_email_with_coaches','share_phone_with_coaches','share_birth_date_with_coaches','sms_opt_in','disclose_medical_to_coaches','photo_path'] loop
    if p_profile ? k and coalesce(nullif(p_profile->>k,''),'') is distinct from coalesce(nullif(cur->>k,''),'') then raise exception 'Use My Profile for name and contact requests. A parent manages birthday, SMS and sensitive sharing';end if;
   end loop;
   ctx:=private.wm_profile_approval_request('context',jsonb_build_object('kind','athlete','id',p_athlete_id));
   prop:=jsonb_build_object('name',ctx->'expected'->'name','details',ctx->'expected'->'details','sharing',ctx->'expected'->'sharing','discoverable',ctx->'expected'->'discoverable','contact',ctx->'contact','team_profile',jsonb_build_object('athlete_id',p_athlete_id,'values',p_profile));
   req:=private.wm_profile_approval_request('prepare',jsonb_build_object('kind','athlete','id',p_athlete_id,'proposal',prop,'expected',ctx->'expected'));
   outcome:=private.wm_profile_approval_request('submit',jsonb_build_object('id',req->'id'));
   return public.get_athlete_profile_for_team(p_athlete_id,p_team_id)||jsonb_build_object('profile_approval',outcome);
  end if;


  select birth_date into v_existing_birth
  from public.athlete_private_identity
  where athlete_id=p_athlete_id;

  if v_can_edit_private and p_profile ? 'birth_date' and nullif(p_profile->>'birth_date','') is not null then
    v_birth := (p_profile->>'birth_date')::date;
  else
    v_birth := v_existing_birth;
  end if;

  v_is_adult := v_birth is not null and v_birth <= (current_date - interval '18 years')::date;
  v_can_control_sensitive := v_is_guardian or v_is_admin or (v_is_self and v_is_adult);

  update public.athletes a
  set first_name=coalesce(nullif(trim(p_profile->>'first_name'),''),a.first_name),
      last_name=coalesce(nullif(trim(p_profile->>'last_name'),''),a.last_name),
      graduation_year=case
        when p_profile ? 'graduation_year' and nullif(p_profile->>'graduation_year','') is not null then (p_profile->>'graduation_year')::int
        when p_profile ? 'graduation_year' then null
        else a.graduation_year end,
      photo_path=case when p_profile ? 'photo_path' then nullif(p_profile->>'photo_path','') else a.photo_path end,
      updated_at=now()
  where a.id=p_athlete_id;

  insert into public.athlete_profile_details(
    athlete_id,school_level,grade_level,shirt_size,shorts_size,shoe_size,singlet_size,warmup_top_size,warmup_bottom_size,updated_by,updated_at
  ) values (
    p_athlete_id,
    nullif(p_profile->>'school_level',''),
    nullif(p_profile->>'grade_level',''),
    nullif(p_profile->>'shirt_size',''),
    nullif(p_profile->>'shorts_size',''),
    nullif(p_profile->>'shoe_size',''),
    nullif(p_profile->>'singlet_size',''),
    nullif(p_profile->>'warmup_top_size',''),
    nullif(p_profile->>'warmup_bottom_size',''),
    auth.uid(),now()
  )
  on conflict (athlete_id) do update set
    school_level=case when p_profile ? 'school_level' then nullif(p_profile->>'school_level','') else public.athlete_profile_details.school_level end,
    grade_level=case when p_profile ? 'grade_level' then nullif(p_profile->>'grade_level','') else public.athlete_profile_details.grade_level end,
    shirt_size=case when p_profile ? 'shirt_size' then nullif(p_profile->>'shirt_size','') else public.athlete_profile_details.shirt_size end,
    shorts_size=case when p_profile ? 'shorts_size' then nullif(p_profile->>'shorts_size','') else public.athlete_profile_details.shorts_size end,
    shoe_size=case when p_profile ? 'shoe_size' then nullif(p_profile->>'shoe_size','') else public.athlete_profile_details.shoe_size end,
    singlet_size=case when p_profile ? 'singlet_size' then nullif(p_profile->>'singlet_size','') else public.athlete_profile_details.singlet_size end,
    warmup_top_size=case when p_profile ? 'warmup_top_size' then nullif(p_profile->>'warmup_top_size','') else public.athlete_profile_details.warmup_top_size end,
    warmup_bottom_size=case when p_profile ? 'warmup_bottom_size' then nullif(p_profile->>'warmup_bottom_size','') else public.athlete_profile_details.warmup_bottom_size end,
    updated_by=auth.uid(),updated_at=now();

  if v_can_edit_private then
    insert into public.athlete_private_identity(athlete_id,birth_date,share_birth_date_with_coaches,updated_at)
    values (
      p_athlete_id,
      v_birth,
      case when v_can_control_sensitive then coalesce((p_profile->>'share_birth_date_with_coaches')::boolean,false) else false end,
      now()
    )
    on conflict (athlete_id) do update set
      birth_date=coalesce(v_birth,public.athlete_private_identity.birth_date),
      share_birth_date_with_coaches=case
        when v_can_control_sensitive and p_profile ? 'share_birth_date_with_coaches'
        then coalesce((p_profile->>'share_birth_date_with_coaches')::boolean,false)
        else public.athlete_private_identity.share_birth_date_with_coaches end,
      updated_at=now();

    insert into public.athlete_private_contact(
      athlete_id,email,phone,share_email_with_coaches,share_phone_with_coaches,sms_opt_in,updated_at
    )
    values (
      p_athlete_id,
      nullif(lower(trim(p_profile->>'email')),''),
      nullif(trim(p_profile->>'phone'),''),
      case when v_can_control_sensitive then coalesce((p_profile->>'share_email_with_coaches')::boolean,false) else false end,
      case when v_can_control_sensitive then coalesce((p_profile->>'share_phone_with_coaches')::boolean,false) else false end,
      case when v_can_control_sensitive then coalesce((p_profile->>'sms_opt_in')::boolean,false) else false end,
      now()
    )
    on conflict (athlete_id) do update set
      email=case when p_profile ? 'email' then nullif(lower(trim(p_profile->>'email')),'') else public.athlete_private_contact.email end,
      phone=case when p_profile ? 'phone' then nullif(trim(p_profile->>'phone'),'') else public.athlete_private_contact.phone end,
      share_email_with_coaches=case
        when v_can_control_sensitive and p_profile ? 'share_email_with_coaches'
        then coalesce((p_profile->>'share_email_with_coaches')::boolean,false)
        else public.athlete_private_contact.share_email_with_coaches end,
      share_phone_with_coaches=case
        when v_can_control_sensitive and p_profile ? 'share_phone_with_coaches'
        then coalesce((p_profile->>'share_phone_with_coaches')::boolean,false)
        else public.athlete_private_contact.share_phone_with_coaches end,
      sms_opt_in=case
        when v_can_control_sensitive and p_profile ? 'sms_opt_in'
        then coalesce((p_profile->>'sms_opt_in')::boolean,false)
        else public.athlete_private_contact.sms_opt_in end,
      updated_at=now();

    if p_profile ? 'medical_conditions' and jsonb_typeof(p_profile->'medical_conditions')='array' then
      select coalesce(array_agg(value),'{}') into v_conditions
      from jsonb_array_elements_text(p_profile->'medical_conditions');
    else
      select conditions into v_conditions from public.athlete_medical_private where athlete_id=p_athlete_id;
    end if;

    insert into public.athlete_medical_private(
      athlete_id,conditions,notes,rescue_item_location,disclose_to_coaches,updated_at
    ) values (
      p_athlete_id,
      coalesce(v_conditions,'{}'),
      nullif(p_profile->>'medical_notes',''),
      nullif(p_profile->>'rescue_item_location',''),
      case when v_can_control_sensitive then coalesce((p_profile->>'disclose_medical_to_coaches')::boolean,false) else false end,
      now()
    )
    on conflict (athlete_id) do update set
      conditions=coalesce(v_conditions,public.athlete_medical_private.conditions),
      notes=case when p_profile ? 'medical_notes' then nullif(p_profile->>'medical_notes','') else public.athlete_medical_private.notes end,
      rescue_item_location=case when p_profile ? 'rescue_item_location' then nullif(p_profile->>'rescue_item_location','') else public.athlete_medical_private.rescue_item_location end,
      disclose_to_coaches=case
        when v_can_control_sensitive and p_profile ? 'disclose_medical_to_coaches'
        then coalesce((p_profile->>'disclose_medical_to_coaches')::boolean,false)
        else public.athlete_medical_private.disclose_to_coaches end,
      updated_at=now();
  end if;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata)
  values (auth.uid(),'update_athlete_profile','athlete',p_athlete_id,jsonb_build_object('team_id',p_team_id));

  return public.get_athlete_profile_for_team(p_athlete_id,p_team_id);
end;
$function$;
