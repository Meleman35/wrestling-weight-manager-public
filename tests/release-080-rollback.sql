-- Synthetic accounts, teams, follows, posts and messages only; all changes roll back.
begin;
create function pg_temp.check(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'CHECK FAILED: %',label;end if;end$$;
create function pg_temp.denied(sql text,pattern text) returns void language plpgsql as $$declare rejected boolean=false;begin begin execute sql;exception when others then if sqlerrm not ilike '%'||pattern||'%' then raise exception 'Wrong denial: %',sqlerrm;end if;rejected:=true;end;perform pg_temp.check(rejected,'Expected denial: '||pattern);end$$;
do $$
declare ca uuid=gen_random_uuid();cb uuid=gen_random_uuid();pa uuid=gen_random_uuid();pb uuid=gen_random_uuid();ka uuid=gen_random_uuid();kb uuid=gen_random_uuid();stranger uuid=gen_random_uuid();ta record;tb record;a uuid;b uuid;ss uuid;wa uuid;wb uuid;wca uuid;wcb uuid;
begin
 insert into auth.users(id,aud,role,email) values(ca,'authenticated','authenticated','social-coach-a@example.invalid'),(cb,'authenticated','authenticated','social-coach-b@example.invalid'),(pa,'authenticated','authenticated','social-parent-a@example.invalid'),(pb,'authenticated','authenticated','social-parent-b@example.invalid'),(ka,'authenticated','authenticated','social-kid-a@example.invalid'),(kb,'authenticated','authenticated','social-kid-b@example.invalid'),(stranger,'authenticated','authenticated','social-stranger@example.invalid');
 perform set_config('request.jwt.claim.sub',ca::text,true);select * into ta from public.bootstrap_wrestling_organization('Social A Org','Social Team A','school','girls','2026-27');perform public.wrestling_profiles_request('mine');select id into wca from private.wrestling_profiles where user_id=ca;
 perform set_config('request.jwt.claim.sub',cb::text,true);select * into tb from public.bootstrap_wrestling_organization('Social B Org','Social Team B','school','girls','2026-27');perform public.wrestling_profiles_request('mine');select id into wcb from private.wrestling_profiles where user_id=cb;
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(ta.organization_id,'Social','Child A',current_date-interval '15 years') returning id into a;
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(tb.organization_id,'Social','Child B',current_date-interval '16 years') returning id into b;
 select id into ss from public.seasons where team_id=ta.team_id and active limit 1;insert into public.roster_memberships(season_id,athlete_id) values(ss,a);
 select id into ss from public.seasons where team_id=tb.team_id and active limit 1;insert into public.roster_memberships(season_id,athlete_id) values(ss,b);
 insert into public.team_memberships(team_id,user_id,role,athlete_id) values(ta.team_id,pa,'parent_guardian',a),(tb.team_id,pb,'parent_guardian',b),(ta.team_id,ka,'athlete',a),(tb.team_id,kb,'athlete',b);
 insert into public.athlete_guardians(athlete_id,guardian_user_id,name,invitation_status) values(a,pa,'Social Parent A','accepted'),(b,pb,'Social Parent B','accepted');
 insert into public.athlete_chat_permissions(team_id,athlete_id,peer_to_peer,coach_to_athlete,media_view,media_send_group) values(ta.team_id,a,true,true,true,true),(tb.team_id,b,true,true,true,true) on conflict(team_id,athlete_id) do update set peer_to_peer=true,coach_to_athlete=true,media_view=true,media_send_group=true;
 perform set_config('request.jwt.claim.sub',pa::text,true);perform public.wrestling_profiles_request('mine');select id into wa from private.wrestling_profiles where athlete_profile_id=(select profile_id from public.athletes where id=a);
 perform set_config('request.jwt.claim.sub',pb::text,true);perform public.wrestling_profiles_request('mine');select id into wb from private.wrestling_profiles where athlete_profile_id=(select profile_id from public.athletes where id=b);
 update private.wrestling_profiles set discoverable=true,sharing='{"follow":true,"outgoing_follow":true}' where id in(wa,wb,wca,wcb);
 insert into private.wrestling_follows(source_id,target_id,status) values(wa,wb,'approved'),(wca,wcb,'approved'),(wca,wa,'approved'),(wcb,wa,'approved');
 perform set_config('test.ca',ca::text,true);perform set_config('test.cb',cb::text,true);perform set_config('test.pa',pa::text,true);perform set_config('test.pb',pb::text,true);perform set_config('test.ka',ka::text,true);perform set_config('test.kb',kb::text,true);perform set_config('test.stranger',stranger::text,true);perform set_config('test.ta',ta.team_id::text,true);perform set_config('test.tb',tb.team_id::text,true);perform set_config('test.a',a::text,true);perform set_config('test.b',b::text,true);perform set_config('test.wa',wa::text,true);perform set_config('test.wb',wb::text,true);perform set_config('test.wca',wca::text,true);perform set_config('test.wcb',wcb::text,true);
end$$;

-- Adult individual follow: independent of membership; explicit audiences only.
set local role authenticated;
do $$
declare w uuid;q jsonb;r jsonb;post jsonb;shared jsonb;t uuid=current_setting('test.ta')::uuid;f jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 r:=public.profile_team_request('mine');w:=(r->0->>'id')::uuid;perform pg_temp.check(w is not null,'standalone adult profile');perform set_config('test.individual',w::text,true);
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);q:=jsonb_build_object('team_id',t);
 perform public.team_board_request('profile_save',q||'{"bio":"Shared team","revision":1,"discoverable":true}');
 post:=public.team_board_request('create',q||jsonb_build_object('client_id',gen_random_uuid(),'body','Team followers only','audience','followers'));perform public.team_board_request('submit',q||jsonb_build_object('id',post->>'id','revision',1));
 shared:=public.team_board_request('create',q||jsonb_build_object('client_id',gen_random_uuid(),'body','All followers','audience','all_followers'));perform public.team_board_request('submit',q||jsonb_build_object('id',shared->>'id','revision',1));
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);q:=jsonb_build_object('profile_id',w,'target',t);
 perform public.profile_team_request('follow',q);perform pg_temp.check(public.profile_team_request('feed',q)='[]','pending individual cannot read');
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 perform public.team_board_request('review_individual',jsonb_build_object('team_id',t,'profile_id',w,'revision',1,'decision','approved'));
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);r:=public.profile_team_request('feed',q);perform pg_temp.check(jsonb_array_length(r)=1 and r->0->>'id'=shared->>'id','individual sees only explicit all followers audience');
 perform pg_temp.denied(format('select public.profile_team_request(''follow'',%L)',jsonb_build_object('profile_id',current_setting('test.wca'),'target',t)),'parent must allow');
 perform pg_temp.denied('select * from private.profile_team_follows','permission denied');
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);perform public.team_board_request('block_individual',jsonb_build_object('team_id',t,'profile_id',w,'revision',2));
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);perform public.profile_team_request('unfollow',q);perform pg_temp.denied(format('select public.profile_team_request(''follow'',%L)',q),'unavailable');
 -- Minor follow uses existing parental permissions and current linked parents.
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);q:=jsonb_build_object('profile_id',current_setting('test.wa'),'target',t);perform pg_temp.denied(format('select public.profile_team_request(''follow'',%L)',q),'parent must allow');
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);perform public.team_board_request('save_parent',jsonb_build_object('team_id',t,'athlete_id',current_setting('test.a'),'revision',0,'values','{"can_view":true,"can_post":true,"review_posts":true,"share_followers":true,"share_individuals":false}'::jsonb));
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);perform public.profile_team_request('follow',q);
 perform pg_temp.denied(format('select public.team_board_request(''create'',%L)',jsonb_build_object('team_id',t,'client_id',gen_random_uuid(),'body','Need additional parent choice','audience','all_followers')),'Parent permission');
