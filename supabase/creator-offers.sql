-- Creator promotion preparation. No payment, customer entitlement, redemption,
-- or trial activation can be performed by these RPCs.
create table private.creator_accounts (
 singleton boolean primary key default true check(singleton),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
-- Provision one confirmed personal Auth UUID privately after identity review.
-- Never provision from an email, client metadata or a signup trigger.
create table private.creator_offer_drafts (
 id uuid primary key,
 created_by uuid not null references auth.users(id) on delete cascade,
 code text not null unique check(code ~ '^[A-Z0-9]{4,32}$'),
 product text not null check(product in ('team_pro_year','team_pro_month','family_video_year','family_video_month','college_pro_year','college_pro_month')),
 discount_percent integer not null check(discount_percent between 1 and 100),
 billing_periods integer not null check(billing_periods between 1 and 12),
 redemption_limit integer not null check(redemption_limit between 1 and 25000),
 expires_at timestamptz not null,
 status text not null default 'draft' check(status in ('draft','archived')),
 revision integer not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table private.creator_trial_policy (
 singleton boolean primary key default true check(singleton),
 product text not null default 'team_pro' check(product='team_pro'),
 days integer not null default 7 check(days=7),
 requested boolean not null default true,
 status text not null default 'awaiting_billing' check(status='awaiting_billing'),
 revision integer not null default 1
);
insert into private.creator_trial_policy(singleton) values(true);
create table private.creator_offer_events (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references auth.users(id) on delete cascade,
 offer_id uuid references private.creator_offer_drafts(id) on delete cascade,
 action text not null check(action in ('create','update','archive','trial')),
 detail jsonb not null,
 created_at timestamptz not null default now()
);
create index creator_offer_events_actor on private.creator_offer_events(actor_id,created_at desc);
create index creator_offer_events_offer on private.creator_offer_events(offer_id);
create index creator_offer_drafts_owner on private.creator_offer_drafts(created_by);
do $$declare n text;begin
 foreach n in array array['creator_accounts','creator_offer_drafts','creator_trial_policy','creator_offer_events'] loop
  execute format('alter table private.%I enable row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated',n);
  execute format('create trigger scoped_deletion_freeze before insert or update or delete on private.%I for each row execute function private.scoped_deletion_freeze()',n);
 end loop;
end $$;

create function private.creator_access() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from private.creator_accounts c join auth.users u on u.id=c.user_id
  join auth.sessions s on s.user_id=u.id and s.id::text=auth.jwt()->>'session_id'
  where c.user_id=auth.uid() and u.deleted_at is null and u.email_confirmed_at is not null
   and (u.banned_until is null or u.banned_until<=now()) and (s.not_after is null or s.not_after>now()))
 and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and private.scoped_deletion_access_ok()
$$;
revoke all on function private.creator_access() from public,anon,authenticated;

create function private.creator_offers_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();d private.creator_offer_drafts%rowtype;offer uuid;
 code_value text;product_value text;discount integer;periods integer;cap integer;expiry timestamptz;
 offers jsonb;events jsonb;policy jsonb;allowed text[];r integer;
begin
 if p_action='access' then return jsonb_build_object('creator',private.creator_access());end if;
 if not private.creator_access() then raise sqlstate '42501' using message='Creator access is unavailable for this account';end if;
 -- Serialize owner mutations and revocation. No team or organization role confers access.
 perform 1 from private.creator_accounts where user_id=u for update;
 if not found then raise sqlstate '42501' using message='Creator access was removed';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4096 then raise exception 'Invalid offer request';end if;
 allowed:=case p_action
  when 'dashboard' then array[]::text[]
  when 'create' then array['id','code','product','discount_percent','billing_periods','redemption_limit','expires_at']
  when 'update' then array['id','revision','code','product','discount_percent','billing_periods','redemption_limit','expires_at']
  when 'archive' then array['id','revision']
  when 'trial' then array['requested','revision']
  else null end;
 if allowed is null then raise exception 'This action is unavailable. Billing and redemption are not connected.';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where not(k=any(allowed))) then raise exception 'Unexpected offer field';end if;
 if p_action in ('create','update') then
  offer:=(p_data->>'id')::uuid;code_value:=upper(btrim(p_data->>'code'));product_value:=p_data->>'product';
  discount:=(p_data->>'discount_percent')::integer;periods:=(p_data->>'billing_periods')::integer;
  cap:=(p_data->>'redemption_limit')::integer;expiry:=(p_data->>'expires_at')::timestamptz;
  if offer is null or code_value is null or code_value!~'^[A-Z0-9]{4,32}$' or product_value is null
   or product_value not in ('team_pro_year','team_pro_month','family_video_year','family_video_month','college_pro_year','college_pro_month')
   or discount is null or discount not between 1 and 100 or periods is null or periods not between 1 and 12
   or cap is null or cap not between 1 and 25000 or expiry is null or not isfinite(expiry)
   or expiry<=now() or expiry>now()+interval '366 days' then raise exception 'Check the code, plan, discount, limits and future expiration (within one year)';end if;
  select * into d from private.creator_offer_drafts where id=offer;
  if p_action='create' and found then
   if d.created_by=u and d.status='draft' and d.code=code_value and d.product=product_value
    and d.discount_percent=discount and d.billing_periods=periods and d.redemption_limit=cap and d.expires_at=expiry
   then return jsonb_build_object('saved',true,'id',d.id,'revision',d.revision,'status','draft');end if;
   raise exception 'This request was already saved with different details. Refresh before trying again.';
  end if;
  if p_action='create' then
   if (select count(*) from private.creator_offer_drafts)>=200 then raise exception 'Offer draft limit reached';end if;
   insert into private.creator_offer_drafts(id,created_by,code,product,discount_percent,billing_periods,redemption_limit,expires_at)
    values(offer,u,code_value,product_value,discount,periods,cap,expiry) returning * into d;
  else
   update private.creator_offer_drafts set code=code_value,product=product_value,discount_percent=discount,
    billing_periods=periods,redemption_limit=cap,expires_at=expiry,revision=revision+1,updated_at=now()
    where id=offer and created_by=u and status='draft' and revision=(p_data->>'revision')::integer returning * into d;
   if not found then raise exception 'Offer changed. Refresh and review the latest draft.';end if;
  end if;
  insert into private.creator_offer_events(actor_id,offer_id,action,detail)
   values(u,d.id,p_action,to_jsonb(d)-array['created_by','created_at','updated_at']);
  return jsonb_build_object('saved',true,'id',d.id,'revision',d.revision,'status','draft');
 elsif p_action='archive' then
  update private.creator_offer_drafts set status='archived',revision=revision+1,updated_at=now()
   where id=(p_data->>'id')::uuid and created_by=u and status='draft' and revision=(p_data->>'revision')::integer returning * into d;
  if not found then raise exception 'Offer changed. Refresh and review the latest draft.';end if;
  insert into private.creator_offer_events(actor_id,offer_id,action,detail) values(u,d.id,'archive',jsonb_build_object('revision',d.revision));
  return jsonb_build_object('archived',true);
 elsif p_action='trial' then
  if jsonb_typeof(p_data->'requested') is distinct from 'boolean' then raise exception 'Choose whether to offer a trial';end if;
  update private.creator_trial_policy set requested=(p_data->>'requested')::boolean,revision=revision+1
   where singleton and revision=(p_data->>'revision')::integer returning revision into r;
  if not found then raise exception 'Trial settings changed. Refresh and review.';end if;
  insert into private.creator_offer_events(actor_id,action,detail) values(u,'trial',jsonb_build_object('requested',p_data->'requested','days',7,'revision',r));
  return jsonb_build_object('saved',true,'status','awaiting_billing');
 end if;
 select coalesce(jsonb_agg(to_jsonb(x)-'created_by' order by x.created_at desc),'[]') into offers
  from private.creator_offer_drafts x where created_by=u;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into events
  from (select action,offer_id,created_at from private.creator_offer_events where actor_id=u order by created_at desc limit 20) x;
 select to_jsonb(x) into policy from private.creator_trial_policy x where singleton;
 return jsonb_build_object('creator',true,'offers',offers,'events',events,'trial',policy,'billing_connected',false,'redemption_available',false);
exception when unique_violation then raise exception 'That code is already saved. Choose another code or edit the existing draft.';
end $$;
revoke all on function private.creator_offers_request(text,jsonb) from public,anon;
grant execute on function private.creator_offers_request(text,jsonb) to authenticated;
create function public.creator_offers_request(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.creator_offers_request(p_action,p_data) $$;
revoke all on function public.creator_offers_request(text,jsonb) from public,anon;
grant execute on function public.creator_offers_request(text,jsonb) to authenticated;
