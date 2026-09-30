CREATE OR REPLACE FUNCTION private.team_people_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 actor uuid=auth.uid(); tid uuid; uid uuid; org uuid; actor_org_admin boolean; target_org_admin boolean;
 role_key text; member_role text; title text; perms jsonb; admin_access boolean; existing jsonb;
 people jsonb; row_data jsonb; result jsonb; linked_parent boolean; has_athlete boolean; minor boolean;
 athlete_ids uuid[]; roster_count integer=0; profile_name text; email text;
begin
 if actor is null or exists(select 1 from private.team_logins where user_id=actor) then raise exception 'Personal administrator account required'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16384 then raise exception 'Invalid team people request'; end if;
 tid:=(p_data->>'team_id')::uuid;
 if tid is null or not public.is_team_admin(tid) then raise exception 'Team administrator access required'; end if;
 select organization_id into org from public.teams where id=tid;
 select exists(select 1 from public.organization_memberships where organization_id=org and user_id=actor and role='organization_admin') into actor_org_admin;

 if p_action='list' then
  existing:=public.get_team_adult_access(tid);
  with ids as (
   select distinct m.user_id from public.team_memberships m where m.team_id=tid and m.active and m.role in ('head_coach','assistant_coach','manager','athlete','parent_guardian')
   union select o.user_id from public.organization_memberships o where o.organization_id=org and o.role='organization_admin'
  ), entries as (
   select i.user_id,coalesce(e.value,'{}') || jsonb_build_object(
    'user_id',i.user_id,'display_name',private.communication_person_name(tid,i.user_id),
    'email',u.email,'athletes',coalesce(a.rows,'[]'),'has_active_athlete',coalesce(a.active,false),
    'known_minor',exists(select 1 from public.team_memberships own join public.athletes x on x.id=own.athlete_id where own.user_id=i.user_id and own.role='athlete' and x.birth_date>(current_date-interval '18 years')::date),
    'revision',private.team_people_revision(tid,i.user_id)
   ) as entry
   from ids i join auth.users u on u.id=i.user_id left join public.profiles p on p.id=i.user_id
   left join lateral (select value from jsonb_array_elements(existing) where value->>'user_id'=i.user_id::text) e on true
   left join lateral (
    select jsonb_agg(jsonb_build_object('athlete_id',q.id,'name',q.name,'active',q.active) order by q.name) as rows, bool_or(q.active) as active,min(q.name) as name
    from (select a.id,a.first_name||' '||a.last_name as name,bool_or(m.active) as active from public.team_memberships m join public.athletes a on a.id=m.athlete_id where m.team_id=tid and m.user_id=i.user_id and m.role='athlete' group by a.id,a.first_name,a.last_name) q
   ) a on true
   where not exists(select 1 from private.team_logins l where l.user_id=i.user_id)
  ) select coalesce(jsonb_agg(entry order by lower(entry->>'display_name'),user_id),'[]') into people from entries;
  return jsonb_build_object('people',people,'organization_admin',actor_org_admin);
 end if;
 if p_action<>'save' then raise exception 'Unknown team people action'; end if;
 -- Serialize changes from this API, then recheck authority after waiting.
 perform 1 from public.teams where id=tid for update;
 if not public.is_team_admin(tid) then raise exception 'Team administrator access required'; end if;
 uid:=(p_data->>'user_id')::uuid;
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Choose a personal account, not a team device or test login'; end if;
 if not exists(select 1 from public.team_memberships m where m.team_id=tid and m.user_id=uid and m.active and m.role in ('head_coach','assistant_coach','manager','athlete','parent_guardian'))
    and not exists(select 1 from public.organization_memberships o where o.organization_id=org and o.user_id=uid and o.role='organization_admin') then raise exception 'This account is not connected to this team'; end if;
 if (p_data->>'revision') is distinct from private.team_people_revision(tid,uid) then raise exception 'This person changed. Reload the list before saving'; end if;
 role_key:=p_data->>'role_key';
 if role_key is null or role_key not in ('head_coach','assistant_coach','volunteer_coach','team_leader','team_mom','team_trainer','club_president','limited_staff','parent_only') then raise exception 'Choose a supported adult role'; end if;
 if role_key='club_president' and not actor_org_admin then raise exception 'Only an organization administrator can assign Club President'; end if;
 select exists(select 1 from public.organization_memberships where organization_id=org and user_id=uid and role='organization_admin') into target_org_admin;
 select exists(select 1 from public.team_memberships where team_id=tid and user_id=uid and active and role='parent_guardian') into linked_parent;
 select coalesce(array_agg(distinct athlete_id) filter(where athlete_id is not null),'{}'),coalesce(bool_or(active),false)
 into athlete_ids,has_athlete from public.team_memberships where team_id=tid and user_id=uid and role='athlete';
 select exists(select 1 from public.team_memberships own join public.athletes a on a.id=own.athlete_id where own.user_id=uid and own.role='athlete' and a.birth_date>(current_date-interval '18 years')::date) into minor;
 if role_key<>'parent_only' then
  if minor then raise exception 'This account has an athlete profile under 18. Adult staff access cannot be assigned'; end if;
  if has_athlete and (p_data->'confirm_adult') is distinct from 'true'::jsonb then raise exception 'Confirm that this is the adult account and the person is at least 18'; end if;
 end if;
 if role_key='parent_only' and (not linked_parent or target_org_admin) then raise exception 'Parent-only access requires a linked parent without organization administrator access'; end if;
 if jsonb_typeof(coalesce(p_data->'permissions','{}'))<>'object' then raise exception 'Invalid permissions'; end if;
 if length(coalesce(p_data->>'title',''))>100 then raise exception 'Keep the displayed title within 100 characters'; end if;
 admin_access:=coalesce(p_data->'team_admin'='true'::jsonb,false) or role_key in ('head_coach','club_president');
 if role_key='parent_only' then admin_access:=false; end if;
 -- Never leave the team with no personal administrator.
 if not admin_access and not exists(select 1 from public.organization_memberships o where o.organization_id=org and o.role='organization_admin')
 and not exists(select 1 from public.team_memberships m where m.team_id=tid and m.user_id<>uid and m.active and (m.role='head_coach' or (m.role in ('assistant_coach','manager') and m.permissions->>'team_admin'='true'))) then
  raise exception 'Keep at least one team administrator before changing this role';
 end if;
 select u.email,private.communication_person_name(tid,uid) into email,profile_name from auth.users u left join public.profiles p on p.id=u.id where u.id=uid;
 if email is null then raise exception 'Personal account not found'; end if;
 title:=coalesce(nullif(trim(p_data->>'title'),''),case role_key when 'head_coach' then 'Head Coach' when 'assistant_coach' then 'Assistant Coach' when 'volunteer_coach' then 'Volunteer Coach' when 'team_leader' then 'Team Leader' when 'team_mom' then 'Team Mom' when 'team_trainer' then 'Team Trainer' when 'club_president' then 'Club President' else 'Limited Staff' end);
 member_role:=case when role_key='head_coach' then 'head_coach' when role_key in ('assistant_coach','volunteer_coach') then 'assistant_coach' else 'manager' end;
 perms:=jsonb_build_object('staff_role',role_key,'display_title',title,'team_admin',admin_access,
  'attendance',coalesce(p_data->'permissions'->'attendance'='true'::jsonb,false),'weigh_in',coalesce(p_data->'permissions'->'weigh_in'='true'::jsonb,false),
  'equipment',coalesce(p_data->'permissions'->'equipment'='true'::jsonb,false),'checkout',coalesce(p_data->'permissions'->'checkout'='true'::jsonb,false),
  'mass_text',admin_access or coalesce(p_data->'permissions'->'mass_text'='true'::jsonb,false));
 delete from public.team_memberships where team_id=tid and user_id=uid and role in ('head_coach','assistant_coach','manager');
 if role_key<>'parent_only' then
  insert into public.team_memberships(team_id,user_id,role,permissions,active) values(tid,uid,member_role,perms,true);
  if role_key='club_president' then insert into public.organization_memberships(organization_id,user_id,role) values(org,uid,'organization_admin') on conflict(organization_id,user_id) do update set role='organization_admin'; end if;
  insert into public.team_staff_profiles(team_id,user_id,display_name,title,contact_email,updated_at) values(tid,uid,profile_name,title,email,now())
   on conflict(team_id,user_id) do update set title=excluded.title,updated_at=now();
  if has_athlete and p_data->'retire_athlete'='true'::jsonb then
   -- Only this adult's own active roster entries on this team. No guardian edits,
   -- deletion, global profile change, historical-season edit or other-team change.
   update public.roster_memberships r set active=false,prior_active_status=case when r.roster_status in ('varsity','jv','both','unassigned') then r.roster_status else r.prior_active_status end,
    roster_status='inactive',status_reason='Adult staff role; athlete history retained',status_changed_at=now(),status_changed_by=actor
   from public.seasons s where s.id=r.season_id and s.team_id=tid and s.active and r.active and r.athlete_id=any(athlete_ids);
   get diagnostics roster_count=row_count;
   update public.team_memberships set active=false,notifications_paused=true where team_id=tid and user_id=uid and role='athlete' and active;
  end if;
 end if;
 result:=jsonb_build_object('team_id',tid,'user_id',uid,'staff_role',role_key,'retired_rosters',roster_count,'parent_access_retained',linked_parent,'organization_admin_retained',target_org_admin or role_key='club_president');
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(actor,'edit_team_people','team',tid,result||jsonb_build_object('confirmed_adult',coalesce(p_data->'confirm_adult'='true'::jsonb,false),'team_admin',admin_access));
 return result;
