-- Synthetic family only; every fixture and side effect rolls back.
begin;
do $$
declare p uuid=gen_random_uuid(); kid uuid=gen_random_uuid(); stranger uuid=gen_random_uuid(); t record; t2 record; a uuid; b uuid; adult uuid; ss uuid; wp uuid;
begin
 insert into auth.users(id,aud,role,email) values(p,'authenticated','authenticated','hub-parent@example.invalid'),(kid,'authenticated','authenticated','hub-child@example.invalid'),(stranger,'authenticated','authenticated','hub-other@example.invalid');
 perform set_config('request.jwt.claim.sub',p::text,true);
 select * into t from public.bootstrap_wrestling_organization('Hub Test Org','Hub Team A','school','girls','2026-27');
 select * into t2 from public.bootstrap_wrestling_organization('Hub Other Org','Hub Team B','school','girls','2026-27');
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(t.organization_id,'Hub','Child',current_date-interval '15 years') returning id into a;
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(t.organization_id,'Other','Child',current_date-interval '14 years') returning id into b;
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(t.organization_id,'Adult','Athlete',current_date-interval '20 years') returning id into adult;
 select id into ss from public.seasons where team_id=t.team_id and active limit 1;
 insert into public.roster_memberships(season_id,athlete_id) values(ss,a),(ss,b),(ss,adult);
 select id into ss from public.seasons where team_id=t2.team_id and active limit 1;
 insert into public.roster_memberships(season_id,athlete_id) values(ss,a);
 insert into public.team_memberships(team_id,user_id,role,athlete_id) values(t.team_id,p,'parent_guardian',a),(t.team_id,p,'parent_guardian',b),(t.team_id,p,'parent_guardian',adult),(t.team_id,kid,'athlete',a),(t2.team_id,p,'parent_guardian',a);
 insert into public.athlete_guardians(athlete_id,guardian_user_id,name,invitation_status) values(a,p,'Hub Parent','accepted'),(b,p,'Hub Parent','accepted'),(adult,p,'Hub Parent','accepted');
 insert into public.athlete_private_contact(athlete_id,email,phone) values(a,'keep@example.invalid','3075550100') on conflict(athlete_id) do update set email=excluded.email,phone=excluded.phone;
 insert into public.athlete_medical_private(athlete_id,conditions,notes) values(a,array['Test condition'],'Keep private note') on conflict(athlete_id) do update set conditions=excluded.conditions,notes=excluded.notes;
 perform public.wrestling_profiles_request('mine');
 select id into wp from private.wrestling_profiles where athlete_profile_id=(select profile_id from public.athletes where id=a);
 update private.wrestling_profiles set details='{"bio":"Keep biography","music_url":"https://music.apple.com/test"}',sharing='{"bio":true,"photo":false}' where id=wp;
 perform set_config('test.hub_parent',p::text,true);perform set_config('test.hub_child',kid::text,true);perform set_config('test.hub_other',stranger::text,true);
 perform set_config('test.hub_a',a::text,true);perform set_config('test.hub_b',b::text,true);perform set_config('test.hub_adult',adult::text,true);perform set_config('test.hub_team',t.team_id::text,true);perform set_config('test.hub_team2',t2.team_id::text,true);
