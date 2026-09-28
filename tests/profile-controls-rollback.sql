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
declare pid uuid=current_setting('test.name_profile')::uuid;candidate jsonb;ctx jsonb;prop jsonb;rid uuid;outcome jsonb;denied boolean;photo jsonb;old_path text;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 ctx:=public.wm_profile_approval_request('context',jsonb_build_object('kind','social','id',pid));
 if ctx->'policy'->>'auto_approve'<>'false' or ctx->'policy'->>'review_photos'<>'true' then raise exception 'Unsafe default settings';end if;
 denied:=false;begin perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',true,'review_photos',false));exception when others then denied:=true;end;
 if not denied then raise exception 'Athlete changed parent policy';end if;
 prop:=jsonb_build_object('name',ctx->'expected'->>'name','details','{"bio":"Auto-approved bio"}'::jsonb,'sharing','{"bio":true,"photo":true}'::jsonb,'contact',ctx->'contact');
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',prop));rid:=(candidate->>'id')::uuid;
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));
 outcome:=public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 if outcome->>'status'<>'pending' then raise exception 'Default did not require review';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',true,'review_photos',true));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',prop));rid:=(candidate->>'id')::uuid;
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));
 outcome:=public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 if outcome->>'status'<>'approved' or outcome->>'auto_approved'<>'true' then raise exception 'Ordinary edit was not automatically approved';end if;
 if public.wrestling_profiles_request('view',jsonb_build_object('id',pid))->'details'->>'bio'<>'Auto-approved bio' then raise exception 'Automatic changes not live';end if;
 -- Name always waits, and the live profile keeps its previously approved value.
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',prop||'{"name":"Needs Review"}'));rid:=(candidate->>'id')::uuid;
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));outcome:=public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 if outcome->>'status'<>'pending' or public.wrestling_profiles_request('view',jsonb_build_object('id',pid))->>'name'='Needs Review' then raise exception 'Name bypassed review';end if;
 -- Contact and contact sharing always wait even with automatic ordinary edits.
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',prop||jsonb_build_object('contact',jsonb_build_object('email','athlete-contact@example.invalid','phone','3075550100','share_email_with_coaches',true,'share_phone_with_coaches',true))));rid:=(candidate->>'id')::uuid;
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));outcome:=public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 if outcome->>'status'<>'pending' then raise exception 'Contact bypassed review';end if;
 denied:=false;begin update public.profiles set phone='3075559999' where id=auth.uid();exception when others then denied:=true;end;if not denied then raise exception 'Direct account phone bypass';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('approve',jsonb_build_object('id',rid));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 ctx:=public.wm_profile_approval_request('context',jsonb_build_object('kind','social','id',pid));
 if ctx->'contact'->>'email'<>'athlete-contact@example.invalid' or (select phone from public.profiles where id=auth.uid())<>'3075550100' then raise exception 'Reviewed contacts did not save';end if;
 prop:=prop||jsonb_build_object('contact',ctx->'contact');
 -- Photo default is manual, including when ordinary edits are automatic.
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',prop,'new_photo',true));rid:=(candidate->>'id')::uuid;
 insert into storage.objects(bucket_id,name,owner_id,metadata) values(candidate->>'bucket',candidate->>'path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}');
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));outcome:=public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 if outcome->>'status'<>'pending' or outcome->>'auto_photo'='true' then raise exception 'Photo skipped required review';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',true,'review_photos',false));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 candidate:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',pid,'proposal',prop,'new_photo',true));rid:=(candidate->>'id')::uuid;
 insert into storage.objects(bucket_id,name,owner_id,metadata) values(candidate->>'bucket',candidate->>'path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}');
 perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',rid));outcome:=public.wm_profile_approval_request('submit',jsonb_build_object('id',rid));
 if outcome->>'auto_photo'<>'true' then raise exception 'Parent photo opt-in ignored';end if;
 photo:=public.wm_profile_photo_request('prepare',jsonb_build_object('kind','social','id',pid,'approval_id',rid));
 photo:=photo||jsonb_build_object('approval_id',rid,'legacy_path',photo->>'prefix'||'/'||gen_random_uuid()::text||'.jpg','social_path',pid::text||'/'||gen_random_uuid()::text||'.jpg');
 insert into storage.objects(bucket_id,name,owner_id,metadata) values(photo->>'bucket',photo->>'legacy_path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}'),('wrestling-profile-photos',photo->>'social_path',auth.uid()::text,'{"mimetype":"image/jpeg","size":100}');
 -- Revocation between prepare and commit must be authoritative.
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',false,'review_photos',false));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 denied:=false;begin perform public.wm_profile_photo_request('commit',photo);exception when others then denied:=true;end;if not denied then raise exception 'Photo committed after opt-out';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_owner'),true);
 perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',true,'review_photos',false));
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 perform public.wm_profile_photo_request('commit',photo);
 if (select photo_path from public.profiles where id=auth.uid()) is distinct from photo->>'legacy_path' then raise exception 'Automatic photo not synced to account';end if;
 if public.wrestling_profiles_request('view',jsonb_build_object('id',pid))->>'photo_path' is distinct from photo->>'social_path' then raise exception 'Automatic photo not live';end if;
 update storage.objects set metadata='{"mimetype":"image/jpeg","size":999}' where name=photo->>'legacy_path' and bucket_id=photo->>'bucket';
 if exists(select 1 from storage.objects where name=photo->>'legacy_path' and metadata->>'size'='999') then raise exception 'Live photo can be overwritten';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_other'),true);
 if jsonb_array_length(public.wm_profile_approval_request('settings',jsonb_build_object('profile_id',pid)))<>0 then raise exception 'Unrelated account saw private settings';end if;
 denied:=false;begin perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',pid,'auto_approve',true,'review_photos',false));exception when others then denied:=true;end;if not denied then raise exception 'Unrelated account changed settings';end if;
end $$;
reset role;
do $$
declare pid uuid=current_setting('test.name_profile')::uuid;aid uuid;team uuid=current_setting('test.name_team')::uuid;denied boolean;settings jsonb;
begin
 select a.id into aid from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where w.id=pid limit 1;
 perform set_config('request.jwt.claim.sub',current_setting('test.name_child'),true);
 denied:=false;begin perform public.update_athlete_profile_v2(aid,team,'{"phone":"3075559999"}');exception when others then denied:=true;end;if not denied then raise exception 'Legacy athlete contact bypass';end if;
 denied:=false;begin perform public.update_athlete_profile_v2(aid,team,'{"birth_date":"1990-01-01"}');exception when others then denied:=true;end;if not denied then raise exception 'Athlete self-declared adulthood';end if;
 update public.team_memberships set active=false where user_id=current_setting('test.name_owner')::uuid and role='parent_guardian';
 settings:=public.wm_profile_approval_request('settings',jsonb_build_object('profile_id',pid));
 if settings->0->'policy'->>'auto_approve'<>'false' then raise exception 'Unlinked parent policy stayed active';end if;
end $$;
rollback;
