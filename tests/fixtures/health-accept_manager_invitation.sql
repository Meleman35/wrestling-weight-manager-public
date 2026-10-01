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
  if v_role_key not in ('head_coach','assistant_coach','volunteer_coach','team_leader','team_mom','club_president','limited_staff') then
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
