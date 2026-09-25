-- Deliberately disabled. Exact team/user grants are provisioned only for an approved pilot.
begin;
create table private.video_pilot_control (
 id boolean primary key default true check (id),
 enabled boolean not null default false
);
insert into private.video_pilot_control(id,enabled) values(true,false);
create table private.video_pilot_grants (
 team_id uuid not null references public.teams(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 expires_at timestamptz not null,
 revoked_at timestamptz,
 primary key(team_id,user_id)
);
alter table private.video_pilot_control enable row level security;
alter table private.video_pilot_grants enable row level security;
revoke all on private.video_pilot_control, private.video_pilot_grants from public,anon,authenticated;
create function private.video_pilot_context(p_team_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); expiry timestamptz; people jsonb;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then
  raise exception 'Personal coach account required';
 end if;
 if not coalesce(public.is_team_staff(p_team_id),false) then return jsonb_build_object('allowed',false); end if;
 select g.expires_at into expiry from private.video_pilot_grants g
 where g.team_id=p_team_id and g.user_id=uid and g.revoked_at is null and g.expires_at>now()
 and exists(select 1 from private.video_pilot_control where id and enabled);
 if expiry is null then return jsonb_build_object('allowed',false); end if;
 select coalesce(jsonb_agg(distinct a.id),'[]') into people from public.athletes a
 join public.roster_memberships r on r.athlete_id=a.id and r.active
 join public.seasons s on s.id=r.season_id and s.team_id=p_team_id and s.active;
 return jsonb_build_object('allowed',true,'user_id',uid,'team_id',p_team_id,
  'lease_seconds',greatest(0,least(7200,extract(epoch from expiry-now())::int)),
  'athlete_ids',people,'cloud_upload',false,'live',false,'billing',false);
end;
$$;
revoke all on function private.video_pilot_context(uuid) from public,anon,authenticated;
-- Exposed invoker wrapper delegates to a narrow, authenticated private projection.
create function public.video_pilot_context(p_team_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.video_pilot_context(p_team_id)$$;
revoke all on function public.video_pilot_context(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.video_pilot_context(uuid),public.video_pilot_context(uuid) to authenticated;
commit;