end $$;
set local role authenticated;
do $$
declare q jsonb=jsonb_build_object('team_id',current_setting('test.hub_team'),'athlete_id',current_setting('test.hub_a')); r jsonb; before_r jsonb; v jsonb; denied boolean; other jsonb;
begin
 r:=public.parent_controls_request('context',q);
 if jsonb_array_length(r->'teams')<>2 or jsonb_array_length(r->'children')<>3 or r->'profile'->>'auto_approve'<>'false' then raise exception 'Hub context/defaults incorrect';end if;
 before_r:=r;
 r:=public.parent_controls_request('save_profile',q||jsonb_build_object('expected',r->'profile','values',jsonb_build_object('auto_approve',true,'review_photos',true,'discoverable',false,'sharing','{"photo":true}'::jsonb)));
 if r->'profile'->'sharing'->>'bio'<>'true' or r->'profile'->'sharing'->>'photo'<>'true' then raise exception 'Profile sharing merge lost existing fields';end if;
 if public.wrestling_profiles_request('view',jsonb_build_object('id',r->>'profile_id'))->'details'->>'bio'<>'Keep biography' then raise exception 'Profile content lost';end if;
 denied:=false;begin perform public.parent_controls_request('save_profile',q||jsonb_build_object('expected',before_r->'profile','values',r->'profile'));exception when others then denied:=true;end;if not denied then raise exception 'Stale profile update accepted';end if;
 v:=r->'privacy'||'{"share_email_with_coaches":true,"disclose_medical_to_coaches":true,"sms_opt_in":true}';
 r:=public.parent_controls_request('save_privacy',q||jsonb_build_object('expected',r->'privacy','values',v));
 if r->'privacy'->>'share_email_with_coaches'<>'true' then raise exception 'Privacy not saved';end if;
 r:=public.parent_controls_request('save_chat',q||jsonb_build_object('expected',r->'chat','values',r->'chat'||'{"team_chat":true,"media_view":true,"media_send_group":false,"media_send_direct":false}'));
 if r->'chat'->>'media_view'<>'true' or r->'chat'->>'media_send_group'<>'false' then raise exception 'Media view/send conflated';end if;
 other:=public.parent_controls_request('context',q||jsonb_build_object('athlete_id',current_setting('test.hub_b')));
 if other->'chat'->>'team_chat'<>'false' or other->'profile'->>'auto_approve'<>'false' then raise exception 'Changes leaked to sibling';end if;
 v:=r->'notifications'||'{"guardian_alerts_only":true,"push_messages":false,"quiet_start":"21:30","quiet_end":"07:15","time_zone":"America/Denver"}';
 r:=public.parent_controls_request('save_notifications',q||jsonb_build_object('expected',r->'notifications','values',v));
 if r->'notifications'->>'guardian_alerts_only'<>'true' or r->'notifications'->>'quiet_start'<>'21:30:00' then raise exception 'Notification preferences not saved';end if;
 other:=public.parent_controls_request('context',q||jsonb_build_object('team_id',current_setting('test.hub_team2')));
 if other->'notifications'->>'guardian_alerts_only'<>'false' or other->'chat'->>'team_chat'<>'false' then raise exception 'Team settings leaked';end if;
 before_r:=r;
 denied:=false;begin perform public.parent_controls_request('save_notifications',q||jsonb_build_object('expected',r->'notifications','values',(v-'push_weigh_ins')||'{"push_messages":true}'));exception when others then denied:=true;end;
 if not denied or public.parent_controls_request('context',q)->'notifications' is distinct from before_r->'notifications' then raise exception 'Invalid notification save partially committed';end if;
 r:=public.parent_controls_request('save_tournament',q||jsonb_build_object('expected',r->'tournament','values','{"level":"mat_only"}'::jsonb));
 if r->'tournament'->>'level'<>'mat_only' then raise exception 'Tournament visibility failed';end if;
 r:=public.parent_controls_request('save_goals',q||jsonb_build_object('expected',r->'goals','values','{"enabled":true}'::jsonb));
 r:=public.parent_controls_request('save_goals',q||jsonb_build_object('expected',r->'goals','values','{"enabled":false}'::jsonb));
 if r->'goals'->>'enabled'<>'false' then raise exception 'Cannot revoke sharing while team goals disabled';end if;
 if r->'video'->>'available'<>'false' then raise exception 'Unreleased video shown as available';end if;
 other:=public.parent_controls_request('context',q||jsonb_build_object('athlete_id',current_setting('test.hub_adult')));
 if other->'profile'<>'null'::jsonb or other->'privacy'<>'null'::jsonb or other->'chat'<>'null'::jsonb then raise exception 'Adult protections editable by parent';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.hub_child'),true);
 denied:=false;begin perform public.parent_controls_request('save_profile',q||jsonb_build_object('expected',r->'profile','values',r->'profile'));exception when others then denied:=true;end;if not denied then raise exception 'Athlete changed parent controls';end if;
 if public.parent_controls_request('context','{}')->'teams'<>'[]'::jsonb then raise exception 'Child can list parent controls';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.hub_other'),true);
 denied:=false;begin perform public.parent_controls_request('context',q);exception when others then denied:=true;end;if not denied then raise exception 'Unrelated account read controls';end if;
end $$;
reset role;
do $$
begin
 if not exists(select 1 from public.athlete_private_contact where athlete_id=current_setting('test.hub_a')::uuid and email='keep@example.invalid' and phone='3075550100') then raise exception 'Contact details overwritten';end if;
 if not exists(select 1 from public.athlete_medical_private where athlete_id=current_setting('test.hub_a')::uuid and notes='Keep private note' and conditions=array['Test condition']) then raise exception 'Medical details overwritten';end if;
 update public.team_memberships set active=false where team_id=current_setting('test.hub_team')::uuid and user_id=current_setting('test.hub_parent')::uuid and role='parent_guardian';
end $$;
set local role authenticated;
do $$
declare denied boolean=false;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.hub_parent'),true);
 begin perform public.parent_controls_request('context',jsonb_build_object('team_id',current_setting('test.hub_team')));exception when others then denied:=true;end;
 if not denied then raise exception 'Revoked parent link retained access';end if;
end $$;
reset role;
select 'PASS: scope, preservation, stale saves, atomic notifications, child/stranger/adult/revoked-link denial, tournament/goals/video gates' result;
rollback;
