-- Source component only; deploy via the guarded generated health-notifications.sql.
-- This adds IN-APP notices, not email/SMS or alert-push delivery. No backfill.
alter table public.communication_notifications add column health_update_id uuid
 references private.health_updates(id) on delete cascade;
create unique index communication_notifications_health_recipient
 on public.communication_notifications(health_update_id,user_id) where health_update_id is not null;
alter table public.communication_notifications add constraint health_notification_shape check(
 health_update_id is null or (category='system' and thread_id is null and message_id is null
 and weigh_in_id is null and athlete_id is null and join_request_id is null and profile_request_id is null));

-- Explicit-user equivalent of the existing case/update read rules. Background
-- recipient selection must not depend on the sender's auth.uid() or session.
create function private.health_notification_visible(p_update uuid,p_user uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(select 1 from auth.users u where u.id=p_user
  and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and not exists(select 1 from private.team_logins where user_id=p_user)
 and not exists(select 1 from private.scoped_deletion_jobs j where j.personal and j.sealed_at is not null
  and j.subject_hash=encode(sha256(convert_to(p_user::text,'UTF8')),'hex'))
 and exists(
  select 1 from private.health_updates h join private.health_cases c on c.id=h.case_id
  join public.teams t on t.id=c.team_id
  cross join lateral(select
   private.health_trainer(c.team_id,p_user) or private.health_clinical_family(c.team_id,c.athlete_id,p_user) clinical,
   private.health_family(c.team_id,c.athlete_id,p_user) family,
   exists(select 1 from public.team_memberships m where m.team_id=c.team_id and m.user_id=p_user and m.active
    and (m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->'team_admin'='true'::jsonb)))
   or exists(select 1 from public.organization_memberships m where m.organization_id=t.organization_id
    and m.user_id=p_user and m.role='organization_admin') staff) access
  where h.id=p_update and private.health_team_athlete(c.team_id,c.athlete_id)
   and (access.clinical or access.family or access.staff)
   and (h.visibility='participation' or access.clinical or h.author_id=p_user)
 );
$$;
revoke all on function private.health_notification_visible(uuid,uuid) from public,anon,authenticated;

create function private.health_notification_readable(p_update uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select private.health_actor() is not null and private.health_notification_visible(p_update,auth.uid());
$$;
revoke all on function private.health_notification_readable(uuid) from public,anon,authenticated;
grant execute on function private.health_notification_readable(uuid) to authenticated;
create policy health_notification_current_access on public.communication_notifications as restrictive
 for select to authenticated using(health_update_id is null or private.health_notification_readable(health_update_id));
-- Future unrelated permissive policies must not enable client-authored notices.
create policy health_notification_no_client_insert on public.communication_notifications as restrictive
 for insert to authenticated with check(health_update_id is null);
create policy health_notification_no_client_update on public.communication_notifications as restrictive
 for update to authenticated using(health_update_id is null) with check(health_update_id is null);

create function private.enqueue_health_update_notifications() returns trigger
 language plpgsql security definer set search_path='' as $$
declare c private.health_cases%rowtype; target uuid;
begin
 select * into c from private.health_cases where id=new.case_id;
 if c.id is null then raise exception 'Care notification source is unavailable';end if;
 for target in
  select m.user_id from public.team_memberships m where m.team_id=c.team_id and m.active
  union select m.user_id from public.organization_memberships m join public.teams t on t.organization_id=m.organization_id
   where t.id=c.team_id and m.role='organization_admin'
 loop
  if target<>new.author_id and private.health_notification_visible(new.id,target) then
   insert into public.communication_notifications(team_id,user_id,category,title,body,health_update_id)
    values(c.team_id,target,'system',case when new.visibility='participation' then 'New participation update' else 'New care update' end,
     'An update is available to your account. Open it to view the concern securely.',new.id)
    on conflict(health_update_id,user_id) where health_update_id is not null do nothing;
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.enqueue_health_update_notifications() from public,anon,authenticated;
create trigger health_update_notification after insert on private.health_updates
 for each row execute function private.enqueue_health_update_notifications();

-- Notification identity is an opaque per-recipient ID. Resolve after sign-in;
-- never accept a caller's recipient identity or trust a raw case ID from a push.
create function private.health_notification_open(p_notification_id uuid) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare u uuid=private.health_actor();n public.communication_notifications%rowtype;c private.health_cases%rowtype;
begin
 if u is null then raise sqlstate '42501' using message='Sign in and unlock to view this care update';end if;
 select * into n from public.communication_notifications where id=p_notification_id and user_id=u and health_update_id is not null;
 if n.id is null or not private.health_notification_visible(n.health_update_id,u) then
  raise sqlstate '42501' using message='This care update is no longer available to this account';end if;
 select c1.* into c from private.health_cases c1 join private.health_updates h on h.case_id=c1.id
  where h.id=n.health_update_id and c1.team_id=n.team_id;
 if c.id is null then raise sqlstate '42501' using message='This care update is no longer available';end if;
 return jsonb_build_object('team_id',c.team_id,'case_id',c.id,'update_id',n.health_update_id);
end $$;
create function public.health_notification_open(p_notification_id uuid) returns jsonb
 language sql security invoker set search_path='' as $$select private.health_notification_open(p_notification_id)$$;
revoke all on function private.health_notification_open(uuid),public.health_notification_open(uuid) from public,anon,authenticated;
grant execute on function private.health_notification_open(uuid),public.health_notification_open(uuid) to authenticated;

-- Keep delivery badge counts consistent with the inbox after access is removed.
-- The ordinary get_notification_badge_count() remains SECURITY INVOKER and uses RLS.
create or replace function public.notification_badge_count_for_delivery(p_user_id uuid) returns integer
 language sql stable security definer set search_path='' as $$
 select count(*)::integer from public.communication_notifications n where n.user_id=p_user_id and n.read_at is null
 and (n.weigh_in_id is null or exists(select 1 from private.weigh_in_recipients(n.weigh_in_id) r where r.user_id=p_user_id))
 and (n.health_update_id is null or private.health_notification_visible(n.health_update_id,p_user_id));
$$;
revoke all on function public.notification_badge_count_for_delivery(uuid) from public,anon,authenticated;
grant execute on function public.notification_badge_count_for_delivery(uuid) to service_role;
