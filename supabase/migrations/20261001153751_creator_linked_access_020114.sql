-- Linked Creator access. Deploy only with the matching reviewed deletion-worker policy.
-- No account is enrolled by this migration. Billing, team roles and health access are unchanged.
begin;
lock table private.creator_accounts in access exclusive mode;
do $$begin
 if private.scoped_deletion_schema_hash()<>'c23b13b51ac8623fccd86341ae73c4a1db8c442a4a2f9698fd8761ec40993ca3'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Linked Creator access requires a fresh schema compatibility review';end if;
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('completed','cancelled'))
 then raise exception 'Finish or review existing deletion jobs before this migration';end if;
end $$;
-- BEGIN LINKED CREATOR CORE
-- One optional, operator-provisioned login. No email or JWT metadata grants access.
alter table private.creator_accounts add column linked_user_id uuid unique references auth.users(id) on delete set null;
alter table private.creator_accounts add constraint creator_accounts_distinct_logins check(linked_user_id is null or linked_user_id<>user_id);
create or replace function private.creator_access() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from private.creator_accounts c join auth.users u on u.id=auth.uid()
  join auth.users workspace_owner on workspace_owner.id=c.user_id
  join auth.sessions s on s.user_id=u.id and s.id::text=auth.jwt()->>'session_id'
  where (c.user_id=auth.uid() or c.linked_user_id=auth.uid())
   and workspace_owner.deleted_at is null and workspace_owner.email_confirmed_at is not null
   and (workspace_owner.banned_until is null or workspace_owner.banned_until<=now())
   and not exists(select 1 from private.team_logins where user_id=c.user_id)
   and not exists(select 1 from private.scoped_deletion_jobs j where j.personal and j.sealed_at is not null
    and j.subject_hash=encode(sha256(convert_to(c.user_id::text,'UTF8')),'hex'))
   and u.deleted_at is null and u.email_confirmed_at is not null
   and (u.banned_until is null or u.banned_until<=now()) and (s.not_after is null or s.not_after>now()))
 and not exists(select 1 from private.team_logins where user_id=auth.uid())
 and private.scoped_deletion_access_ok()
$$;
revoke all on function private.creator_access() from public,anon,authenticated;

