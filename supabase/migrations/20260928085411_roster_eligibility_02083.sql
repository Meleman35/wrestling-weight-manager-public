-- Competition eligibility is private, seasonal, and independent of roster membership.
create table private.roster_eligibility (
 season_id uuid not null references public.seasons(id), athlete_id uuid not null references public.athletes(id),
 eligible boolean not null default true, revision integer not null default 1,
 changed_by uuid not null references auth.users(id), changed_at timestamptz not null default now(),
 primary key(season_id,athlete_id)
);
alter table private.roster_eligibility enable row level security;
revoke all on private.roster_eligibility from public,anon,authenticated;
create function private.roster_eligibility_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid;s uuid=(p_data->>'season_id')::uuid;a uuid=(p_data->>'athlete_id')::uuid;r private.roster_eligibility%rowtype;v boolean;
begin
 select team_id into t from public.seasons where id=s;
 if auth.uid() is null or t is null or not public.is_team_staff(t) or exists(select 1 from private.team_logins where user_id=auth.uid()) then raise exception 'Coach personal account required';end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(jsonb_build_object('athlete_id',rm.athlete_id,'photo_path',a.photo_path,'eligible',coalesce(e.eligible,true),'revision',coalesce(e.revision,0))) from public.roster_memberships rm join public.athletes a on a.id=rm.athlete_id left join private.roster_eligibility e using(season_id,athlete_id) where rm.season_id=s),'[]');
 elsif p_action='save' then
  if jsonb_typeof(p_data->'eligible') is distinct from 'boolean' or a is null then raise exception 'Choose Eligible or Ineligible';end if;
  perform 1 from public.roster_memberships where season_id=s and athlete_id=a for update;
  if not found then raise exception 'Athlete is not on this season roster';end if;
  select * into r from private.roster_eligibility where season_id=s and athlete_id=a;
  if coalesce(r.revision,0) is distinct from (p_data->>'revision')::int then raise exception 'Eligibility changed. Reopen Roster before saving';end if;
  v:=(p_data->>'eligible')::boolean;
  insert into private.roster_eligibility(season_id,athlete_id,eligible,changed_by) values(s,a,v,auth.uid())
   on conflict(season_id,athlete_id) do update set eligible=excluded.eligible,revision=private.roster_eligibility.revision+1,changed_by=auth.uid(),changed_at=clock_timestamp() returning * into r;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'competition_eligibility_changed','athlete',a,jsonb_build_object('team_id',t,'season_id',s));
  return jsonb_build_object('athlete_id',a,'eligible',r.eligible,'revision',r.revision);
 end if;
 raise exception 'Unknown eligibility action';
end $$;
revoke all on function private.roster_eligibility_request(text,jsonb) from public,anon;
grant execute on function private.roster_eligibility_request(text,jsonb) to authenticated;
create function public.roster_eligibility_request(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.roster_eligibility_request(p_action,p_data)$$;
revoke all on function public.roster_eligibility_request(text,jsonb) from public,anon;
grant execute on function public.roster_eligibility_request(text,jsonb) to authenticated;
