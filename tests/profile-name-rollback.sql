-- Synthetic accounts only. Run after the migration; roll back all fixture data.
begin;
do $$
declare owner_id uuid=gen_random_uuid(); child_id uuid=gen_random_uuid(); other_id uuid=gen_random_uuid();
  t record; a uuid; w uuid;
begin
  insert into auth.users(id,aud,role,email) values
    (owner_id,'authenticated','authenticated','name-parent@example.invalid'),
    (child_id,'authenticated','authenticated','name-athlete@example.invalid'),
    (other_id,'authenticated','authenticated','name-other@example.invalid');
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  select * into t from public.bootstrap_wrestling_organization('Name Test Organization','Name Test Team','school','girls','2026-27');
  update public.profiles set display_name='Original Parent' where id=owner_id;
  update public.profiles set display_name='Original Athlete' where id=child_id;
  insert into public.athletes(organization_id,first_name,last_name,birth_date)
    values(t.organization_id,'Original','Athlete',current_date-interval '15 years') returning id into a;
  insert into public.team_memberships(team_id,user_id,role,athlete_id) values(t.team_id,child_id,'athlete',a);
  insert into public.team_memberships(team_id,user_id,role,athlete_id) values(t.team_id,owner_id,'parent_guardian',a);
  insert into public.athlete_guardians(athlete_id,guardian_user_id,name,invitation_status)
    values(a,owner_id,'Original Parent','accepted');
  perform public.wrestling_profiles_request('mine');
  select id into w from private.wrestling_profiles where athlete_profile_id=(select profile_id from public.athletes where id=a);
  update private.wrestling_profiles set details='{"bio":"Keep this bio"}',sharing='{"bio":false,"outgoing_follow":false}',discoverable=false where id=w;
  perform set_config('test.name_owner',owner_id::text,true);
  perform set_config('test.name_child',child_id::text,true);
  perform set_config('test.name_other',other_id::text,true);
  perform set_config('test.name_profile',w::text,true);
  perform set_config('test.name_team',t.team_id::text,true);
end $$;
set local role authenticated;
do $$
declare pid uuid=current_setting('test.name_profile')::uuid; own uuid; result jsonb; denied boolean;
begin
  -- Parent renames own profile, then the linked child. Neither changes the other identity.
  select (x->>'id')::uuid into own from jsonb_array_elements(public.wrestling_profiles_request('mine')) x where x->>'athlete'='false';
  if own is null then raise exception 'Missing parent profile'; end if;
  perform public.update_profile_name(own,'  Renamed Parent  ');
  if (select display_name from public.profiles where id=auth.uid())<>'Renamed Parent' then raise exception 'Parent name not synced'; end if;
  perform public.update_profile_name(pid,'Renamed Child');
  if (select display_name from public.profiles where id=auth.uid())<>'Renamed Parent' then raise exception 'Child rename changed parent'; end if;
  -- Existing account editor updates the same shared name, with existing RLS.
  update public.profiles set display_name='Account Parent' where id=auth.uid();
  result:=public.wrestling_profiles_request('view',jsonb_build_object('id',own));
  if result->>'name'<>'Account Parent' then raise exception 'Account name did not sync'; end if;
  -- Minor self is allowed to rename only, not change discovery/sharing.
  perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
  if (select display_name from public.profiles where id=auth.uid())<>'Renamed Child' then raise exception 'Linked child account not synced'; end if;
  perform public.update_profile_name(pid,'Zoë O’Neill-Smith');
  if (select display_name from public.profiles where id=auth.uid())<>'Zoë O’Neill-Smith' then raise exception 'Athlete own name not synced'; end if;
  denied:=false;
  begin perform public.wrestling_profiles_request('save',jsonb_build_object('id',pid,'name','Unauthorized sharing','discoverable',true)); exception when others then denied:=true; end;
  if not denied then raise exception 'Minor gained sharing permissions'; end if;
  denied:=false;
  begin perform public.update_profile_name(pid,'   '); exception when others then denied:=true; end;
  if not denied then raise exception 'Blank name accepted'; end if;
  denied:=false;
  begin perform public.update_profile_name(pid,repeat('x',121)); exception when others then denied:=true; end;
  if not denied then raise exception 'Overlong name accepted'; end if;
  perform set_config('request.jwt.claim.sub',current_setting('test.name_other'),true);
  denied:=false;
  begin perform public.update_profile_name(pid,'Unauthorized'); exception when others then denied:=true; end;
  if not denied then raise exception 'Unrelated person renamed child'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  denied:=false;
  begin perform public.update_profile_name(pid,'Signed out'); exception when others then denied:=true; end;
  if not denied then raise exception 'Signed-out rename accepted'; end if;
end $$;
reset role;
do $$
begin
  if not exists(select 1 from private.wrestling_profiles where id=current_setting('test.name_profile')::uuid and name='Zoë O’Neill-Smith' and details='{"bio":"Keep this bio"}'::jsonb and sharing='{"bio":false,"outgoing_follow":false}'::jsonb and not discoverable) then raise exception 'Name-only save changed profile settings'; end if;
  if not exists(select 1 from public.team_staff_profiles where user_id=current_setting('test.name_owner')::uuid and team_id=current_setting('test.name_team')::uuid and display_name='Account Parent') then raise exception 'Coach directory name not synced'; end if;
  if has_function_privilege('anon','public.update_profile_name(uuid,text)','execute') then raise exception 'Anonymous execute allowed'; end if;
end $$;
select 'PASS: own account, coach directory, shared profile, linked child, minor self, Unicode, validation, authorization and unchanged sharing' as result;
rollback;
