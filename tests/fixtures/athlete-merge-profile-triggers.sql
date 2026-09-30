CREATE OR REPLACE FUNCTION private.guard_athlete_protected_edits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION private.guard_managed_membership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a private.team_logins%rowtype; uid uuid;
begin
 if tg_table_name='athlete_guardians' then uid:=new.guardian_user_id; else uid:=new.user_id; end if;
 select * into a from private.team_logins where user_id=uid;
 if not found then return new; end if;
 if a.kind='shared' or tg_table_name<>'team_memberships' then raise exception 'Team logins cannot receive personal or organization roles.'; end if;
 if new.team_id<>a.team_id or new.role<>(case when a.kind='test_athlete' then 'athlete' else 'manager' end)
   or new.athlete_id is distinct from a.athlete_id or new.permissions is distinct from a.permissions
   or (new.active and (not a.active or a.state<>'ready')) then raise exception 'Manage this account through Team Logins.'; end if;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION private.guard_team_profile_edit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare aid uuid;pid uuid;v jsonb;prior jsonb;current_row jsonb;col text;changed boolean=false;
begin
 if auth.uid() is null then return new;end if;
 if tg_table_name='athletes' then aid:=new.id;else aid:=new.athlete_id;end if;
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

CREATE OR REPLACE FUNCTION public.is_self_athlete(check_athlete_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.team_memberships tm
    where tm.athlete_id=check_athlete_id
      and tm.user_id=auth.uid()
      and tm.role='athlete'
      and tm.active=true
  );
$function$
;

CREATE OR REPLACE FUNCTION public.sync_athlete_medical_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_profile_id uuid;
begin
  if pg_trigger_depth()>1 then return new; end if;
  select profile_id into v_profile_id from public.athletes where id=new.athlete_id;
  if v_profile_id is null then return new; end if;
  insert into public.athlete_medical_private(
    athlete_id,conditions,notes,rescue_item_location,disclose_to_coaches,updated_at
  )
  select a.id,new.conditions,new.notes,new.rescue_item_location,false,now()
  from public.athletes a
  where a.profile_id=v_profile_id and a.id<>new.athlete_id
  on conflict (athlete_id) do update set
    conditions=excluded.conditions,
    notes=excluded.notes,
    rescue_item_location=excluded.rescue_item_location,
    updated_at=now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_athlete_private_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_profile_id uuid;
begin
  if pg_trigger_depth()>1 then return new; end if;
  select profile_id into v_profile_id from public.athletes where id=new.athlete_id;
  if v_profile_id is null then return new; end if;
  insert into public.athlete_private_contact(
    athlete_id,email,phone,share_email_with_coaches,share_phone_with_coaches,sms_opt_in,updated_at
  )
  select a.id,new.email,new.phone,false,false,new.sms_opt_in,now()
  from public.athletes a
  where a.profile_id=v_profile_id and a.id<>new.athlete_id
  on conflict (athlete_id) do update set
    email=excluded.email,
    phone=excluded.phone,
    sms_opt_in=excluded.sms_opt_in,
    updated_at=now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_athlete_private_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_profile_id uuid;
begin
  if pg_trigger_depth()>1 then return new; end if;
  select profile_id into v_profile_id from public.athletes where id=new.athlete_id;
  if v_profile_id is null then return new; end if;
  insert into public.athlete_private_identity(athlete_id,birth_date,share_birth_date_with_coaches,updated_at)
  select a.id,new.birth_date,false,now()
  from public.athletes a
  where a.profile_id=v_profile_id and a.id<>new.athlete_id
  on conflict (athlete_id) do update set
    birth_date=excluded.birth_date,
    updated_at=now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_athlete_profile_details()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_profile_id uuid;
