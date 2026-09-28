-- Synthetic invitation acceptance and delivery authorization; no emails are sent.
begin;
do $$
declare owner_id uuid=gen_random_uuid();child_id uuid=gen_random_uuid();parent_id uuid=gen_random_uuid();other_id uuid=gen_random_uuid();t record;a uuid;ss uuid;inv record;g record;
begin
 insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data) values
 (owner_id,'authenticated','authenticated','invite-coach@example.invalid',now(),'{"full_name":"Actual Coach"}'),
 (child_id,'authenticated','authenticated','invite-child@example.invalid',null,'{"full_name":"Actual Athlete"}'),
 (parent_id,'authenticated','authenticated','invite-parent@example.invalid',now(),'{"full_name":"Actual Parent"}'),
 (other_id,'authenticated','authenticated','invite-other@example.invalid',now(),'{}');
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 select * into t from public.bootstrap_wrestling_organization('Synthetic Invitation Organization','Synthetic Invitation Team','school','girls','2026-27');
 insert into public.athletes(organization_id,first_name,last_name,birth_date) values(t.organization_id,'Actual','Athlete',current_date-interval '15 years') returning id into a;
 select id into ss from public.seasons where team_id=t.team_id limit 1;
 insert into public.roster_memberships(season_id,athlete_id) values(ss,a);
 select * into inv from public.create_athlete_claim_invitation(a,t.team_id,'invite-child@example.invalid');
 select * into g from public.create_guardian_invitation_v2(a,t.team_id,'Actual Parent',p_email=>'invite-parent@example.invalid');
 perform set_config('test.inv_owner',owner_id::text,true);perform set_config('test.inv_child',child_id::text,true);perform set_config('test.inv_parent',parent_id::text,true);perform set_config('test.inv_other',other_id::text,true);perform set_config('test.inv_a',a::text,true);perform set_config('test.inv_token',inv.invitation_token,true);perform set_config('test.inv_guardian',g.invitation_token,true);
end $$;
set local role authenticated;
do $$
declare result jsonb;denied boolean;request_id uuid=gen_random_uuid();
begin
 result:=public.invitation_email_context(current_setting('test.inv_token'),request_id);
 if result->>'email'<>'invite-child@example.invalid' or result->>'name'<>'Actual Athlete' then raise exception 'Invitation did not resolve saved recipient and name';end if;
 denied:=false;begin perform public.invitation_email_context(current_setting('test.inv_token'),request_id);exception when others then denied:=true;end;if not denied then raise exception 'Duplicate email attempt allowed';end if;
 denied:=false;begin perform public.invitation_email_context(current_setting('test.inv_token'),gen_random_uuid());exception when others then denied:=true;end;if not denied then raise exception 'Email cooldown bypass';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.inv_other'),true);
 denied:=false;begin perform public.invitation_email_context(current_setting('test.inv_guardian'),gen_random_uuid());exception when others then denied:=true;end;if not denied then raise exception 'Unrelated account generated recipient credentials';end if;
 result:=public.accept_verified_email_invitations();if (result->>'athletes')::int<>0 or (result->>'guardians')::int<>0 then raise exception 'Wrong email gained membership';end if;
 denied:=false;begin perform public.accept_athlete_claim_invitation(current_setting('test.inv_token'));exception when others then denied:=true;end;if not denied then raise exception 'Wrong email accepted token';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.inv_child'),true);
 denied:=false;begin perform public.accept_verified_email_invitations();exception when others then denied:=true;end;if not denied then raise exception 'Unverified email accepted invitation';end if;
 if (select display_name from public.profiles where id=auth.uid())<>'Actual Athlete' then raise exception 'Signup still using email prefix';end if;
end $$;
reset role;
update auth.users set email_confirmed_at=now() where id=current_setting('test.inv_child')::uuid;
set local role authenticated;
do $$
declare result jsonb;
begin
 result:=public.accept_verified_email_invitations();if result->>'athletes'<>'1' then raise exception 'Verified athlete not linked: %',result;end if;
 result:=public.accept_verified_email_invitations();if result->>'athletes'<>'0' then raise exception 'Repeated acceptance not idempotent';end if;
 if public.accept_athlete_claim_invitation(current_setting('test.inv_token'))<>current_setting('test.inv_a')::uuid then raise exception 'Opening original invitation again failed';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.inv_parent'),true);
 result:=public.accept_verified_email_invitations();if result->>'guardians'<>'1' then raise exception 'Verified parent not linked: %',result;end if;
 if not public.is_guardian_for_athlete(current_setting('test.inv_a')::uuid) then raise exception 'Parent missing guardian access';end if;
end $$;
reset role;
do $$begin
 if has_function_privilege('anon','public.invitation_email_context(text,uuid)','execute') or has_function_privilege('anon','public.accept_verified_email_invitations()','execute') then raise exception 'Anonymous invitation endpoint exposed';end if;
end $$;
select 'PASS: bound recipient and real name, authenticated sender, duplicate prevention, verified email only, athlete and parent linking, idempotence and unrelated denial' as result;
rollback;