end $$;
-- Profile details are preserved until approval and then use the same automatic setting.
reset role;
do $$begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 insert into public.athlete_profile_details(athlete_id,shirt_size,grade_level) values(current_setting('test.a')::uuid,'Youth S','8') on conflict(athlete_id) do update set shirt_size='Youth S',grade_level='8';
end $$;
set local role authenticated;
do $$
declare a uuid=current_setting('test.a')::uuid;t uuid=current_setting('test.ta')::uuid;w uuid=current_setting('test.wa')::uuid;r jsonb;ctx jsonb;req jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);
 r:=public.update_athlete_profile_v2(a,t,'{"shirt_size":"Youth M","grade_level":"9"}');perform pg_temp.check(r->'profile_approval'->>'status'='pending','team details wait');
 perform pg_temp.check(r->>'shirt_size'='Youth S','seeded shirt remains visible');
 perform pg_temp.denied(format('update public.athlete_profile_details set shirt_size=''Adult L'' where athlete_id=%L',a),'parent approval');
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);perform public.wm_profile_approval_request('approve',jsonb_build_object('id',r->'profile_approval'->>'id'));
 perform pg_temp.check(public.get_athlete_profile_for_team(a,t)->>'shirt_size'='Youth M','parent publishes team details');
 perform public.wm_profile_approval_request('set_settings',jsonb_build_object('profile_id',w,'auto_approve',true,'review_photos',true));
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);r:=public.update_athlete_profile_v2(a,t,'{"shirt_size":"Youth L"}');perform pg_temp.check(r->'profile_approval'->>'status'='approved' and r->>'shirt_size'='Youth L','automatic team details');
 perform pg_temp.denied(format('select public.update_athlete_profile_v2(%L,%L,''{"email":"changed@example.invalid"}'')',a,t),'My Profile');
 ctx:=public.wm_profile_approval_request('context',jsonb_build_object('kind','social','id',w));
 req:=public.wm_profile_approval_request('prepare',jsonb_build_object('kind','social','id',w,'proposal',jsonb_build_object('name',ctx->'expected'->>'name','details',ctx->'expected'->'details','sharing',ctx->'expected'->'sharing','discoverable',false)));perform public.wm_profile_approval_request('save_draft',jsonb_build_object('id',req->>'id'));
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);perform public.update_athlete_profile_v2(a,t,'{"shirt_size":"Adult M"}');
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);ctx:=public.wm_profile_approval_request('context',jsonb_build_object('kind','social','id',w));perform pg_temp.check(ctx->>'draft_stale'='true','new coach seed makes older draft stale');
end $$;
-- Repeat dates, DST, monthly missing dates, retries and unauthorized access.
do $$
declare t uuid=current_setting('test.ta')::uuid;s uuid;q jsonb;r jsonb;d jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);select id into s from public.seasons where team_id=t limit 1;
 q:=jsonb_build_object('team_id',t,'season_id',s,'client_id',gen_random_uuid(),'frequency','weekly','timezone','America/Denver','start_local','2026-10-26T18:00','end_local','2026-10-26T19:30','until','2026-11-11','weekdays','[1,3]'::jsonb,'event','{"event_type":"open_mat","title":"Open Mats","location_name":"LIS wrestling room","counts_toward_season_attendance":false}'::jsonb);
 r:=public.create_repeating_events(q);perform pg_temp.check((r->>'count')::int=6,'Monday Wednesday six events');perform pg_temp.check(public.create_repeating_events(q)=r,'retry returns same batch');perform set_config('test.repeat_batch',r->>'id',true);
 perform pg_temp.check((select count(*)=6 and bool_and((starts_at at time zone 'America/Denver')::time='18:00') and bool_and((ends_at at time zone 'America/Denver')::time='19:30') and bool_and(extract(isodow from starts_at at time zone 'America/Denver') in (1,3)) from public.team_events where repeat_batch_id=(r->>'id')::uuid),'local time persists across DST');
 d:=q||jsonb_build_object('client_id',gen_random_uuid(),'frequency','monthly','start_local','2027-01-31T18:00','end_local','2027-01-31T19:30','until','2027-04-30');r:=public.create_repeating_events(d);perform pg_temp.check(r->>'count'='2','monthly skips months without same date');
 d:=q||jsonb_build_object('client_id',gen_random_uuid(),'frequency','daily','until','2026-10-28');r:=public.create_repeating_events(d);perform pg_temp.check(r->>'count'='3','daily inclusive');
 perform pg_temp.denied(format('select public.create_repeating_events(%L)',q||jsonb_build_object('client_id',gen_random_uuid(),'end_local','2026-10-26T17:00')),'End must be after');
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);perform pg_temp.denied(format('select public.create_repeating_events(%L)',q),'coach');
end $$;
reset role;
do $$
declare e public.team_events%rowtype;r jsonb;v jsonb;n int;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 select * into e from public.team_events where repeat_batch_id=current_setting('test.repeat_batch')::uuid order by starts_at limit 1;
 update public.team_events set starts_at=now()-interval '7 days',ends_at=now()-interval '7 days'+interval '90 minutes' where id=e.id returning * into e;
 insert into public.event_attendance(event_id,athlete_id,status) values(e.id,current_setting('test.a')::uuid,'present');
 v:=to_jsonb(e)||jsonb_build_object('title','Corrected past open mats','location_name','LIS room correction');
 r:=public.edit_team_event(e.id,e.updated_at,v);
 perform pg_temp.check(r->>'id'=e.id::text and r->>'title'='Corrected past open mats','past event edited in place');
 perform pg_temp.check(exists(select 1 from public.event_attendance where event_id=e.id and status='present'),'attendance preserved');
 perform pg_temp.denied(format('select public.edit_team_event(%L,%L,%L)',e.id,e.updated_at,v),'event changed');
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 perform pg_temp.denied(format('select public.edit_team_event(%L,%L,%L)',e.id,r->>'updated_at',v),'Coach access');
end $$;
select 'PASS: individual follows, explicit audiences, minor parent choices, blocks, team-profile review/auto-approval, stale drafts, weekly/daily/monthly events, DST, idempotent retries and past-event edits preserving attendance' result;
rollback;