create or replace function private.creator_offers_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid=auth.uid();workspace_owner uuid;linked_user uuid;capable boolean;
 d private.creator_offer_drafts%rowtype;offer uuid;
 code_value text;product_value text;discount integer;periods integer;cap integer;expiry timestamptz;
 offers jsonb;events jsonb;policy jsonb;allowed text[];r integer;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4096 then raise exception 'Invalid offer request';end if;
 select user_id,linked_user_id into workspace_owner,linked_user from private.creator_accounts
  where user_id=u or linked_user_id=u;
 capable:=coalesce(private.creator_access() and (u=workspace_owner or p_data->>'client'='creator-linked-v1'),false);
 -- Legacy clients must not route a linked personal account into the owner-only home.
 if p_action='access' then return jsonb_build_object('creator',capable,'home_mode',
  case when capable then case when u=workspace_owner then 'dedicated' else 'team' end else null end);end if;
 if not capable then raise sqlstate '42501' using message='Creator access is unavailable. Refresh the app and try again.';end if;
 -- Both logins lock the same workspace row. Revocation cannot race an offer mutation.
 select user_id,linked_user_id into workspace_owner,linked_user from private.creator_accounts
  where user_id=u or linked_user_id=u for update;
 if not found or not private.creator_access() then raise sqlstate '42501' using message='Creator access was removed';end if;
 p_data:=p_data-'client';
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
   if d.created_by=workspace_owner and d.status='draft' and d.code=code_value and d.product=product_value
    and d.discount_percent=discount and d.billing_periods=periods and d.redemption_limit=cap and d.expires_at=expiry
   then return jsonb_build_object('saved',true,'id',d.id,'revision',d.revision,'status','draft');end if;
   raise exception 'This request was already saved with different details. Refresh before trying again.';
  end if;
  if p_action='create' then
   if (select count(*) from private.creator_offer_drafts)>=200 then raise exception 'Offer draft limit reached';end if;
   insert into private.creator_offer_drafts(id,created_by,code,product,discount_percent,billing_periods,redemption_limit,expires_at)
    values(offer,workspace_owner,code_value,product_value,discount,periods,cap,expiry) returning * into d;
  else
   update private.creator_offer_drafts set code=code_value,product=product_value,discount_percent=discount,
    billing_periods=periods,redemption_limit=cap,expires_at=expiry,revision=revision+1,updated_at=now()
    where id=offer and created_by=workspace_owner and status='draft' and revision=(p_data->>'revision')::integer returning * into d;
   if not found then raise exception 'Offer changed. Refresh and review the latest draft.';end if;
  end if;
  insert into private.creator_offer_events(actor_id,offer_id,action,detail)
   values(u,d.id,p_action,to_jsonb(d)-array['created_by','created_at','updated_at']);
  return jsonb_build_object('saved',true,'id',d.id,'revision',d.revision,'status','draft');
 elsif p_action='archive' then
  update private.creator_offer_drafts set status='archived',revision=revision+1,updated_at=now()
   where id=(p_data->>'id')::uuid and created_by=workspace_owner and status='draft' and revision=(p_data->>'revision')::integer returning * into d;
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
  from private.creator_offer_drafts x where created_by=workspace_owner;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into events
  from (select e.action,e.offer_id,e.created_at,
    case when e.actor_id=u then 'This login' when e.actor_id=workspace_owner then 'Creator owner' else 'Linked personal login' end actor_label
   from private.creator_offer_events e where e.actor_id=workspace_owner or e.actor_id=linked_user
    or exists(select 1 from private.creator_offer_drafts o where o.id=e.offer_id and o.created_by=workspace_owner)
   order by e.created_at desc,e.id desc limit 20) x;
 select to_jsonb(x) into policy from private.creator_trial_policy x where singleton;
 return jsonb_build_object('creator',true,'home_mode',case when u=workspace_owner then 'dedicated' else 'team' end,'workspace_shared',linked_user is not null,'offers',offers,'events',events,'trial',policy,'billing_connected',false,'redemption_available',false);
exception when unique_violation then raise exception 'That code is already saved. Choose another code or edit the existing draft.';
end $$;
revoke all on function private.creator_offers_request(text,jsonb) from public,anon;
grant execute on function private.creator_offers_request(text,jsonb) to authenticated;
create or replace function public.creator_offers_request(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.creator_offers_request(p_action,p_data) $$;
revoke all on function public.creator_offers_request(text,jsonb) from public,anon;
grant execute on function public.creator_offers_request(text,jsonb) to authenticated;
-- END LINKED CREATOR CORE
-- Register the full reviewed catalog and keep both drift guards exact.
do $$declare snapshot jsonb; expected_hash text; source text;begin
 select jsonb_build_object(
  'tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'columns',
   (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull) order by a.attnum)
    from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) order by n.nspname,c.relname),'[]')
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and c.relname not like 'scoped_deletion_%'),
  'constraints',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',k.conname,'type',k.contype,
   'columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.conkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=c.oid and a.attnum=z.num),
   'ref_schema',rn.nspname,'ref_table',rc.relname,
   'ref_columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.confkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=rc.oid and a.attnum=z.num),
   'delete_action',k.confdeltype) order by n.nspname,c.relname,k.conname),'[]')
   from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
   left join pg_class rc on rc.oid=k.confrelid left join pg_namespace rn on rn.oid=rc.relnamespace
   where n.nspname in ('public','private') and c.relname not like 'scoped_deletion_%')
 ) into snapshot;
 expected_hash:=private.scoped_deletion_schema_hash();
 update private.scoped_deletion_config set catalog=snapshot,catalog_hash=expected_hash where id;
 -- Refresh only the reviewed old fingerprint in the existing merge router.
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if position('c23b13b51ac8623fccd86341ae73c4a1db8c442a4a2f9698fd8761ec40993ca3' in source)=0 then raise exception 'Unexpected athlete merge version; review compatibility first';end if;
 execute replace(source,'c23b13b51ac8623fccd86341ae73c4a1db8c442a4a2f9698fd8761ec40993ca3',expected_hash);
end $$;

commit;
