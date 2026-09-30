-- Production CHECK helpers; no customer rows.
CREATE OR REPLACE FUNCTION public.wm_practice_groups_valid(g jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare x jsonb;
begin
 if g is null or jsonb_typeof(g)<>'object' or octet_length(g::text)>6000 then return false;end if;
 if exists(select 1 from jsonb_object_keys(g) k where k not in('ages','level','squads')) then return false;end if;
 if g ? 'level' and (jsonb_typeof(g->'level')<>'string' or length(g->>'level')>40) then return false;end if;
 if g ? 'ages' then
  if jsonb_typeof(g->'ages')<>'array' or jsonb_array_length(g->'ages')>20 then return false;end if;
  for x in select value from jsonb_array_elements(g->'ages') loop
   if jsonb_typeof(x)<>'object' or jsonb_typeof(x->'age') is distinct from 'string' or length(trim(x->>'age')) not between 1 and 24 or jsonb_typeof(x->'level') is distinct from 'string' or length(x->>'level')>40 then return false;end if;
   if exists(select 1 from jsonb_object_keys(x) k where k not in('age','level')) then return false;end if;
  end loop;
  if (select count(*)<>count(distinct value->>'age') from jsonb_array_elements(g->'ages')) then return false;end if;
  if jsonb_array_length(g->'ages')>0 and coalesce(g->>'level','')<>'' then return false;end if;
 end if;
 if g ? 'squads' then
  if jsonb_typeof(g->'squads')<>'array' or jsonb_array_length(g->'squads')>2 then return false;end if;
  if exists(select 1 from jsonb_array_elements(g->'squads') as squad(value) where squad.value not in('"Varsity"','"JV"')) then return false;end if;
 end if;
 return true;
end $function$
;