end;
$function$;


CREATE OR REPLACE FUNCTION public.create_adult_staff_invitation(p_team_id uuid, p_email text, p_role_key text, p_title text DEFAULT NULL::text, p_permissions jsonb DEFAULT '{}'::jsonb, p_team_admin boolean DEFAULT false, p_expires_in_days integer DEFAULT 14)
 RETURNS TABLE(invitation_id uuid, invitation_token text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_token text; v_id uuid; v_role_key text:=lower(trim(coalesce(p_role_key,''))); v_title text; v_team_admin boolean; v_permissions jsonb; v_mass_text boolean;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if; if not public.is_team_admin(p_team_id) then raise exception 'team admin access required'; end if;
  if nullif(lower(trim(coalesce(p_email,''))),'') is null or position('@' in trim(p_email))<2 then raise exception 'valid email required'; end if;
  if v_role_key not in ('head_coach','assistant_coach','volunteer_coach','team_leader','team_mom','team_trainer','club_president','limited_staff') then raise exception 'invalid adult team role'; end if;
  v_title:=coalesce(nullif(trim(coalesce(p_title,'')),''),case v_role_key when 'head_coach' then 'Head Coach' when 'assistant_coach' then 'Assistant Coach' when 'volunteer_coach' then 'Volunteer Coach' when 'team_leader' then 'Team Leader' when 'team_mom' then 'Team Mom' when 'team_trainer' then 'Team Trainer' when 'club_president' then 'Club President' else 'Limited Staff' end);
  v_team_admin:=coalesce(p_team_admin,false) or v_role_key in ('head_coach','club_president');
  v_mass_text:=v_team_admin or case when jsonb_typeof(p_permissions->'mass_text')='boolean' then (p_permissions->>'mass_text')::boolean else v_role_key in ('head_coach','assistant_coach','volunteer_coach','team_leader','club_president') end;
  v_permissions:=jsonb_build_object('attendance',case when jsonb_typeof(p_permissions->'attendance')='boolean' then (p_permissions->>'attendance')::boolean else false end,'weigh_in',case when jsonb_typeof(p_permissions->'weigh_in')='boolean' then (p_permissions->>'weigh_in')::boolean else false end,'equipment',case when jsonb_typeof(p_permissions->'equipment')='boolean' then (p_permissions->>'equipment')::boolean else false end,'checkout',case when jsonb_typeof(p_permissions->'checkout')='boolean' then (p_permissions->>'checkout')::boolean else false end,'mass_text',v_mass_text,'staff_role',v_role_key,'display_title',v_title,'team_admin',v_team_admin,'organization_admin',v_role_key='club_president');
  update public.team_staff_invitations set status='revoked' where team_id=p_team_id and lower(email)=lower(trim(p_email)) and status='pending';
  v_token:='WMM-'||encode(extensions.gen_random_bytes(24),'hex');
  insert into public.team_staff_invitations(team_id,email,role,permissions,token_hash,created_by,expires_at) values(p_team_id,lower(trim(p_email)),'manager',v_permissions,encode(extensions.digest(v_token,'sha256'),'hex'),(select auth.uid()),now()+make_interval(days=>greatest(coalesce(p_expires_in_days,14),1))) returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values((select auth.uid()),'create_adult_staff_invitation','team_staff_invitation',v_id,jsonb_build_object('team_id',p_team_id,'email',lower(trim(p_email)),'staff_role',v_role_key,'team_admin',v_team_admin,'mass_text',v_mass_text));
  return query select v_id,v_token;
end; $function$;


CREATE OR REPLACE FUNCTION public.assign_team_adult_role(p_team_id uuid, p_user_id uuid, p_role_key text, p_title text DEFAULT NULL::text, p_permissions jsonb DEFAULT '{}'::jsonb, p_team_admin boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role_key text:=lower(trim(coalesce(p_role_key,''))); v_membership_role text; v_title text; v_permissions jsonb; v_team_admin boolean; v_org_id uuid; v_email text; v_name text; v_mass_text boolean;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if not public.is_team_admin(p_team_id) then raise exception 'team admin access required'; end if;
  if v_role_key not in ('head_coach','assistant_coach','volunteer_coach','team_leader','team_mom','team_trainer','club_president','limited_staff') then raise exception 'invalid adult team role'; end if;
  if v_role_key='team_trainer' and exists(select 1 from public.team_memberships m join public.athletes a on a.id=m.athlete_id left join public.athlete_private_identity i on i.athlete_id=a.id where m.user_id=p_user_id and m.role='athlete' and coalesce(i.birth_date,a.birth_date)>(current_date-interval '18 years')::date) then raise exception 'Team Trainer must be an adult';end if;
  select t.organization_id into v_org_id from public.teams t where t.id=p_team_id; if v_org_id is null then raise exception 'team not found'; end if;
  if not (exists(select 1 from public.team_memberships tm where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.active=true and tm.role in ('head_coach','assistant_coach','manager','parent_guardian')) or exists(select 1 from public.organization_memberships om where om.organization_id=v_org_id and om.user_id=p_user_id)) then raise exception 'adult must already be connected to this team or organization'; end if;
  select u.email,coalesce(nullif(p.display_name,''),nullif(u.raw_user_meta_data->>'full_name',''),split_part(coalesce(u.email,''),'@',1)) into v_email,v_name from auth.users u left join public.profiles p on p.id=u.id where u.id=p_user_id;
  if v_email is null then raise exception 'adult account not found'; end if;
  v_membership_role:=case when v_role_key='head_coach' then 'head_coach' when v_role_key in ('assistant_coach','volunteer_coach') then 'assistant_coach' else 'manager' end;
  v_title:=coalesce(nullif(trim(coalesce(p_title,'')),''),case v_role_key when 'head_coach' then 'Head Coach' when 'assistant_coach' then 'Assistant Coach' when 'volunteer_coach' then 'Volunteer Coach' when 'team_leader' then 'Team Leader' when 'team_mom' then 'Team Mom' when 'team_trainer' then 'Team Trainer' when 'club_president' then 'Club President' else 'Limited Staff' end);
  v_team_admin:=coalesce(p_team_admin,false) or v_role_key in ('head_coach','club_president');
  v_mass_text:=v_team_admin or case when jsonb_typeof(p_permissions->'mass_text')='boolean' then (p_permissions->>'mass_text')::boolean else v_role_key in ('head_coach','assistant_coach','volunteer_coach','team_leader','club_president') end;
  v_permissions:=jsonb_build_object('attendance',case when jsonb_typeof(p_permissions->'attendance')='boolean' then (p_permissions->>'attendance')::boolean else false end,'weigh_in',case when jsonb_typeof(p_permissions->'weigh_in')='boolean' then (p_permissions->>'weigh_in')::boolean else false end,'equipment',case when jsonb_typeof(p_permissions->'equipment')='boolean' then (p_permissions->>'equipment')::boolean else false end,'checkout',case when jsonb_typeof(p_permissions->'checkout')='boolean' then (p_permissions->>'checkout')::boolean else false end,'mass_text',v_mass_text,'staff_role',v_role_key,'display_title',v_title,'team_admin',v_team_admin);
  delete from public.team_memberships tm where tm.team_id=p_team_id and tm.user_id=p_user_id and tm.role in ('head_coach','assistant_coach','manager');
  insert into public.team_memberships(team_id,user_id,role,permissions,active) values(p_team_id,p_user_id,v_membership_role,v_permissions,true);
  if v_role_key='club_president' then insert into public.organization_memberships(organization_id,user_id,role) values(v_org_id,p_user_id,'organization_admin') on conflict(organization_id,user_id) do update set role='organization_admin'; end if;
  insert into public.team_staff_profiles(team_id,user_id,display_name,title,contact_email,share_email_with_athletes,share_phone_with_athletes,share_email_with_parents,share_phone_with_parents,updated_at) values(p_team_id,p_user_id,v_name,v_title,lower(v_email),false,false,false,false,now()) on conflict(team_id,user_id) do update set display_name=coalesce(nullif(public.team_staff_profiles.display_name,''),excluded.display_name),title=excluded.title,contact_email=coalesce(nullif(public.team_staff_profiles.contact_email,''),excluded.contact_email),updated_at=now();
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values((select auth.uid()),'assign_adult_team_role','team',p_team_id,jsonb_build_object('assigned_user_id',p_user_id,'staff_role',v_role_key,'membership_role',v_membership_role,'title',v_title,'team_admin',v_team_admin,'mass_text',v_mass_text,'organization_admin',v_role_key='club_president'));
  return jsonb_build_object('team_id',p_team_id,'user_id',p_user_id,'staff_role',v_role_key,'membership_role',v_membership_role,'title',v_title,'team_admin',v_team_admin,'mass_text',v_mass_text,'organization_admin',v_role_key='club_president');
end; $function$;


CREATE OR REPLACE FUNCTION public.accept_manager_invitation(p_invitation_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_inv public.team_staff_invitations%rowtype;
  v_user_email text;
  v_role_key text;
  v_membership_role text;
  v_title text;
  v_org_id uuid;
  v_name text;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  select u.email into v_user_email from auth.users u where u.id=(select auth.uid());

  select * into v_inv
  from public.team_staff_invitations
  where token_hash=encode(extensions.digest(p_invitation_token,'sha256'),'hex')
    and status='pending'
    and (expires_at is null or expires_at>now())
  for update;

  if v_inv.id is null then raise exception 'invalid or expired invitation'; end if;
  if v_user_email is null or lower(v_user_email)<>lower(v_inv.email) then
    raise exception 'invitation email does not match signed-in account';
  end if;

  v_role_key := coalesce(nullif(v_inv.permissions->>'staff_role',''),'limited_staff');
  if v_role_key not in ('head_coach','assistant_coach','volunteer_coach','team_leader','team_mom','team_trainer','club_president','limited_staff') then
    raise exception 'invalid adult team role';
  end if;

  v_membership_role := case
    when v_role_key='head_coach' then 'head_coach'
    when v_role_key in ('assistant_coach','volunteer_coach') then 'assistant_coach'
    else 'manager'
  end;
  v_title := coalesce(
    nullif(v_inv.permissions->>'display_title',''),
    case v_role_key
      when 'head_coach' then 'Head Coach'
      when 'assistant_coach' then 'Assistant Coach'
      when 'volunteer_coach' then 'Volunteer Coach'
      when 'team_leader' then 'Team Leader'
      when 'team_mom' then 'Team Mom'
      when 'team_trainer' then 'Team Trainer'
      when 'club_president' then 'Club President'
      else 'Limited Staff'
    end
  );

  delete from public.team_memberships tm
  where tm.team_id=v_inv.team_id
    and tm.user_id=(select auth.uid())
    and tm.role in ('head_coach','assistant_coach','manager');

  insert into public.team_memberships(team_id,user_id,role,permissions,active)
  values(v_inv.team_id,(select auth.uid()),v_membership_role,v_inv.permissions,true);

  if coalesce((v_inv.permissions->>'organization_admin')::boolean,false) or v_role_key='club_president' then
    select t.organization_id into v_org_id from public.teams t where t.id=v_inv.team_id;
    insert into public.organization_memberships(organization_id,user_id,role)
    values(v_org_id,(select auth.uid()),'organization_admin')
    on conflict(organization_id,user_id) do update set role='organization_admin';
  end if;

  select coalesce(
    nullif(p.display_name,''),
    nullif(u.raw_user_meta_data->>'full_name',''),
    nullif(u.raw_user_meta_data->>'name',''),
    split_part(coalesce(u.email,''),'@',1)
  )
  into v_name
  from auth.users u
  left join public.profiles p on p.id=u.id
  where u.id=(select auth.uid());

  insert into public.team_staff_profiles(
    team_id,user_id,display_name,title,contact_email,
    share_email_with_athletes,share_phone_with_athletes,
    share_email_with_parents,share_phone_with_parents,updated_at
  )
  values(
    v_inv.team_id,(select auth.uid()),v_name,v_title,lower(v_user_email),
    false,false,false,false,now()
  )
  on conflict(team_id,user_id) do update
  set display_name=coalesce(nullif(public.team_staff_profiles.display_name,''),excluded.display_name),
      title=excluded.title,
      contact_email=coalesce(nullif(public.team_staff_profiles.contact_email,''),excluded.contact_email),
      updated_at=now();

  update public.team_staff_invitations set status='accepted' where id=v_inv.id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata)
  values(
    (select auth.uid()),'accept_adult_staff_invitation','team_staff_invitation',v_inv.id,
    jsonb_build_object(
      'team_id',v_inv.team_id,
      'staff_role',v_role_key,
      'membership_role',v_membership_role,
      'team_admin',coalesce((v_inv.permissions->>'team_admin')::boolean,false),
      'organization_admin',coalesce((v_inv.permissions->>'organization_admin')::boolean,false)
    )
  );

  return v_inv.team_id;
end;
$function$;

