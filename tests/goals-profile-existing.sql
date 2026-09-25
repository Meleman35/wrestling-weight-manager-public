CREATE OR REPLACE FUNCTION public.wrestling_profiles_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.wrestling_profiles_request(p_action,p_data) $function$
;
CREATE OR REPLACE FUNCTION private.wrestling_profiles_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); pid uuid; sid uuid; tid uuid; p private.wrestling_profiles%rowtype; d jsonb; sh jsonb; r record; result jsonb; member uuid; pos integer=0;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal account required'; end if;
 if octet_length(p_data::text)>30000 then raise exception 'Profile is too large'; end if;
 if p_action like 'spouse_%' then return private.wrestling_spouse_request(p_action,p_data);end if;
 if p_action='mine' then
 -- A minor athlete login uses its athlete profile, never a second adult identity.
 if not exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.user_id=uid and m.role='athlete' and m.active and (coalesce((select ai.birth_date from public.athlete_private_identity ai where ai.athlete_id=a.id),a.birth_date) is null or coalesce((select ai.birth_date from public.athlete_private_identity ai where ai.athlete_id=a.id),a.birth_date)>current_date-interval '18 years')) then
 insert into private.wrestling_profiles(user_id,name) select id,coalesce(nullif(display_name,''),'My profile') from public.profiles where id=uid on conflict(user_id) do nothing;
 end if;
 for r in select distinct on(a.profile_id) a.profile_id,a.first_name,a.last_name from public.athletes a where a.profile_id is not null and (public.is_guardian_for_athlete(a.id) or exists(select 1 from public.team_memberships m where m.athlete_id=a.id and m.user_id=uid and m.role='athlete' and m.active)) order by a.profile_id,a.created_at loop
 insert into private.wrestling_profiles(athlete_profile_id,name,details) values(r.profile_id,left(r.first_name||' '||r.last_name,120),'{"roles":"Athlete"}') on conflict(athlete_profile_id) do nothing;
 end loop;
 select coalesce(jsonb_agg(private.wrestling_profile_card(id) order by name),'[]') into result from private.wrestling_profiles where private.wrestling_profile_manager(id) or private.wrestling_profile_self(id);return result;
 end if;

 if p_action='browse' then
 select jsonb_build_object('rows',coalesce(jsonb_agg(card order by name,id) filter(where n<=30),'[]'::jsonb),'more',count(*)>30) into result
 from (select q.id,q.name,private.wrestling_profile_card(q.id,true) card,row_number() over(order by q.name,q.id)-greatest(0,least(10000,coalesce((p_data->>'offset')::int,0))) n
 from private.wrestling_profiles q where q.discoverable and private.wrestling_profile_visible(q.id)
 order by q.name,q.id limit 31 offset greatest(0,least(10000,coalesce((p_data->>'offset')::int,0)))) listing;
 return result;
 end if;

 if p_action='search' then
 if length(trim(p_data->>'query'))<2 then return '[]'; end if;
 select coalesce(jsonb_agg(private.wrestling_profile_card(id)),'[]') into result from (select id from private.wrestling_profiles where discoverable and name ilike '%'||left(p_data->>'query',80)||'%' and private.wrestling_profile_visible(id) order by name limit 30) s;return result;
 end if;

 if p_action='affiliation' then
 if length(trim(coalesce(p_data->>'name',''))) not between 2 and 160 then return '{"rows":[],"more":false}';end if;
 select jsonb_build_object('rows',coalesce(jsonb_agg(card order by name,id) filter(where rn<=greatest(0,least(10000,coalesce((p_data->>'offset')::integer,0)))+30),'[]'::jsonb),'more',count(*)>30) into result
 from (
 select q.id,q.name,private.wrestling_profile_card(q.id,true) card,row_number() over(order by q.name,q.id) rn
 from private.wrestling_profiles q
 where q.discoverable and q.sharing->>'affiliation'='true' and private.wrestling_profile_visible(q.id)
 and exists(select 1 from regexp_split_to_table(coalesce(q.details->>'affiliation',''),'[,;]') part where lower(trim(part))=lower(trim(p_data->>'name')))
 order by q.name,q.id limit 31 offset greatest(0,least(10000,coalesce((p_data->>'offset')::integer,0)))
 ) listing;
 return result;
 end if;

 pid:=nullif(p_data->>'id','')::uuid;
 if p_action='view' then
 result:=private.wrestling_profile_card(pid,coalesce((p_data->>'preview')::boolean,false));if result is null then raise exception 'Profile is private or unavailable';end if;
 select coalesce(jsonb_agg(private.wrestling_profile_card(c.member_id,true) order by c.position),'[]') into d from private.wrestling_corners c join private.wrestling_profiles m on m.id=c.member_id where c.profile_id=pid and private.wrestling_profile_teammates(pid,c.member_id) and m.discoverable and private.wrestling_profile_visible(c.member_id) and exists(select 1 from private.wrestling_follows f where f.source_id=pid and f.target_id=c.member_id and f.status='approved') and exists(select 1 from private.wrestling_follows f where f.target_id=pid and f.source_id=c.member_id and f.status='approved');
 select * into p from private.wrestling_profiles where id=pid;
 if coalesce((p_data->>'preview')::boolean,false) and not p.discoverable then
 return jsonb_build_object('id',pid,'discoverable',false,'unavailable',true,'details','{}'::jsonb,'corner','[]'::jsonb);
 end if;
 -- Parent family pins are returned only to their owner, never in the outside preview.
 if not coalesce((p_data->>'preview')::boolean,false) then
   select coalesce(jsonb_agg(private.wrestling_profile_card(c.member_id) order by c.position),'[]'::jsonb) into sh
   from private.wrestling_corners c join private.wrestling_profiles m on m.id=c.member_id
   where c.profile_id=pid and private.wrestling_profile_linked_child(pid,c.member_id);
   if p.user_id=uid and private.wrestling_profile_manager(pid) then result:=result||jsonb_build_object('family_corner',sh);end if;
   select parent.id into sid from private.wrestling_profiles parent
   where parent.user_id=uid and private.wrestling_profile_linked_child(parent.id,pid);
   if sid is not null then result:=result||jsonb_build_object('parent_connection',jsonb_build_object('profile_id',sid,'in_corner',exists(select 1 from private.wrestling_corners where profile_id=sid and member_id=pid)));end if;
 end if;
 return result||jsonb_build_object('corner',case when p.sharing->>'corner'='true' or (private.wrestling_profile_manager(pid) and not coalesce((p_data->>'preview')::boolean,false)) then d else '[]'::jsonb end);
 end if;
 if p_action='family_corner' then
 sid:=pid;tid:=nullif(p_data->>'target','')::uuid;
 if not private.wrestling_profile_linked_child(sid,tid) then raise exception 'An active linked parent/guardian is required';end if;
 if jsonb_typeof(p_data->'show') is distinct from 'boolean' then raise exception 'Choose whether to show this child';end if;
 perform 1 from private.wrestling_profiles where id=sid for update;
 if (p_data->>'show')::boolean then
   if not exists(select 1 from private.wrestling_corners where profile_id=sid and member_id=tid) then
     select n into pos from generate_series(1,8) n where not exists(select 1 from private.wrestling_corners where profile_id=sid and position=n) order by n limit 1;
     if pos is null then raise exception 'My Corner is full. Remove someone before adding another person (up to eight).';end if;
     insert into private.wrestling_corners(profile_id,member_id,position) values(sid,tid,pos);
   end if;
 else delete from private.wrestling_corners where profile_id=sid and member_id=tid;
 end if;
 return jsonb_build_object('ok',true,'in_corner',(p_data->>'show')::boolean);
 end if;
 if p_action='save' then
 if not private.wrestling_profile_manager(pid) then raise exception 'Linked parent/guardian or adult profile owner required';end if;
 select * into p from private.wrestling_profiles where id=pid for update;
 d:=coalesce(p_data->'details','{}');sh:=coalesce(p_data->'sharing','{}');
 if jsonb_typeof(d)<>'object' or jsonb_typeof(sh)<>'object' then raise exception 'Invalid profile';end if;
 if length(trim(p_data->>'name')) not between 1 and 120 then raise exception 'Name required (120 characters maximum)';end if;
 if length(coalesce(d->>'bio',''))>1200 or length(coalesce(d->>'roles',''))>160 or length(coalesce(d->>'affiliation',''))>160 then raise exception 'Please shorten the profile text';end if;
 if coalesce(d->>'music_url','')<>'' and d->>'music_url' !~ '^https://(music[.]apple[.]com|open[.]spotify[.]com)/[^[:space:]]+$' then raise exception 'Use an Apple Music or Spotify HTTPS link';end if;
 if coalesce(d->>'music_url','')<>'' and (p_data->>'music_approved') is distinct from 'true' then raise exception 'Confirm the song is clean and approved';end if;
 if d ? 'results' and (jsonb_typeof(d->'results')<>'array' or jsonb_array_length(d->'results')>30) then raise exception 'Use up to 30 tournament results';end if;
 if p.athlete_profile_id is not null then d:=d||'{"roles":"Athlete"}';end if;
 -- Only explicit, allow-listed fields enter this shareable record.
 select coalesce(jsonb_object_agg(key,value),'{}') into d from jsonb_each(d) where key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url']);
 select coalesce(jsonb_object_agg(key,value),'{}') into sh from jsonb_each(sh) where value in ('true'::jsonb,'false'::jsonb) and key=any(array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url','photo','corner','follow','outgoing_follow']);
 update private.wrestling_profiles set name=trim(p_data->>'name'),details=d,sharing=sh,discoverable=coalesce((p_data->>'discoverable')::boolean,false),updated_at=now() where id=pid;
 return private.wrestling_profile_card(pid);
 end if;
 if p_action='photo' then raise exception 'Refresh Wrestling Manager before changing your profile picture';end if;
 if p_action in ('follow','unfollow','links','corner') then
 sid:=pid;
 if not private.wrestling_profile_manager(sid) and not(private.wrestling_profile_self(sid) and exists(select 1 from private.wrestling_profiles where id=sid and sharing->>'outgoing_follow'='true')) then raise exception 'Parent approval is required to follow or manage My Corner';end if;
 if p_action='links' then
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'status',q.status,'family',q.family,'profile',q.card,
 'can_corner',q.family or (q.status='approved' and private.wrestling_profile_teammates(sid,q.id) and exists(select 1 from private.wrestling_follows f where f.source_id=q.id and f.target_id=sid and f.status='approved')),
 'in_corner',c.member_id is not null) order by c.position nulls last,q.family desc,q.name,q.id),'[]'::jsonb) into result
 from (
 select child.id,'approved'::text status,true family,child.name,private.wrestling_profile_card(child.id) card
 from private.wrestling_profiles child where private.wrestling_profile_linked_child(sid,child.id)
 union all
 select f.target_id,f.status,false,m.name,private.wrestling_profile_card(f.target_id,true)
 from private.wrestling_follows f join private.wrestling_profiles m on m.id=f.target_id
 where f.source_id=sid and not private.wrestling_profile_linked_child(sid,f.target_id)
 ) q left join private.wrestling_corners c on c.profile_id=sid and c.member_id=q.id;
 return result;
 end if;
 tid:=nullif(p_data->>'target','')::uuid;
 if p_action='unfollow' and private.wrestling_profile_linked_child(sid,tid) then raise exception 'Your linked child is followed automatically. Turn off Show in My Corner to hide their tile.';end if;
 if p_action='unfollow' then delete from private.wrestling_follows where source_id=sid and target_id=tid and status<>'blocked';return '{"ok":true}';end if;
 if p_action='follow' then
 if private.wrestling_profile_linked_child(sid,tid) then return '{"ok":true,"automatic":true}';end if;
 if not private.wrestling_profile_visible(tid) or not exists(select 1 from private.wrestling_profiles where id=tid and discoverable and sharing->>'follow'='true') then raise exception 'This profile is not accepting followers';end if;
 if exists(select 1 from private.wrestling_follows where ((source_id=sid and target_id=tid) or (source_id=tid and target_id=sid)) and status in ('blocked','denied')) then raise exception 'This connection is unavailable';end if;
 insert into private.wrestling_follows(source_id,target_id,status) values(sid,tid,'pending') on conflict(source_id,target_id) do nothing;return '{"ok":true}';
 end if;
 if p_action='corner' then
 if jsonb_typeof(p_data->'members') is distinct from 'array' then raise exception 'Choose your corner members';end if;
 if jsonb_array_length(p_data->'members')>8 then raise exception 'Choose up to eight people for My Corner';end if;
 perform 1 from private.wrestling_profiles where id=sid for update;
 delete from private.wrestling_corners where profile_id=sid;
 for member in select value::uuid from jsonb_array_elements_text(p_data->'members') loop
 if not private.wrestling_profile_linked_child(sid,member) and (not private.wrestling_profile_teammates(sid,member) or not exists(select 1 from private.wrestling_follows where source_id=sid and target_id=member and status='approved') or not exists(select 1 from private.wrestling_follows where source_id=member and target_id=sid and status='approved')) then raise exception 'Choose a linked child or mutual approved teammate for My Corner';end if;
 pos:=pos+1;insert into private.wrestling_corners values(sid,member,pos);
 end loop;return '{"ok":true}';
 end if;
 end if;
 if p_action='requests' then
 if not private.wrestling_profile_manager(pid) then raise exception 'Parent/owner permission required';end if;
 select coalesce(jsonb_agg(jsonb_build_object('source',f.source_id,'name',s.name,'status',f.status) order by f.created_at desc),'[]') into result from private.wrestling_follows f join private.wrestling_profiles s on s.id=f.source_id where f.target_id=pid;return result;
 end if;
 if p_action='review' then
 if not private.wrestling_profile_manager(pid) then raise exception 'Parent/owner permission required';end if;
 if p_data->>'status' not in ('approved','denied','blocked') then raise exception 'Invalid decision';end if;
 update private.wrestling_follows set status=p_data->>'status' where source_id=(p_data->>'source')::uuid and target_id=pid;
 return '{"ok":true}';
 end if;
 raise exception 'Unknown profile action';
