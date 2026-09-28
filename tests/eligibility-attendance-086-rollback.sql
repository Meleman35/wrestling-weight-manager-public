-- Append to roster-attendance-rollback.sql within one rolled-back transaction.
set local role authenticated;
do $$
declare q jsonb=jsonb_build_object('season_id',current_setting('ra.s'),'athlete_id',current_setting('ra.a'));r jsonb;v int;d date=(now() at time zone 'America/Denver')::date;
begin
 perform set_config('request.jwt.claim.sub',current_setting('ra.c'),true);
 select (value->>'revision')::int into v from jsonb_array_elements(public.roster_eligibility_request('list',q)) where value->>'athlete_id'=current_setting('ra.a');
 q:=q||jsonb_build_object('rules_version',2,'practice_allowed',true,'timezone','America/Denver');
 r:=public.roster_eligibility_request('save',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',d-5,'restricted_through',d));v:=(r->>'revision')::int;
 perform pg_temp.check(r->>'eligible'='false' and r->>'practice_allowed'='true','inclusive end date blocks competition but allows practice');
 r:=public.roster_eligibility_request('list',q);perform pg_temp.check(r->0->>'eligible'='false' and r->0->>'rules_version'='2','list exposes effective state and date controls');
 r:=public.roster_eligibility_request('save',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',d-5,'restricted_through',d-1));v:=(r->>'revision')::int;
 perform pg_temp.check(r->>'eligible'='true' and r->>'competition_allowed'='false','expired restriction automatically eligible, configuration retained');
 r:=public.roster_eligibility_request('list',q);perform pg_temp.check(r->0->>'eligible'='true','list auto expiry');
 r:=public.roster_eligibility_request('save',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',d+1,'restricted_through',d+2));v:=(r->>'revision')::int;
 perform pg_temp.check(r->>'eligible'='true','future restriction not active today');
 perform pg_temp.denied(format('select public.roster_eligibility_request(''save'',%L)',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',d,'restricted_through',d-1)),'last restricted day');
 perform pg_temp.denied(format('select public.roster_eligibility_request(''save'',%L)',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',d,'timezone','Invalid/Zone')),'time zone');
 perform pg_temp.denied(format('select public.roster_eligibility_request(''save'',%L)',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',null)),'start date');
 r:=public.roster_eligibility_request('save',q||jsonb_build_object('eligible',false,'practice_allowed',false,'revision',v,'restricted_from',d,'restricted_through',null));v:=(r->>'revision')::int;
 perform pg_temp.check(r->>'practice_allowed'='false' and r->>'restricted_through' is null,'school can restrict both until cleared');
 perform public.set_athlete_team_status(current_setting('ra.s')::uuid,current_setting('ra.a')::uuid,'standby');
 r:=public.attendance_summary_request('read',q-'athlete_id');perform pg_temp.check(jsonb_array_length(r->'athletes')=0,'standby hidden from attendance picker');
 perform pg_temp.denied(format('select public.attendance_summary_request(''read'',%L)',q),'active wrestlers only');
 perform public.set_athlete_team_status(current_setting('ra.s')::uuid,current_setting('ra.a')::uuid,'removed');
 r:=public.attendance_summary_request('read',q-'athlete_id');perform pg_temp.check(jsonb_array_length(r->'athletes')=0,'removed hidden from attendance picker');
 perform public.set_athlete_team_status(current_setting('ra.s')::uuid,current_setting('ra.a')::uuid,'active');
 r:=public.attendance_summary_request('read',q);perform pg_temp.check(jsonb_array_length(r->'athletes')=1 and jsonb_array_length(r->'events')=6,'reactivation restores saved history; competition restriction does not hide active attendance');
 r:=public.roster_eligibility_request('save',q||jsonb_build_object('eligible',true,'practice_allowed',true,'revision',v));
 perform pg_temp.check(r->>'eligible'='true' and r->>'restricted_from' is null and r->>'restricted_through' is null,'clearing removes dates and restores eligibility');
 perform set_config('request.jwt.claim.sub',current_setting('ra.x'),true);
 perform pg_temp.denied(format('select public.roster_eligibility_request(''save'',%L)',q||jsonb_build_object('eligible',false,'revision',v,'restricted_from',d)),'Coach personal');
end $$;
reset role;
select 'PASS: dated eligibility/expiry, practice override, date validation, inactive attendance hiding/history preservation and access control' result;
