-- Read-only capture of deployed resource functions, 2026-09-25; no user records.
CREATE OR REPLACE FUNCTION private.wm_team_access(t uuid, w boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(select 1 from private.team_logins where user_id=auth.uid()) and (public.is_team_admin(t) or exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=auth.uid() and m.active and m.role<>'kiosk' and (not w or m.role in ('head_coach','assistant_coach') or (m.role='manager' and m.permissions->>'equipment'='true'))));
$function$;

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
  return jsonb_build_object('write',private.wm_team_access(tid,true),'rows',coalesce((select jsonb_agg(to_jsonb(x) order by title) from private.wm_equipment x where team_id=tid),'[]'));
 end if;
 if not private.wm_team_access(tid,true) then raise exception 'Team staff required';end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.wm_resources_request(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.wm_resources(p_action,p_data)$function$;

