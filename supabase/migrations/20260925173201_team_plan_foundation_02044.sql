-- Launch foundation. The pilot remains free; no checkout, provider secrets or charges.
begin;
-- Refuse to overwrite a resource implementation changed since this draft was prepared.
do $$ begin
 if (select md5(prosrc) from pg_catalog.pg_proc where oid='private.wm_resources(text,jsonb)'::regprocedure)
  is distinct from 'a199b4bdb56d44614911c15f25125874' then
  raise exception 'Resource implementation changed; rebase and review the equipment guard before deploying';
 end if;
end $$;
create table private.team_plan_settings (
 singleton boolean primary key default true check(singleton),
 pilot_enabled boolean not null default true
);
insert into private.team_plan_settings values(true,true);

create table private.team_subscriptions (
 team_id uuid primary key references public.teams(id) on delete restrict,
 provider text not null check(provider in ('apple','stripe','manual')),
 subscription_ref text not null check(length(subscription_ref) between 1 and 240),
 status text not null check(status in ('active','canceled','past_due','expired','revoked')),
 period_start timestamptz not null,
 period_end timestamptz not null check(period_end>period_start),
 revision integer not null check(revision>0),
 updated_at timestamptz not null default now(),
 unique(provider,subscription_ref)
);
create table private.team_subscription_events (
 provider text not null,
 event_id text not null check(length(event_id) between 1 and 240),
 team_id uuid not null references public.teams(id) on delete restrict,
 payload jsonb not null,
 accepted_revision integer,
 created_at timestamptz not null default now(),
 primary key(provider,event_id)
);
create index team_subscription_events_team_idx on private.team_subscription_events(team_id,created_at);
alter table private.team_plan_settings enable row level security;
alter table private.team_subscriptions enable row level security;
alter table private.team_subscription_events enable row level security;
revoke all on private.team_plan_settings,private.team_subscriptions,private.team_subscription_events from public,anon,authenticated,service_role;

-- Only trusted backend SQL may apply an already verified, authoritative billing state.
-- This is NOT a webhook and does not verify a receipt. No client or service-role RPC
-- grant is provided. Future adapters must verify signatures, product and environment.
create function private.apply_team_subscription_event(
 p_provider text,p_event_id text,p_team_id uuid,p_subscription_ref text,
 p_expected_revision integer,p_status text,p_period_start timestamptz,p_period_end timestamptz
) returns integer language plpgsql set search_path='' as $$
declare request jsonb; previous private.team_subscription_events%rowtype;
 current_plan private.team_subscriptions%rowtype; next_revision integer;
begin
 if p_provider is null or p_provider not in ('apple','stripe','manual')
 or p_event_id is null or length(trim(p_event_id)) not between 1 and 240
 or p_subscription_ref is null or length(trim(p_subscription_ref)) not between 1 and 240
 or p_team_id is null or p_expected_revision is null or p_expected_revision<0
 or p_status is null or p_status not in ('active','canceled','past_due','expired','revoked')
 or p_period_start is null or p_period_end is null or not isfinite(p_period_start) or not isfinite(p_period_end)
 or p_period_end<=p_period_start then raise exception 'Invalid verified subscription event';end if;
 request:=jsonb_build_object('team_id',p_team_id,'subscription_ref',p_subscription_ref,'expected_revision',p_expected_revision,
 'status',p_status,'period_start',extract(epoch from p_period_start),'period_end',extract(epoch from p_period_end));
 insert into private.team_subscription_events(provider,event_id,team_id,payload)
 values(p_provider,p_event_id,p_team_id,request) on conflict(provider,event_id) do nothing;
 if not found then
  select * into previous from private.team_subscription_events where provider=p_provider and event_id=p_event_id;
  if previous.payload is distinct from request then raise exception 'Event ID was already used with different subscription data';end if;
  return previous.accepted_revision;
 end if;
 -- Lock the team even for its first subscription. Concurrent first grants cannot race.
 perform 1 from public.teams where id=p_team_id for update;
 if not found then raise exception 'Team does not exist';end if;
 select * into current_plan from private.team_subscriptions where team_id=p_team_id for update;
 if coalesce(current_plan.revision,0)<>p_expected_revision then raise exception 'Subscription changed; reload verified provider state before retrying';end if;
 if current_plan.team_id is not null and (current_plan.provider<>p_provider or current_plan.subscription_ref<>p_subscription_ref) then
  raise exception 'Changing a team subscription requires a reviewed replacement';
 end if;
 if exists(select 1 from private.team_subscriptions where provider=p_provider and subscription_ref=p_subscription_ref and team_id<>p_team_id) then
  raise exception 'Subscription already belongs to another team';
 end if;
 next_revision:=p_expected_revision+1;
 insert into private.team_subscriptions(team_id,provider,subscription_ref,status,period_start,period_end,revision)
 values(p_team_id,p_provider,p_subscription_ref,p_status,p_period_start,p_period_end,next_revision)
 on conflict(team_id) do update set status=excluded.status,period_start=excluded.period_start,period_end=excluded.period_end,revision=excluded.revision,updated_at=now();
 update private.team_subscription_events set accepted_revision=next_revision where provider=p_provider and event_id=p_event_id;
 return next_revision;