end $function$
;
CREATE OR REPLACE FUNCTION public.is_guardian_for_athlete(check_athlete_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.athlete_guardians ag
    join public.team_memberships tm
      on tm.user_id=ag.guardian_user_id
     and tm.athlete_id=ag.athlete_id
     and tm.role='parent_guardian'
     and tm.active=true
    where ag.athlete_id=check_athlete_id
      and ag.guardian_user_id=auth.uid()
  );
$function$
;
CREATE OR REPLACE FUNCTION private.wrestling_profile_card(p_id uuid, p_preview boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p private.wrestling_profiles%rowtype; d jsonb='{}'; k text; own boolean;
begin
 if not private.wrestling_profile_visible(p_id) then return null;end if;
 select * into p from private.wrestling_profiles where id=p_id;
 own:=private.wrestling_profile_manager(p_id) and not p_preview;
 foreach k in array array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url'] loop
  if own or p.sharing->>k='true' then d:=d||jsonb_build_object(k,p.details->k);end if;
 end loop;
 return jsonb_build_object('id',p.id,'name',p.name,'athlete',p.athlete_profile_id is not null,
  'manager',private.wrestling_profile_manager(p_id),'self',private.wrestling_profile_self(p_id),
  'details',d,'discoverable',p.discoverable,'sharing',case when own then p.sharing else '{}'::jsonb end,
  'assigned_roles',case when own or p.sharing->>'roles'='true' then private.wrestling_role_badges(p.user_id,own or coalesce(p.sharing->>'affiliation'='true',false)) else '[]'::jsonb end,
  'spouse',private.wrestling_spouse_card(p_id,p_preview),
  'photo_path',case when own or p.sharing->>'photo'='true' then p.photo_path end,
  'photo_source',private.wrestling_profile_photo_source(p_id,p_preview));
end $function$
;
CREATE OR REPLACE FUNCTION private.wrestling_profile_visible(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(select 1 from private.team_logins where user_id=auth.uid()) and exists(select 1 from private.wrestling_profiles p where p.id=p_id and (
 private.wrestling_profile_manager(p.id) or private.wrestling_profile_self(p.id) or (p.discoverable and not exists(select 1 from private.wrestling_follows f where f.status='blocked' and ((f.target_id=p.id and private.wrestling_profile_self(f.source_id)) or (f.source_id=p.id and private.wrestling_profile_self(f.target_id)))))))
$function$
;