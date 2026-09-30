-- Read-only paid statistics. No new personal records, billing, or trial grants.
-- Replace this closed adapter only when verified Team Pro entitlements are wired.
-- Do not infer payment from client input, roles, user_metadata, or recording permission.
create function private.wrestler_statistics_covered(p_team uuid) returns boolean
language sql stable set search_path='' as $$ select false $$;
revoke all on function private.wrestler_statistics_covered(uuid) from public,anon,authenticated;

create function private.wrestler_statistics_request(p_action text,p_data jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid=auth.uid();t uuid=(p_data->>'team_id')::uuid;a uuid=(p_data->>'athlete_id')::uuid;
 s uuid=(p_data->>'season_id')::uuid;st text=p_data->>'style';coach boolean;covered boolean;people jsonb;seasons jsonb;rows jsonb;ids uuid[];pid uuid;
begin
 if u is null or not exists(select 1 from auth.users where id=u and deleted_at is null and email_confirmed_at is not null and (banned_until is null or banned_until<=now()))
  or exists(select 1 from private.team_logins where user_id=u) then raise sqlstate '42501' using message='Use your personal account for wrestler statistics';end if;
 if t is null or not exists(select 1 from public.teams where id=t) then raise exception 'Choose a team';end if;
 coach:=public.is_team_staff(t) and not coalesce((p_data->>'view_as_parent')::boolean,false);
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'profile_id',x.profile_id,'name',concat_ws(' ',x.first_name,x.last_name)) order by x.last_name,x.first_name),'[]') into people
 from public.athletes x where exists(select 1 from public.roster_memberships r join public.seasons ss on ss.id=r.season_id where ss.team_id=t and r.athlete_id=x.id)
 and (coach or public.is_self_athlete(x.id) or public.is_guardian_for_athlete(x.id));
 if not coach and jsonb_array_length(people)=0 then raise sqlstate '42501' using message='Statistics are private to this wrestler, linked guardians and coaches';end if;
 covered:=private.wrestler_statistics_covered(t);
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active) order by starts_on desc nulls last),'[]') into seasons from public.seasons where team_id=t;
 if p_action='context' then return jsonb_build_object('team_id',t,'covered',covered,'can_manage',coach,'athletes',people,'seasons',seasons);end if;
 if p_action<>'read' then raise exception 'Unknown statistics action';end if;
 if not covered then raise sqlstate '42501' using message='Team Pro statistics access is not active for this team';end if;
 if a is null or not exists(select 1 from jsonb_array_elements(people) x where x->>'id'=a::text) then raise sqlstate '42501' using message='Choose an authorized wrestler';end if;
 if st is null or st not in ('folkstyle','freestyle','greco','beach') then raise exception 'Choose a wrestling style';end if;
 if s is not null and not exists(select 1 from public.seasons where id=s and team_id=t) then raise exception 'Season does not belong to this team';end if;
 select profile_id into pid from public.athletes where id=a;
 select array_agg(x.id) into ids from public.athletes x where (x.id=a or (pid is not null and x.profile_id=pid))
  and exists(select 1 from public.roster_memberships r join public.seasons ss on ss.id=r.season_id where ss.team_id=t and r.athlete_id=x.id);
 with source as (
  select 'book' source,id,team_id,season_id,challenge_id,data,revision,created_at from private.match_books where team_id=t
  union all
  select 'video',v.id,v.team_id,e.season_id,null::uuid,v.data,v.revision,v.created_at from private.video_scored_matches v join public.team_events e on e.id=v.event_id and e.team_id=v.team_id where v.team_id=t
 ), latest as (
  select distinct on(id) * from source order by id,revision desc,source
 ), selected as (
  select * from latest where (s is null or season_id=s) and challenge_id is null
   and data->>'status'='complete' and data->>'style'=st and coalesce(data->>'book_type','competition')='competition'
   and coalesce(data->>'video_test','false')='false' and coalesce(data->>'test_only','false')='false' and coalesce(data->>'demo','false')='false'
   and (data->>'red_id'=any(ids::text[]) or data->>'other_id'=any(ids::text[]))
 ), bounded as (select * from selected order by created_at desc,id limit 5001)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'source',source,'team_id',team_id,'season_id',season_id,'revision',revision,'created_at',created_at,
 'data',jsonb_build_object('style',data->>'style','status','complete','book_type','competition','winner',data->>'winner','result',data->>'result',
  'red_id',data->>'red_id','other_id',data->>'other_id','red_name',data->>'red_name','other_name',data->>'other_name','label',data->>'label','bout_number',data->>'bout_number','flowVersion',data->'flowVersion',
  'ledger',(select coalesce(jsonb_agg(jsonb_build_object('id',l->'id','action_id',l->'action_id','corner',l->'corner','points',l->'points','period',l->'period','voided',l->'voided','scoring',l->'scoring','position_after',l->'position_after','adjusts',l->'adjusts')),'[]') from jsonb_array_elements(case when jsonb_typeof(data->'ledger')='array' then data->'ledger' else '[]'::jsonb end) l)
 ))),'[]') into rows from bounded;
 if jsonb_array_length(rows)>5000 then raise exception 'Select one season to load this wrestler’s statistics';end if;
 return jsonb_build_object('team_id',t,'athlete_id',a,'athlete_ids',ids,'season_id',s,'style',st,'matches',rows);
end $$;
revoke all on function private.wrestler_statistics_request(text,jsonb) from public,anon;
grant execute on function private.wrestler_statistics_request(text,jsonb) to authenticated;
create function public.wrestler_statistics_request(p_action text,p_data jsonb default '{}') returns jsonb
language sql stable security invoker set search_path='' as $$ select private.wrestler_statistics_request(p_action,p_data) $$;
revoke all on function public.wrestler_statistics_request(text,jsonb) from public,anon;
grant execute on function public.wrestler_statistics_request(text,jsonb) to authenticated;
