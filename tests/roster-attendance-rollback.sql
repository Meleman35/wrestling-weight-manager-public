create function pg_temp.check(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'CHECK FAILED: %',label;end if;end$$;
create function pg_temp.denied(sql text,pattern text) returns void language plpgsql as $$declare rejected boolean=false;begin begin execute sql;exception when others then if sqlerrm not ilike '%'||pattern||'%' then raise exception 'Wrong denial: %',sqlerrm;end if;rejected:=true;end;perform pg_temp.check(rejected,'Expected denial: '||pattern);end$$;
do $$
declare c uuid=gen_random_uuid();p uuid=gen_random_uuid();k uuid=gen_random_uuid();x uuid=gen_random_uuid();t record;a uuid;s uuid;e uuid;i int;
begin
 insert into auth.users(id,aud,role,email) values(c,'authenticated','authenticated','ra-coach@example.invalid'),(p,'authenticated','authenticated','ra-parent@example.invalid'),(k,'authenticated','authenticated','ra-kid@example.invalid'),(x,'authenticated','authenticated','ra-stranger@example.invalid');
 perform set_config('request.jwt.claim.sub',c::text,true);select * into t from public.bootstrap_wrestling_organization('RA Test Org','RA Test Team','school','girls','2026-27');
 select id into s from public.seasons where team_id=t.team_id limit 1;
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(t.organization_id,'Test','Athlete',current_date-interval '15 years') returning id into a;
 insert into public.roster_memberships(season_id,athlete_id,created_at) values(s,a,now()-interval '2 years');
 insert into public.team_memberships(team_id,user_id,role,athlete_id) values(t.team_id,k,'athlete',a),(t.team_id,p,'parent_guardian',a);
 insert into public.athlete_guardians(athlete_id,guardian_user_id,name,invitation_status) values(a,p,'Test Parent','accepted');
 for i in 1..6 loop
  insert into public.team_events(team_id,season_id,event_type,title,starts_at,ends_at,created_by,attendance_required,counts_toward_season_attendance) values(t.team_id,s,'practice','Past practice '||i,now()-i*interval '1 day',now()-i*interval '1 day'+interval '1 hour',c,true,true) returning id into e;
  if i<6 then insert into public.event_attendance(event_id,athlete_id,status,excuse_status) values(e,a,(array['present','late','absent','modified','absent'])[i],case when i=5 then 'excused' else 'none' end);end if;
 end loop;
 perform set_config('ra.c',c::text,true);perform set_config('ra.p',p::text,true);perform set_config('ra.k',k::text,true);perform set_config('ra.x',x::text,true);perform set_config('ra.a',a::text,true);perform set_config('ra.s',s::text,true);perform set_config('ra.t',t.team_id::text,true);
end $$;
set local role authenticated;
do $$
declare q jsonb=jsonb_build_object('season_id',current_setting('ra.s'),'athlete_id',current_setting('ra.a'));r jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('ra.c'),true);
 r:=public.roster_eligibility_request('list',q);perform pg_temp.check(r->0->>'eligible'='true' and r->0->>'revision'='0','default eligible');
 r:=public.roster_eligibility_request('save',q||'{"eligible":false,"revision":0}');perform pg_temp.check(r->>'eligible'='false','ineligible stored');
 perform pg_temp.check((select active from public.roster_memberships where season_id=current_setting('ra.s')::uuid and athlete_id=current_setting('ra.a')::uuid),'membership remains active');
 perform pg_temp.check((select count(*)=5 from public.event_attendance where athlete_id=current_setting('ra.a')::uuid),'history preserved');
 perform pg_temp.denied(format('select public.roster_eligibility_request(''save'',%L)',q||'{"eligible":true,"revision":0}'),'Eligibility changed');
 perform public.set_athlete_team_status(current_setting('ra.s')::uuid,current_setting('ra.a')::uuid,'standby');perform public.set_athlete_team_status(current_setting('ra.s')::uuid,current_setting('ra.a')::uuid,'active');
 perform pg_temp.check(public.roster_eligibility_request('list',q)->0->>'eligible'='false','reactivating does not clear competition eligibility');
 r:=public.attendance_summary_request('read',q);perform pg_temp.check(jsonb_array_length(r->'events')=6,'completed schedule rows include unmarked');perform pg_temp.check(r->'settings'->>'excused_counts'='false','excused excluded default');
 r:=public.attendance_summary_request('settings',q||'{"revision":0,"event_types":["practice","camp"],"excused_counts":true,"modified_counts":false}');perform pg_temp.check(r->'settings'->>'excused_counts'='true','coach config');
 perform pg_temp.denied(format('select public.attendance_summary_request(''settings'',%L)',q||'{"revision":0,"event_types":["practice"],"excused_counts":true,"modified_counts":true}'),'settings changed');
 perform set_config('request.jwt.claim.sub',current_setting('ra.p'),true);r:=public.attendance_summary_request('read',q);perform pg_temp.check(r->>'can_manage'='false' and jsonb_array_length(r->'events')=6,'guardian can see own child');
 perform pg_temp.denied(format('select public.roster_eligibility_request(''list'',%L)',q),'Coach personal');
 perform pg_temp.denied(format('select public.attendance_summary_request(''settings'',%L)',q),'Coach access');
 perform set_config('request.jwt.claim.sub',current_setting('ra.k'),true);r:=public.attendance_summary_request('read',q);perform pg_temp.check(jsonb_array_length(r->'athletes')=1,'athlete sees self');
 perform set_config('request.jwt.claim.sub',current_setting('ra.x'),true);perform pg_temp.denied(format('select public.attendance_summary_request(''read'',%L)',q),'Attendance is private');
 perform pg_temp.denied('select * from private.roster_eligibility','permission denied');perform pg_temp.denied('select * from private.attendance_preferences','permission denied');
end $$;
reset role;
select 'PASS: eligibility isolation, stale writes, roster/family/history preservation, attendance defaults, settings, guardian/self/stranger authorization' result;
