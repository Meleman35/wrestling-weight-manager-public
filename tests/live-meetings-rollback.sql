-- Run in a transaction through the administrative SQL connection; never commit.
-- Synthetic meeting records and temporary membership fixtures are rolled back.
begin;
do $$
declare o uuid; uid uuid; member_id uuid;
begin
 select organization_id,user_id into o,uid from public.organization_memberships where role='organization_admin' and private.gov_adult_candidate(organization_id,user_id) order by organization_id limit 1;
 select p.id into member_id from public.profiles p join auth.users u on u.id=p.id where p.id<>uid and not exists(select 1 from private.team_logins where user_id=p.id) and not exists(select 1 from public.organization_memberships where organization_id=o and user_id=p.id) and not exists(select 1 from private.organization_positions where organization_id=o and assigned_user_id=p.id and active) order by p.id limit 1;
 if uid is null or member_id is null then raise exception 'Missing test identity'; end if;
 insert into public.organization_memberships(organization_id,user_id,role) values(o,member_id,'assistant_coach');
 perform set_config('wm.meeting_test_org',o::text,true);perform set_config('wm.meeting_test_admin',uid::text,true);perform set_config('wm.meeting_test_member',member_id::text,true);perform set_config('request.jwt.claim.sub',uid::text,true);
end $$;
set local role authenticated;
do $$
declare o uuid=current_setting('wm.meeting_test_org')::uuid; uid uuid=auth.uid(); q jsonb; m jsonb; out jsonb; d jsonb; h jsonb; id uuid; denied boolean; passed text[]='{}';
begin
 q:=jsonb_build_object('action','meeting_create','organization_id',o,'request_id',gen_random_uuid(),'title','ROLLBACK TEST meeting','meeting_at',now(),'secretary_user_id',uid,'confirm_adult',true);
 out:=public.organization_governance(q);id:=(out->>'id')::uuid;
 if out is distinct from public.organization_governance(q) then raise exception 'Create retry differed';end if;
 passed:=array_append(passed,'Live public RPC creates one meeting across retries');
 m:=public.organization_governance(jsonb_build_object('action','meeting_detail','organization_id',o,'id',id));d:=m->'document';
 if not (m->>'can_edit')::boolean or d->'quorum'->>'board_required' is not null then raise exception 'Unexpected authorization or quorum';end if;
 perform set_config('request.jwt.claim.sub',current_setting('wm.meeting_test_member'),true);
 denied:=false;begin perform public.organization_governance(jsonb_build_object('action','meeting_detail','organization_id',o,'id',id));exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Member read draft';end if;
 passed:=array_append(passed,'Ordinary member cannot read draft through actual live access helpers');
 perform set_config('request.jwt.claim.sub',uid::text,true);
 d:=jsonb_set(d,'{minutes}','"Recorded test discussion"');
 q:=jsonb_build_object('action','meeting_save','organization_id',o,'id',id,'revision',m->'revision','request_id',gen_random_uuid(),'document',d,'confidential_notes','RESTRICTED-ROLLBACK-TEST');
 out:=public.organization_governance(q);
 if out is distinct from public.organization_governance(q) then raise exception 'Save replay changed';end if;
 denied:=false;begin perform public.organization_governance(q||jsonb_build_object('request_id',gen_random_uuid()));exception when sqlstate '40001' then denied:=true;end;
 if not denied then raise exception 'Stale revision accepted';end if;
 passed:=array_append(passed,'Actual database enforces idempotent save and revision conflicts');
 out:=public.organization_governance(jsonb_build_object('action','meeting_start','organization_id',o,'id',id,'revision',out->'revision','request_id',gen_random_uuid()));
 out:=public.organization_governance(jsonb_build_object('action','meeting_adjourn','organization_id',o,'id',id,'revision',out->'revision','request_id',gen_random_uuid()));
 perform set_config('request.jwt.claim.sub',current_setting('wm.meeting_test_member'),true);
 m:=public.organization_governance(jsonb_build_object('action','meeting_detail','organization_id',o,'id',id));
 h:=public.organization_governance(jsonb_build_object('action','meeting_history','organization_id',o,'id',id));
 if m->>'minutes_label'<>'UNAPPROVED MINUTES' or m ? 'confidential_notes' or (m::text||h::text) like '%RESTRICTED-ROLLBACK-TEST%' then raise exception 'Published projection leaked or label invalid';end if;
 passed:=array_append(passed,'Adjourned minutes available to member with restricted notes excluded');
 perform set_config('request.jwt.claim.sub',uid::text,true);
 out:=public.organization_governance(jsonb_build_object('action','meeting_approve','organization_id',o,'id',id,'revision',out->'revision','request_id',gen_random_uuid(),'confirm_approved',true,'approved_on',current_date,'reference','Rollback approval record'));
 out:=public.organization_governance(jsonb_build_object('action','meeting_save','organization_id',o,'id',id,'revision',out->'revision','request_id',gen_random_uuid(),'document',jsonb_set(d,'{minutes}','"Corrected test notes"'),'confidential_notes','RESTRICTED-ROLLBACK-TEST','correction_reason','Rollback correction'));
 h:=public.organization_governance(jsonb_build_object('action','meeting_history','organization_id',o,'id',id));
 if jsonb_array_length(h)<>3 or h->0->'snapshot'->>'minutes_label'<>'UNAPPROVED MINUTES' or h->1->'snapshot'->>'minutes_label'<>'APPROVED MINUTES' then raise exception 'Revision history invalid';end if;
 passed:=array_append(passed,'Approval and correction create immutable separately labeled versions');
 denied:=false;begin perform count(*) from private.organization_meeting_confidential;exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Private table exposed';end if;
 denied:=false;begin perform private.gov_meeting_action('{}');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Legacy function exposed';end if;
 passed:=array_append(passed,'Direct confidential table and legacy meeting API denied');
 denied:=false;begin perform public.organization_governance(jsonb_build_object('action','cast_vote','organization_id',o));exception when others then if sqlerrm not like '%not enabled%' then raise;end if;denied:=true;end;if not denied then raise exception 'Voting enabled';end if;
 passed:=array_append(passed,'Legacy voting remains disabled');
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);denied:=false;begin perform public.organization_governance(jsonb_build_object('action','meeting_detail','organization_id',o,'id',id));exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Tenant boundary failed';end if;
 perform set_config('request.jwt.claim.sub','',true);denied:=false;begin perform public.organization_governance(jsonb_build_object('action','meeting_list','organization_id',o));exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Anonymous allowed';end if;
 passed:=array_append(passed,'Unrelated and anonymous identities rejected');
 perform set_config('wm.meeting_test_result',jsonb_build_object('passed',array_length(passed,1),'checks',to_jsonb(passed))::text,true);
end $$;
reset role;
select current_setting('wm.meeting_test_result')::jsonb as test_results;
rollback;
