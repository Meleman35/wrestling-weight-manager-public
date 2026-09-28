CREATE OR REPLACE FUNCTION private.wrestling_photo_access(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare pid uuid;
begin
 if auth.uid() is null or exists(select 1 from private.team_logins where user_id=auth.uid()) then return false;end if;
 begin pid:=split_part(p_name,'/',1)::uuid;exception when others then return false;end;
 if private.wrestling_profile_manager(pid) then return true;end if;
 if p_write then return false;end if;
 return private.wrestling_profile_visible(pid) and exists(select 1 from private.wrestling_profiles where id=pid and photo_path=p_name and (sharing->>'photo'='true' or private.wrestling_profile_self(pid)));
end $function$
;
CREATE OR REPLACE FUNCTION private.wrestling_profile_card(p_id uuid, p_preview boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p private.wrestling_profiles%rowtype; d jsonb='{}'; k text; own boolean;
begin
 if not private.wrestling_profile_visible(p_id) then return null;end if;
 select * into p from private.wrestling_profiles where id=p_id;
 own:=(private.wrestling_profile_manager(p_id) or private.wrestling_profile_self(p_id)) and not p_preview;
 foreach k in array array['roles','bio','age_division','affiliation','mat_rank','pairing_rank','results','music_title','music_url'] loop
  if own or p.sharing->>k='true' then d:=d||jsonb_build_object(k,p.details->k);end if;
 end loop;
 return jsonb_build_object('id',p.id,'name',p.name,'athlete',p.athlete_profile_id is not null,
  'manager',private.wrestling_profile_manager(p_id),'self',private.wrestling_profile_self(p_id),
  'details',d,'discoverable',p.discoverable,'sharing',case when own then p.sharing else '{}'::jsonb end,
  'assigned_roles',case when own or p.sharing->>'roles'='true' then private.wrestling_role_badges(p.user_id,own or coalesce(p.sharing->>'affiliation'='true',false)) else '[]'::jsonb end,
  'spouse',private.wrestling_spouse_card(p_id,p_preview),
  'photo_path',case when own or p.sharing->>'photo'='true' then p.photo_path end,
  'photo_source',private.wrestling_profile_photo_source(p_id,p_preview));
end $function$
;
CREATE OR REPLACE FUNCTION private.wrestling_profile_photo_source(p_id uuid, p_preview boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p private.wrestling_profiles%rowtype; own boolean; visible boolean;
begin
 if auth.uid() is null or exists(select 1 from private.team_logins where user_id=auth.uid()) then return null;end if;
 select * into p from private.wrestling_profiles where id=p_id;
 own:=(private.wrestling_profile_manager(p_id) or private.wrestling_profile_self(p_id)) and not p_preview;
 visible:=private.wrestling_profile_visible(p_id);
 if not visible and not p_preview then
  visible:=not exists(select 1 from private.wrestling_follows f where f.status='blocked' and ((f.target_id=p_id and private.wrestling_profile_self(f.source_id)) or (f.source_id=p_id and private.wrestling_profile_self(f.target_id)))) and exists(select 1 from private.profile_family_access f where f.profile_id=p_id and f.recipient=auth.uid() and f.status='accepted' and f.share_profile and private.profile_manager_for(f.profile_id,f.created_by));
 end if;
 if not visible or not (own or coalesce(p.sharing->>'photo'='true',false)) then return null;end if;
 return private.wm_identity_photo_source(p_id);
end $function$
;
