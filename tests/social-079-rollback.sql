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
set local role authenticated;
do $$
declare c jsonb;r jsonb;cid text;mid uuid=gen_random_uuid();q jsonb;rev int;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 q:=jsonb_build_object('profile_id',current_setting('test.wca'),'target',current_setting('test.wcb'));
 c:=public.profile_connections_request('request',q);cid:=c->>'id';perform pg_temp.check(c->>'status'='pending','new chat pending');
 perform pg_temp.denied(format('select public.profile_connections_request(''send'',%L)',jsonb_build_object('id',cid,'body','Before acceptance','client_id',mid)),'Waiting for the recipient');
 perform pg_temp.denied(format('select public.profile_connections_request(''accept'',%L)',jsonb_build_object('id',cid,'revision',1)),'Only the recipient');
 perform set_config('request.jwt.claim.sub',current_setting('test.cb'),true);
 c:=public.profile_connections_request('accept',jsonb_build_object('id',cid,'revision',1));perform pg_temp.check((c->>'can_send')::boolean,'adult cross-team chat accepted');
 r:=public.profile_connections_request('send',jsonb_build_object('id',cid,'body','Synthetic message','client_id',mid));perform pg_temp.check(r=public.profile_connections_request('send',jsonb_build_object('id',cid,'body','Synthetic message','client_id',mid)),'retry idempotence');
 r:=public.profile_connections_request('read',jsonb_build_object('id',cid));perform pg_temp.check(jsonb_array_length(r->'messages')=1,'single retry message');
 c:=public.profile_connections_request('preferences',jsonb_build_object('id',cid,'revision',c->>'revision','allowed',false));
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 c:=public.profile_connections_request('pair',q)->'chat';c:=public.profile_connections_request('preferences',jsonb_build_object('id',cid,'revision',c->>'revision','allowed',true));perform pg_temp.check(not(c->>'can_send')::boolean,'one person cannot override other stop');
 perform pg_temp.denied(format('select public.profile_connections_request(''preferences'',%L)',jsonb_build_object('id',cid,'revision',1,'allowed',true)),'preferences changed');
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 perform pg_temp.denied(format('select public.profile_connections_request(''read'',%L)',jsonb_build_object('id',cid)),'Conversation access');
 perform set_config('request.jwt.claim.sub',current_setting('test.cb'),true);
 perform pg_temp.check(not(public.profile_connections_request('pair',jsonb_build_object('profile_id',current_setting('test.wcb'),'target',current_setting('test.wa')))->>'can_request')::boolean,'unrelated adult cannot request minor');
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);
 c:=public.profile_connections_request('request',jsonb_build_object('profile_id',current_setting('test.wa'),'target',current_setting('test.wb')));cid:=c->>'id';perform set_config('test.kchat',cid,true);
 perform set_config('request.jwt.claim.sub',current_setting('test.kb'),true);c:=public.profile_connections_request('accept',jsonb_build_object('id',cid,'revision',1));perform pg_temp.check(not(c->>'can_send')::boolean,'minor needs parents after recipient acceptance');
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);c:=public.profile_connections_request('read',jsonb_build_object('id',cid))->'chat';perform pg_temp.check((c->>'guardian_mirror')::boolean,'guardian mirror');c:=public.profile_connections_request('guardian',jsonb_build_object('id',cid,'revision',c->>'revision','profile_id',current_setting('test.wa'),'allowed',true));
 perform pg_temp.denied(format('select public.profile_connections_request(''send'',%L)',jsonb_build_object('id',cid,'body','No guardian send','client_id',gen_random_uuid())),'read-only');
 perform set_config('request.jwt.claim.sub',current_setting('test.pb'),true);c:=public.profile_connections_request('read',jsonb_build_object('id',cid))->'chat';c:=public.profile_connections_request('guardian',jsonb_build_object('id',cid,'revision',c->>'revision','profile_id',current_setting('test.wb'),'allowed',true));
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);c:=public.profile_connections_request('read',jsonb_build_object('id',cid))->'chat';perform pg_temp.check((c->>'can_send')::boolean,'both parents allow peers across teams');perform public.profile_connections_request('send',jsonb_build_object('id',cid,'body','Synthetic peer chat','client_id',gen_random_uuid()));
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);c:=public.profile_connections_request('guardian',jsonb_build_object('id',cid,'revision',c->>'revision','profile_id',current_setting('test.wa'),'allowed',false));
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);c:=public.profile_connections_request('read',jsonb_build_object('id',cid))->'chat';perform pg_temp.check(not(c->>'can_send')::boolean,'parent revoke immediately gates send');
 perform pg_temp.denied('select * from private.profile_chat_messages','permission denied');
