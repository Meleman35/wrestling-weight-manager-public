-- Run after migration via an authorized administrative SQL connection.
-- All fixture rows, requests, history and audit events are rolled back.
begin;
select set_config('wm.structure_test_org',(select organization_id::text from private.organization_positions order by created_at limit 1),true);
select set_config('request.jwt.claim.sub',(select user_id::text from public.organization_memberships where organization_id=current_setting('wm.structure_test_org')::uuid and role='organization_admin' order by user_id limit 1),true);
set local role authenticated;
do $$
declare o uuid:=current_setting('wm.structure_test_org')::uuid; uid uuid:=auth.uid(); q jsonb; p jsonb; a jsonb; c jsonb; history jsonb;
 passed text[]:='{}'; denied boolean; result jsonb;
begin
 if uid is null then raise exception 'No administrator test context'; end if;
 c:=public.organization_governance(jsonb_build_object('action','context','organization_id',o));
 if not (c->>'can_manage_structure')::boolean or jsonb_array_length(c->'positions')<19 or jsonb_array_length(c->'affiliates')<55 then raise exception 'Live context preservation failed'; end if;
 passed:=array_append(passed,'Authenticated public API loads existing organization structure');
 q:=jsonb_build_object('action','save_position','organization_id',o,'request_id',gen_random_uuid(),'title','ROLLBACK TEST position');
 p:=public.organization_governance(q);
 if p is distinct from public.organization_governance(q) then raise exception 'Replay changed result'; end if;
 passed:=array_append(passed,'Same request replay returns the same position and revision');
 denied:=false;
 begin perform public.organization_governance(q||jsonb_build_object('title','ROLLBACK TEST different')); exception when others then
  if sqlerrm not like '%different content%' then raise; end if;denied:=true;end;
 if not denied then raise exception 'Changed replay accepted';end if;
 passed:=array_append(passed,'Changed-payload replay blocked');
 q:=jsonb_build_object('action','save_position','organization_id',o,'request_id',gen_random_uuid(),'title','ROLLBACK TEST assigned','id',p->>'id','revision',1,'user_id',uid,'confirm_adult',true);
 p:=public.organization_governance(q);
 if (p->>'revision')::int<>2 then raise exception 'Update revision failed';end if;
 passed:=array_append(passed,'Administrator-confirmed adult assignment saved');
 denied:=false;
 begin perform public.organization_governance(q||jsonb_build_object('request_id',gen_random_uuid())); exception when sqlstate '40001' then denied:=true;end;
 if not denied then raise exception 'Stale revision accepted';end if;
 passed:=array_append(passed,'Stale concurrent-edit revision rejected');
 denied:=false;
 begin perform public.organization_governance((q-'revision')||jsonb_build_object('request_id',gen_random_uuid())); exception when sqlstate '40001' then denied:=true;end;
 if not denied then raise exception 'Missing revision accepted';end if;
 passed:=array_append(passed,'Missing revision rejected');
 denied:=false;
 begin perform public.organization_governance(q||jsonb_build_object('request_id',gen_random_uuid(),'revision',2,'access_role','president')); exception when others then
  if sqlerrm not like '%confirm the selected access%' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Unconfirmed access accepted';end if;
 passed:=array_append(passed,'Operational access requires separate confirmation');
 a:=public.organization_governance(jsonb_build_object('action','save_affiliate','organization_id',o,'request_id',gen_random_uuid(),'title','ROLLBACK TEST affiliate'));
 a:=public.organization_governance(jsonb_build_object('action','archive_affiliate','organization_id',o,'request_id',gen_random_uuid(),'id',a->>'id','revision',1));
 a:=public.organization_governance(jsonb_build_object('action','restore_affiliate','organization_id',o,'request_id',gen_random_uuid(),'id',a->>'id','revision',2));
 history:=public.organization_governance(jsonb_build_object('action','history','organization_id',o,'entity_kind','affiliate','id',a->>'id'));
 if jsonb_array_length(history)<>3 or history->0->'snapshot'->>'membership_review'<>'unreviewed' then raise exception 'Affiliate history failed';end if;
 passed:=array_append(passed,'Archive/reactivate retains immutable revisions and resets review');
 denied:=false;
 begin perform count(*) from private.organization_positions;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Raw private table readable';end if;
 passed:=array_append(passed,'Direct private table access denied');
 denied:=false;
 begin perform private.gov_structure_action('{}'::jsonb);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Legacy unsafe structure function callable';end if;
 passed:=array_append(passed,'Legacy direct-write function inaccessible');
 denied:=false;
 begin perform public.organization_governance(jsonb_build_object('action','cast_vote','organization_id',o));exception when others then
  if sqlerrm not like '%not enabled%' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Voting unexpectedly enabled';end if;
 passed:=array_append(passed,'Incomplete voting API blocked');
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 denied:=false;
 begin perform public.organization_governance(jsonb_build_object('action','context','organization_id',o));exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Unrelated identity can read tenant';end if;
 passed:=array_append(passed,'Unrelated identity cannot read organization');
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;
 begin perform public.organization_governance(jsonb_build_object('action','context','organization_id',o));exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Missing identity accepted';end if;
 passed:=array_append(passed,'Missing authenticated identity rejected');
 perform set_config('wm.structure_test_result',jsonb_build_object('passed',cardinality(passed),'tests',to_jsonb(passed),'fixture_changes','rolled back')::text,true);
end $$;
reset role;
select current_setting('wm.structure_test_result')::jsonb as result;
rollback;
