create or replace function private.guard_team_profile_edit() returns trigger language plpgsql security definer set search_path='' as $$
declare aid uuid;pid uuid;v jsonb;prior jsonb;current_row jsonb;col text;changed boolean=false;
begin
 if auth.uid() is null then return new;end if;
 if tg_table_name='athletes' then aid:=new.id;else aid:=new.athlete_id;end if;
 if not public.is_self_athlete(aid) or public.is_guardian_for_athlete(aid) then return new;end if;
 if exists(select 1 from public.athletes a left join public.athlete_private_identity i on i.athlete_id=a.id where a.id=aid and coalesce(i.birth_date,a.birth_date)<=current_date-interval '18 years') then return new;end if;
 select w.id into pid from public.athletes a join private.wrestling_profiles w on w.athlete_profile_id=a.profile_id where a.id=aid;
 if exists(select 1 from private.profile_publish_context where transaction_id=txid_current() and profile_id=pid and actor_id=auth.uid()) then return new;end if;
 if tg_table_name='athletes' then changed:=new.graduation_year is distinct from old.graduation_year;
 else
  v:=to_jsonb(new)-array['athlete_id','updated_at','updated_by','id','created_at'];
  if tg_op='UPDATE' then prior:=to_jsonb(old)-array['athlete_id','updated_at','updated_by','id','created_at'];
  else
   if tg_table_name='athlete_profile_details' then select to_jsonb(d) into current_row from public.athlete_profile_details d where athlete_id=aid;
   else select to_jsonb(d) into current_row from public.athlete_medical_private d where athlete_id=aid;end if;
   prior:=coalesce(current_row,'{}')-array['athlete_id','updated_at','updated_by','id','created_at'];
  end if;
  -- An unchanged upsert or empty insert is safe; changed values must use the approval path.
  for col in select key from jsonb_each(v) loop
   if coalesce(v->col,'null') is distinct from coalesce(prior->col,'null') and not (prior->col is null and v->col in ('null','false','[]')) then changed:=true;end if;
  end loop;
 end if;
 if changed then raise exception 'Save team-profile edits through the parent approval form';end if;
 return new;
end $$;