begin
  if pg_trigger_depth()>1 then return new; end if;
  select profile_id into v_profile_id from public.athletes where id=new.athlete_id;
  if v_profile_id is null then return new; end if;
  insert into public.athlete_profile_details(
    athlete_id,school_level,grade_level,shirt_size,shorts_size,shoe_size,
    singlet_size,warmup_top_size,warmup_bottom_size,updated_by,updated_at
  )
  select a.id,new.school_level,new.grade_level,new.shirt_size,new.shorts_size,new.shoe_size,
         new.singlet_size,new.warmup_top_size,new.warmup_bottom_size,new.updated_by,now()
  from public.athletes a
  where a.profile_id=v_profile_id and a.id<>new.athlete_id
  on conflict (athlete_id) do update set
    school_level=excluded.school_level,
    grade_level=excluded.grade_level,
    shirt_size=excluded.shirt_size,
    shorts_size=excluded.shorts_size,
    shoe_size=excluded.shoe_size,
    singlet_size=excluded.singlet_size,
    warmup_top_size=excluded.warmup_top_size,
    warmup_bottom_size=excluded.warmup_bottom_size,
    updated_by=excluded.updated_by,
    updated_at=now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_athlete_public_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if pg_trigger_depth()>1 or new.profile_id is null then return new; end if;
  update public.athletes a
  set first_name=new.first_name,
      last_name=new.last_name,
      graduation_year=new.graduation_year,
      photo_path=new.photo_path,
      updated_at=now()
  where a.profile_id=new.profile_id and a.id<>new.id;
  update public.athlete_profiles set updated_at=now() where id=new.profile_id;
  return new;
end;
$function$
;

CREATE TRIGGER trg_sync_athlete_public_profile AFTER UPDATE OF first_name, last_name, graduation_year, photo_path ON public.athletes FOR EACH ROW EXECUTE FUNCTION sync_athlete_public_profile();
CREATE TRIGGER trg_sync_athlete_profile_details AFTER INSERT OR UPDATE ON public.athlete_profile_details FOR EACH ROW EXECUTE FUNCTION sync_athlete_profile_details();
CREATE TRIGGER trg_sync_athlete_private_identity AFTER INSERT OR UPDATE OF birth_date ON public.athlete_private_identity FOR EACH ROW EXECUTE FUNCTION sync_athlete_private_identity();
CREATE TRIGGER trg_sync_athlete_private_contact AFTER INSERT OR UPDATE OF email, phone, sms_opt_in ON public.athlete_private_contact FOR EACH ROW EXECUTE FUNCTION sync_athlete_private_contact();
CREATE TRIGGER trg_sync_athlete_medical_profile AFTER INSERT OR UPDATE OF conditions, notes, rescue_item_location ON public.athlete_medical_private FOR EACH ROW EXECUTE FUNCTION sync_athlete_medical_profile();
CREATE TRIGGER guard_managed_membership BEFORE INSERT OR UPDATE ON public.team_memberships FOR EACH ROW EXECUTE FUNCTION private.guard_managed_membership();
CREATE TRIGGER guard_managed_guardian BEFORE INSERT OR UPDATE ON public.athlete_guardians FOR EACH ROW EXECUTE FUNCTION private.guard_managed_membership();
CREATE TRIGGER team_profile_parent_guard BEFORE UPDATE OF graduation_year ON public.athletes FOR EACH ROW EXECUTE FUNCTION private.guard_team_profile_edit();
CREATE TRIGGER team_details_parent_guard BEFORE INSERT OR UPDATE ON public.athlete_profile_details FOR EACH ROW EXECUTE FUNCTION private.guard_team_profile_edit();
CREATE TRIGGER team_medical_parent_guard BEFORE INSERT OR UPDATE ON public.athlete_medical_private FOR EACH ROW EXECUTE FUNCTION private.guard_team_profile_edit();
CREATE TRIGGER guard_athlete_protected_edits BEFORE UPDATE OF first_name, last_name, email, phone, birth_date, photo_path ON public.athletes FOR EACH ROW EXECUTE FUNCTION private.guard_athlete_protected_edits();
CREATE TRIGGER guard_athlete_contact_edits BEFORE INSERT OR UPDATE ON public.athlete_private_contact FOR EACH ROW EXECUTE FUNCTION private.guard_athlete_protected_edits();
CREATE TRIGGER guard_athlete_birth_edits BEFORE INSERT OR UPDATE ON public.athlete_private_identity FOR EACH ROW EXECUTE FUNCTION private.guard_athlete_protected_edits();