end$$;
-- Team profiles, explicit audience and moderation.
do $$
declare ta text=current_setting('test.ta');tb text=current_setting('test.tb');q jsonb;r jsonb;post jsonb;shared jsonb;parent_post jsonb;pref jsonb;rows jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 q:=jsonb_build_object('team_id',ta);r:=public.team_board_request('context',q);perform pg_temp.check(r->>'discoverable'='false','team profile private default');
 perform public.team_board_request('profile_save',q||'{"bio":"Synthetic Team A","revision":1,"discoverable":true}');
 post:=public.team_board_request('create',q||jsonb_build_object('client_id',gen_random_uuid(),'body','Private team note'));post:=public.team_board_request('submit',q||jsonb_build_object('id',post->>'id','revision',post->>'revision'));perform set_config('test.privatepost',post->>'id',true);
 shared:=public.team_board_request('create',q||jsonb_build_object('client_id',gen_random_uuid(),'body','Shared team note','audience','followers'));shared:=public.team_board_request('submit',q||jsonb_build_object('id',shared->>'id','revision',shared->>'revision'));perform set_config('test.sharedpost',shared->>'id',true);
 perform set_config('request.jwt.claim.sub',current_setting('test.cb'),true);q:=jsonb_build_object('team_id',tb);
 perform public.team_board_request('profile_save',q||'{"bio":"Synthetic Team B","revision":1,"discoverable":true}');
 perform public.team_board_request('follow',q||jsonb_build_object('target',ta));perform pg_temp.check(public.team_board_request('feed',q||jsonb_build_object('target',ta))='[]','pending team follow cannot read posts');
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);perform public.team_board_request('review_follow',jsonb_build_object('team_id',ta,'target',tb,'decision','approved'));
 perform set_config('request.jwt.claim.sub',current_setting('test.cb'),true);rows:=public.team_board_request('feed',q||jsonb_build_object('target',ta));perform pg_temp.check(jsonb_array_length(rows)=1 and rows->0->>'id'=shared->>'id','approved follower sees only explicitly shared post');perform pg_temp.check(rows->0->>'author_name'='Team bulletin','follower author identity minimized');
 perform public.team_board_request('report',q||jsonb_build_object('target',ta,'id',shared->>'id','reason','Synthetic report for coach review'));
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);perform pg_temp.denied(format('select public.team_board_request(''feed'',%L)',q),'team membership');
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);q:=jsonb_build_object('team_id',ta);perform pg_temp.denied(format('select public.team_board_request(''context'',%L)',q),'parent needs to enable');
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);q:=q||jsonb_build_object('athlete_id',current_setting('test.a'));pref:=public.team_board_request('parent',q);perform pg_temp.check(pref->>'revision'='0','read preferences does not write restriction');pref:=public.team_board_request('save_parent',q||jsonb_build_object('revision',0,'values','{"can_view":true,"can_post":true,"review_posts":true,"share_followers":false}'::jsonb));
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);q:=jsonb_build_object('team_id',ta);
 perform pg_temp.denied(format('select public.team_board_request(''create'',%L)',q||jsonb_build_object('client_id',gen_random_uuid(),'body','Unapproved outside sharing','audience','followers')),'Parent permission');
 parent_post:=public.team_board_request('create',q||jsonb_build_object('client_id',gen_random_uuid(),'body','Athlete note'));parent_post:=public.team_board_request('submit',q||jsonb_build_object('id',parent_post->>'id','revision',parent_post->>'revision'));perform pg_temp.check(parent_post->>'status'='pending','athlete waits for review');
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);parent_post:=public.team_board_request('approve',q||jsonb_build_object('id',parent_post->>'id','revision',parent_post->>'revision'));perform pg_temp.check(parent_post->>'status'='pending','coach cannot bypass parent review');
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);parent_post:=public.team_board_request('approve',q||jsonb_build_object('id',parent_post->>'id','revision',parent_post->>'revision'));perform pg_temp.check(parent_post->>'status'='published','parent plus coach publishes athlete post');
 perform pg_temp.denied(format('select public.team_board_request(''pin'',%L)',q||jsonb_build_object('id',parent_post->>'id','revision',parent_post->>'revision','pinned',true)),'Coaches can pin');
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);parent_post:=public.team_board_request('pin',q||jsonb_build_object('id',parent_post->>'id','revision',parent_post->>'revision','pinned',true));perform pg_temp.check(parent_post->>'pinned'='true','coach pins');
 perform public.team_board_request('block_follow',q||jsonb_build_object('target',tb));
 perform set_config('request.jwt.claim.sub',current_setting('test.cb'),true);perform pg_temp.check(public.team_board_request('feed',jsonb_build_object('team_id',tb,'target',ta))='[]','blocking revokes follower posts');
 perform pg_temp.denied('select * from private.bulletin_posts','permission denied');