end $$;
revoke all on function private.apply_team_subscription_event(text,text,uuid,text,integer,text,timestamptz,timestamptz) from public,anon,authenticated,service_role;

-- No user ID, price, paid flag, browser storage, or device environment is accepted.
create function private.team_plan_context(t uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare uid uuid=auth.uid(); sub private.team_subscriptions%rowtype;
 pilot boolean; paid boolean; state text; team_name text; admin boolean;
begin
 if uid is null or exists(select 1 from private.team_logins where user_id=uid) then raise exception 'Personal account required';end if;
 select name into team_name from public.teams where id=t;
 if not found then raise exception 'Active team access required';end if;
 admin:=public.is_team_admin(t);
 if not (admin or exists(
  select 1 from public.team_memberships m where m.team_id=t and m.user_id=uid and m.active and (
   m.role in ('head_coach','assistant_coach','manager') or (
    m.role in ('athlete','parent_guardian') and exists(select 1 from public.roster_memberships r join public.seasons s on s.id=r.season_id
     where r.athlete_id=m.athlete_id and r.active and s.active and s.team_id=t)
    and (m.role='athlete' or exists(select 1 from public.athlete_guardians g where g.athlete_id=m.athlete_id and g.guardian_user_id=uid))
   )
  )
 )) then raise exception 'Active team access required';end if;
 select * into sub from private.team_subscriptions where team_id=t;
 select pilot_enabled into pilot from private.team_plan_settings where singleton;
 paid:=coalesce(sub.status in ('active','canceled') and sub.period_start<=now() and sub.period_end>now(),false);
 state:=case when sub.team_id is null then 'none' when sub.status='revoked' then 'revoked'
  when sub.period_end<=now() then 'expired' when sub.period_start>now() then 'scheduled' else sub.status end;
 return jsonb_build_object('team_id',t,'team_name',team_name,'plan',case when paid then 'full_year' else 'free' end,
  'access_source',case when paid then 'subscription' when coalesce(pilot,false) then 'pilot' else 'free' end,
  'full_access',paid or coalesce(pilot,false),'pilot_enabled',coalesce(pilot,false),
  'subscription_status',state,'paid_through',case when admin then sub.period_end else null end,
  'can_manage_plan',admin,'purchases_available',false,'server_time',now());
end $$;
revoke all on function private.team_plan_context(uuid) from public,anon,authenticated;
grant execute on function private.team_plan_context(uuid) to authenticated;
create function public.team_plan_request(p_team_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select private.team_plan_context(p_team_id);
$$;
revoke all on function public.team_plan_request(uuid) from public,anon,authenticated;
grant execute on function public.team_plan_request(uuid) to authenticated;

-- This release integrates Equipment. Other paid components must be wired before launch.
create function private.team_feature_allowed(t uuid,feature text) returns boolean
language plpgsql stable set search_path='' as $$
declare ctx jsonb;
begin
 if feature not in ('core','equipment_management') or feature is null then raise exception 'Unknown team feature';end if;
 ctx:=private.team_plan_context(t);
 return feature='core' or (ctx->>'full_access')::boolean;
end $$;
revoke all on function private.team_feature_allowed(uuid,text) from public,anon,authenticated,service_role;

-- EQUIPMENT_PLAN_GUARD follows; media and original role checks are preserved.
CREATE OR REPLACE FUNCTION private.wm_resources(a text, d jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare pid uuid=nullif(d->>'profile','')::uuid; tid uuid=nullif(d->>'team','')::uuid; mid uuid=nullif(d->>'id','')::uuid; m private.wm_media%rowtype; item private.wm_equipment%rowtype; canwrite boolean; result jsonb;
begin
 if auth.uid() is null or exists(select 1 from private.team_logins where user_id=auth.uid()) then raise exception 'Personal account required'; end if;
 if a in ('media_list','media_reserve') then
  if (pid is null)=(tid is null) then raise exception 'Choose a profile or team';end if;
  canwrite:=case when pid is not null then private.wrestling_profile_manager(pid) else private.wm_team_access(tid,true) end;
  if not canwrite and not(case when pid is not null then private.wrestling_profile_visible(pid) else private.wm_team_access(tid,false) end) then raise exception 'Access denied';end if;
  if a='media_list' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into result from (select * from private.wm_media where profile_id=pid or team_id=tid) x where x.ready and (canwrite and coalesce(d->>'preview','false')<>'true' or x.team_id is not null or x.shared);
   return jsonb_build_object('write',canwrite and coalesce(d->>'preview','false')<>'true','rows',result);
  end if;
  if not canwrite then raise exception 'Profile owner, linked guardian or team staff required';end if;
  if d->>'mime' not in ('image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm','application/pdf') or d->>'mime' is null or (pid is not null and d->>'mime'='application/pdf') then raise exception 'Unsupported file type';end if;
  if (select count(*) from private.wm_media where profile_id=pid or team_id=tid)>=100 then raise exception 'Limit 100 uploads; remove old entries first';end if;
  insert into private.wm_media(profile_id,team_id,path,mime,caption) values(pid,tid,coalesce(pid,tid)::text||'/'||gen_random_uuid()::text,d->>'mime',left(coalesce(d->>'caption',''),500)) returning * into m;
  return to_jsonb(m);
 end if;
 if a in ('media_publish','media_visibility','media_remove') then
  select * into m from private.wm_media where id=mid for update;
  if not found or not private.wm_media_access(m.path,true) then raise exception 'Access denied';end if;
  if a='media_remove' then delete from private.wm_media where id=mid;return '{"ok":true}';end if;
  if not exists(select 1 from storage.objects where bucket_id='wm-media' and name=m.path and metadata->>'mimetype'=m.mime) then raise exception 'Upload not complete';end if;
  update private.wm_media set ready=true,shared=coalesce((d->>'shared')::boolean,false) where id=mid;
  return '{"ok":true}';
 end if;
 if not private.wm_team_access(tid,false) then raise exception 'Team access required';end if;
 if a='equipment_list' then
  return jsonb_build_object('write',private.wm_team_access(tid,true) and private.team_feature_allowed(tid,'equipment_management'),'plan_required',not private.team_feature_allowed(tid,'equipment_management'),'rows',coalesce((select jsonb_agg(to_jsonb(x) order by title) from private.wm_equipment x where team_id=tid),'[]'));
 end if;
 if not private.wm_team_access(tid,true) then raise exception 'Team staff required';end if;
 if not private.team_feature_allowed(tid,'equipment_management') then raise exception 'Full Year is required to manage equipment for this team. Existing inventory stays available to view.';end if;
 if a='equipment_add' then
  if length(trim(coalesce(d->>'title',''))) not between 1 and 120 then raise exception 'Enter item name';end if;
  insert into private.wm_equipment(team_id,title,quantity,notes) values(tid,trim(d->>'title'),(d->>'quantity')::integer,left(coalesce(d->>'notes',''),500));
 elsif a in ('equipment_out','equipment_in','equipment_remove') then
  select * into item from private.wm_equipment where id=mid and team_id=tid for update;
  if not found or item.revision is distinct from (d->>'revision')::integer then raise exception 'Inventory changed. Refresh and try again';end if;
  if a='equipment_remove' then
   if item.checked_out>0 then raise exception 'Return issued items before removing';end if;
   delete from private.wm_equipment where id=mid;
  else update private.wm_equipment set checked_out=checked_out+case when a='equipment_out' then 1 else -1 end,revision=revision+1 where id=mid;end if;
 else raise exception 'Unknown action';end if;
 return '{"ok":true}';
end $function$
;
commit;
