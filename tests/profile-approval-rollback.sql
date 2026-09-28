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
declare pid uuid=current_setting('test.name_profile')::uuid;rid uuid;candidate jsonb;live jsonb;denied boolean;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'new_photo',true,'proposal',jsonb_build_object('name','Real Athlete','details','{"bio":"Private draft bio","music_title":"Example"}'::jsonb,'sharing','{"bio":true,"photo":true}'::jsonb,'discoverable',true)));
 rid:=(candidate->>'id')::uuid;
 perform set_config('test.approval_id',rid::text,true);perform set_config('test.approval_path',candidate->>'path',true);
 -- Upload through authenticated Storage RLS; neither a public path nor a live photo.
 insert into storage.objects(bucket_id,name,owner_id,metadata) values('profile-photo-requests',candidate->>'path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}');
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));
 live:=public.wrestling_profiles_request('view',jsonb_build_object('id',pid));
 if live->>'name'='Real Athlete' or live->'details'->>'bio'='Private draft bio' then raise exception 'Draft leaked to live profile';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 if jsonb_array_length(public.wm_profile_approval_request('list',jsonb_build_object('profile_id',pid)))<>0 then raise exception 'Parent saw unsent private draft';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 perform public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 perform public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 denied:=false;begin perform public.wm_profile_approval_request('approve',jsonb_build_object('id',rid));exception when others then denied:=true;end;if not denied then raise exception 'Athlete approved own draft';end if;
 denied:=false;begin perform public.update_profile_name(pid,'Bypass');exception when others then denied:=true;end;if not denied then raise exception 'Minor name bypass';end if;
 denied:=false;begin update public.profiles set display_name='Bypass' where id=auth.uid();exception when others then denied:=true;end;if not denied then raise exception 'Account-name bypass';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_other'),true);
 if jsonb_array_length(public.wm_profile_approval_request('list'))<>0 then raise exception 'Unrelated viewer saw pending profile';end if;
 if exists(select 1 from storage.objects where bucket_id='profile-photo-requests' and name=candidate->>'path') then raise exception 'Unrelated viewer saw photo';end if;
 denied:=false;begin perform public.wm_profile_approval_request('approve',jsonb_build_object('id',rid));exception when others then denied:=true;end;if not denied then raise exception 'Unrelated approval';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 if jsonb_array_length(public.wm_profile_approval_request('list'))<>1 then raise exception 'Parent missing request';end if;
 if not exists(select 1 from storage.objects where bucket_id='profile-photo-requests' and name=candidate->>'path') then raise exception 'Parent missing photo';end if;
 if (select count(*) from public.communication_notifications where profile_request_id=rid)<>1 then raise exception 'Duplicate or missing parent notification';end if;
 denied:=false;begin perform public.wm_profile_approval_request('approve',jsonb_build_object('id',rid));exception when others then denied:=true;end;if not denied then raise exception 'Photo request approved without uploaded published photo';end if;
 candidate:=public.wm_profile_photo_request('prepare',jsonb_build_object('kind','social','id',pid));
 candidate:=candidate||jsonb_build_object('legacy_path',candidate->>'prefix'||'/'||gen_random_uuid()::text||'.jpg','social_path',pid::text||'/'||gen_random_uuid()::text||'.jpg','approval_id',rid);
 insert into storage.objects(bucket_id,name,owner_id,metadata) values(candidate->>'bucket',candidate->>'legacy_path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}'),('wrestling-profile-photos',candidate->>'social_path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}');
 perform public.wm_profile_photo_request('commit',candidate);
 live:=public.wrestling_profiles_request('view',jsonb_build_object('id',pid));
 if live->>'name'<>'Real Athlete' or live->'details'->>'bio'<>'Private draft bio' or live->>'discoverable'<>'true' then raise exception 'Complete draft not published';end if;
 if exists(select 1 from public.communication_notifications where profile_request_id=rid and read_at is null) then raise exception 'Approval notification stayed unread';end if;
 if (select display_name from public.profiles where id=auth.uid())<>'Original Parent' then raise exception 'Parent renamed';end if;
 -- Editing after approval has no public effect; parent rejects then a new draft can be sent.
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',jsonb_build_object('name','Next Name','details','{}'::jsonb)));
 rid:=(candidate->>'id')::uuid;perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));perform public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('reject',jsonb_build_object('id',rid));
 live:=public.wrestling_profiles_request('view',jsonb_build_object('id',pid));if live->>'name'<>'Real Athlete' then raise exception 'Rejection changed published name';end if;
 -- Stale requests cannot overwrite newer parent edits.
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',jsonb_build_object('name','Stale Name','details','{}'::jsonb)));
 rid:=(candidate->>'id')::uuid;perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));perform public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.update_profile_name(pid,'Parent Correction');
 denied:=false;begin perform public.wm_profile_approval_request('approve',jsonb_build_object('id',rid));exception when others then denied:=true;end;if not denied then raise exception 'Stale draft overwrote parent edit';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',jsonb_build_object('name','Final Athlete','details','{}'::jsonb)));
 rid:=(candidate->>'id')::uuid;perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));perform public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 denied:=false;begin update public.profiles set photo_path='unapproved.jpg' where id=auth.uid();exception when others then denied:=true;end;if not denied then raise exception 'Account-photo bypass';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('approve',jsonb_build_object('id',rid));
 live:=public.wrestling_profiles_request('view',jsonb_build_object('id',pid));if live->>'name'<>'Final Athlete' then raise exception 'No-photo approval failed';end if;
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;begin perform public.wm_profile_approval_request('list');exception when others then denied:=true;end;if not denied then raise exception 'Anonymous private draft access';end if;
end $$;
reset role;
do $$
begin
 if exists(select 1 from storage.buckets where id='profile-photo-requests' and public) then raise exception 'Draft bucket public';end if;
 if has_function_privilege('anon','public.wm_profile_approval_request(text,jsonb)','execute') then raise exception 'Anonymous execute allowed';end if;
 if has_table_privilege('authenticated','private.profile_approval_requests','select') then raise exception 'Private drafts directly exposed';end if;
end $$;
update public.team_memberships set active=false where user_id=current_setting('test.name_owner')::uuid and role='parent_guardian';
set local role authenticated;
do $$begin
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 if jsonb_array_length(public.wm_profile_approval_request('list',jsonb_build_object('profile_id',current_setting('test.name_profile'))))<>0 then raise exception 'Unlinked parent retained draft access';end if;
 if exists(select 1 from storage.objects where bucket_id='profile-photo-requests' and name=current_setting('test.approval_path')) then raise exception 'Unlinked parent retained photo access';end if;
end $$;
reset role;
select 'PASS: private draft, storage ownership, guardian notification, atomic photo and profile approval, reject, stale guard, name bypasses and anonymous/unrelated denial' as result;
rollback;