end$$;
reset role;
-- Storage policy checks use synthetic metadata rows and roll back with the fixture.
do $$
declare id uuid=gen_random_uuid();path text;
begin
 path:=current_setting('test.ta')||'/'||current_setting('test.ca')||'/'||id::text||'.jpg';
 insert into private.bulletin_posts(id,team_id,author_id,client_id,body,kind,color,audience,status,photo_path,coach_approved) values(id,current_setting('test.ta')::uuid,current_setting('test.ca')::uuid,gen_random_uuid(),'Synthetic private image','photo','white','team','published',path,current_setting('test.ca')::uuid);
 insert into storage.objects(bucket_id,name,owner_id,metadata) values('team-bulletins',path,current_setting('test.ca'),'{"mimetype":"image/jpeg","size":10}');
 perform set_config('test.photo',path,true);
end$$;
set local role authenticated;
do $$
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ca'),true);
 perform pg_temp.check((select count(*)=1 from storage.objects where bucket_id='team-bulletins' and name=current_setting('test.photo')),'coach reads authorized private photo');
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);
 perform pg_temp.check((select count(*)=1 from storage.objects where bucket_id='team-bulletins' and name=current_setting('test.photo')),'parent-enabled athlete reads photo');
 perform set_config('request.jwt.claim.sub',current_setting('test.cb'),true);
 perform pg_temp.check((select count(*)=0 from storage.objects where bucket_id='team-bulletins' and name=current_setting('test.photo')),'other team cannot sign private photo');
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 perform pg_temp.check((select count(*)=0 from storage.objects where bucket_id='team-bulletins' and name=current_setting('test.photo')),'stranger cannot read private photo');
end$$;
reset role;
update public.athlete_chat_permissions set media_view=false where team_id=current_setting('test.ta')::uuid and athlete_id=current_setting('test.a')::uuid;
update public.team_memberships set active=false where team_id=current_setting('test.ta')::uuid and user_id=current_setting('test.pa')::uuid and role='parent_guardian';
set local role authenticated;
do $$
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.ka'),true);
 perform pg_temp.check((select count(*)=0 from storage.objects where bucket_id='team-bulletins' and name=current_setting('test.photo')),'revoked media/guardian access prevents photo reads');
 perform set_config('request.jwt.claim.sub',current_setting('test.pa'),true);
 perform pg_temp.denied(format('select public.profile_connections_request(''read'',%L)',jsonb_build_object('id',current_setting('test.kchat'))),'Conversation access');
 perform pg_temp.denied(format('select public.team_board_request(''parent'',%L)',jsonb_build_object('team_id',current_setting('test.ta'),'athlete_id',current_setting('test.a'))),'team membership');
end$$;
reset role;
select 'PASS: cross-team chat, recipient consent, persistent stops, guardian mirrors/approval/revoke, idempotence, isolation, team follows, default privacy, explicit audiences, moderation, parent preferences, pin/report/block' result;
rollback;
