-- Verify the installed profile API's filtering using temporary values only.
begin;
do $$
declare uid uuid; pid uuid;
begin
 select p.user_id,p.id into uid,pid from private.wrestling_profiles p where p.user_id is not null and not exists(select 1 from private.team_logins t where t.user_id=p.user_id) and not exists(select 1 from public.team_memberships m where m.user_id=p.user_id and m.role='athlete') order by p.id limit 1;
 if uid is null then raise exception 'No adult profile available for rollback test';end if;
 perform set_config('wm.preview_test_id',pid::text,true);perform set_config('request.jwt.claim.sub',uid::text,true);
 update private.wrestling_profiles set discoverable=true,details=jsonb_build_object('bio','HIDDEN-PREVIEW-TEST','affiliation','SHARED-PREVIEW-TEST'),sharing='{"affiliation":true}',photo_path=null where id=pid;
end $$;
set local role authenticated;
do $$
declare pid uuid=current_setting('wm.preview_test_id')::uuid; owner jsonb; outside jsonb;
begin
 owner:=public.wrestling_profiles_request('view',jsonb_build_object('id',pid));
 outside:=public.wrestling_profiles_request('view',jsonb_build_object('id',pid,'preview',true));
 if owner->'details'->>'bio'<>'HIDDEN-PREVIEW-TEST' or outside->'details' ? 'bio' or outside ? 'family_corner' or outside->'details'->>'affiliation'<>'SHARED-PREVIEW-TEST' then raise exception 'Profile preview filtering failed';end if;
 perform set_config('wm.preview_result','Shared affiliation shown; private bio and family corner omitted by live server',true);
end $$;
reset role;
update private.wrestling_profiles set discoverable=false where id=current_setting('wm.preview_test_id')::uuid;
set local role authenticated;
do $$
declare outside jsonb;
begin
 outside:=public.wrestling_profiles_request('view',jsonb_build_object('id',current_setting('wm.preview_test_id')::uuid,'preview',true));
 if outside->>'unavailable'<>'true' or outside->'details'<>'{}'::jsonb or outside::text like '%PREVIEW-TEST%' then raise exception 'Private profile preview failed';end if;
end $$;
select jsonb_build_object('passed',2,'shared_profile',current_setting('wm.preview_result'),'private_profile','Undiscoverable profile returns unavailable with empty details') as test_results;
rollback;
