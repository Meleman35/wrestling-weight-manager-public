-- Authorized synthetic coach; all records and auth state are rolled back.
begin;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email) values(auth.uid(),'authenticated','authenticated','weight-setup-rollback@example.invalid');
set local role authenticated;
do $test$
declare v record; v_boys record; v_result jsonb; v_weights numeric[];
begin
  if not exists(select 1 from public.state_high_school_weight_rules where state_code='WY' and season_name='2026-27' and gender_scope='girls' and active) then raise exception 'New coach cannot read verified presets'; end if;
  select * into v from public.bootstrap_wrestling_organization('Weight Setup Rollback School','Weight Setup Rollback Girls','school','girls','2026-27');
  perform public.update_team_settings_v3(v.team_id,'Weight Setup Rollback Girls','school','girls',array['high_school'],'WY','#163A67','#285E9E','#FFFFFF',null,50);
  v_result:=public.apply_state_high_school_weight_classes(v.team_id,v.season_id);
  if not coalesce((v_result->>'applied')::boolean,false) then raise exception 'State preset not applied'; end if;
  select array_agg(weight_lbs order by sort_order) into v_weights from public.team_weight_classes where team_id=v.team_id and active;
  if v_weights<>array[100,105,110,115,120,125,130,135,140,145,155,170,190,235]::numeric[] then raise exception 'Girls classes did not persist'; end if;
  if not exists(select 1 from public.teams where id=v.team_id and gender_scope='girls' and service_levels @> array['high_school'] and state_code='WY' and growth_allowance_lbs=2) then raise exception 'First team settings not retained'; end if;
  select * into v_boys from public.create_team_in_organization_v4(v.organization_id,'Weight Setup Rollback Boys','school','boys',array['high_school'],'WY',p_season_name=>'2026-27');
  perform public.apply_team_weight_class_preset_v2(v_boys.team_id,'nfhs_boys_14');
  select array_agg(weight_lbs order by sort_order) into v_weights from public.team_weight_classes where team_id=v_boys.team_id and active;
  if v_weights<>array[106,113,120,126,132,138,144,150,157,165,175,190,215,285]::numeric[] then raise exception 'Boys classes did not persist'; end if;
end;
$test$;
rollback;
