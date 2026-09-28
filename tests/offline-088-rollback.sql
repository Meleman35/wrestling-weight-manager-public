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
declare t uuid=current_setting('ra.t')::uuid;s uuid=current_setting('ra.s')::uuid;a uuid=current_setting('ra.a')::uuid;
 c jsonb;req jsonb;r jsonb;r2 jsonb;e public.team_events%rowtype;att public.event_attendance%rowtype;th uuid;mid uuid;n int;
begin
 c:=jsonb_build_object('team_id',t,'season_id',s);
 perform pg_temp.check(public.offline_coach_request('manifest',c)->>'user_id'=current_setting('ra.c'),'scoped manifest');
 perform pg_temp.check(jsonb_array_length(public.offline_coach_request('roster',c))=1,'roster snapshot');
 perform pg_temp.check(jsonb_array_length(public.offline_coach_request('events',c))=6,'events snapshot');
 perform pg_temp.check(jsonb_array_length(public.offline_coach_request('attendance',c))=5,'attendance snapshot');
 select * into e from public.team_events where team_id=t and title='Past practice 6';
 req:=c||jsonb_build_object('kind','attendance','operation_id',gen_random_uuid(),'event_id',e.id,'athlete_id',a,'status','present','expected',null);
 r:=public.offline_coach_request('apply',req);perform pg_temp.check(r->>'status'='applied','new attendance applied: '||r::text);
 r2:=public.offline_coach_request('apply',req);perform pg_temp.check(r=r2,'lost-response replay returns same attendance result');
 perform pg_temp.denied(format('select public.offline_coach_request(''apply'',%L)',req||'{"status":"absent"}'),'reused');
 r2:=public.offline_coach_request('apply',req||jsonb_build_object('operation_id',gen_random_uuid(),'status','late'));
 perform pg_temp.check(r2->>'status'='conflict' and r2->'value'->>'status'='present','concurrent attendance requires review');
 perform public.set_athlete_team_status(s,a,'standby');
 r2:=public.offline_coach_request('apply',req||jsonb_build_object('operation_id',gen_random_uuid(),'expected',r->'value'->>'updated_at'));
 perform pg_temp.check(r2->>'status'='blocked' and r2->>'message' ilike '%active wrestlers%','standby replay blocked');
 perform public.set_athlete_team_status(s,a,'active');
 req:=c||jsonb_build_object('kind','event','operation_id',gen_random_uuid(),'event_id',e.id,'expected',e.updated_at,'values',to_jsonb(e)||'{"title":"Offline event edit"}');
 r:=public.offline_coach_request('apply',req);perform pg_temp.check(r->>'status'='applied','event edit applied: '||r::text);
 r2:=public.offline_coach_request('apply',req);perform pg_temp.check(r=r2,'event replay same result');
 r2:=public.offline_coach_request('apply',req||jsonb_build_object('operation_id',gen_random_uuid()));perform pg_temp.check(r2->>'status'='conflict','stale event edit conflicts');
 select thread_id into th from public.get_communication_inbox_v4(t,s) where can_post limit 1;
 perform pg_temp.check(th is not null,'test conversation created');
 req:=c||jsonb_build_object('kind','message','operation_id',gen_random_uuid(),'thread_id',th,'body','Practice starts at five.');
 r:=public.offline_coach_request('apply',req);perform pg_temp.check(r->>'status'='applied','message applied: '||r::text);mid:=(r->>'value')::uuid;
 select count(*) into n from public.communication_message_receipts where message_id=mid;
 r2:=public.offline_coach_request('apply',req);perform pg_temp.check(r=r2,'lost-response message replay same ID');
 perform pg_temp.check((select count(*)=1 from public.communication_messages where thread_id=th and body='Practice starts at five.'),'one message after retry');
 perform pg_temp.check((select count(*)=n from public.communication_message_receipts where message_id=mid),'no duplicated receipts');
 perform pg_temp.check(jsonb_array_length(public.offline_coach_request('messages',c||jsonb_build_object('thread_id',th)))=1,'recent messages scoped read');
 perform pg_temp.denied('select * from private.offline_operations','permission denied');
 perform set_config('request.jwt.claim.sub',current_setting('ra.x'),true);
 perform pg_temp.denied(format('select public.offline_coach_request(''manifest'',%L)',c),'Current coach access');
 perform pg_temp.denied(format('select public.offline_coach_request(''apply'',%L)',req),'Current coach access');
 perform set_config('request.jwt.claim.sub',current_setting('ra.p'),true);
 perform pg_temp.denied(format('select public.offline_coach_request(''roster'',%L)',c),'Current coach access');
 perform set_config('request.jwt.claim.sub',current_setting('ra.c'),true);
 perform set_config('offline.req',req::text,true);
end $$;
reset role;
-- Remove both team and organization authorization before retrying the accepted operation.
update public.team_memberships set active=false where user_id=current_setting('ra.c')::uuid and team_id=current_setting('ra.t')::uuid;
delete from public.organization_memberships where user_id=current_setting('ra.c')::uuid;
set local role authenticated;
select pg_temp.denied(format('select public.offline_coach_request(''apply'',%L)',current_setting('offline.req')::jsonb),'Current coach access');
reset role;
select 'PASS: snapshot scope, attendance active-only, event and attendance conflicts, idempotent messages, no duplicate receipts, account isolation, revoked coach blocked, private ledger denied' result;
