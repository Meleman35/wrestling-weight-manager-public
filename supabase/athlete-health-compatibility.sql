-- Retain exact schema-drift guards. New health records are not allowlisted for
-- automatic erasure; affected shared medical records continue to require review.
-- Register the complete structural catalog, never merely reset the hash.
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
 if position('4edb6748d4f52b32daeb62498f2fb3152b6bc5caa1ac1618b7e89e77c850d587' in source)=0 then raise exception 'Unexpected athlete merge version; review compatibility first';end if;
 execute replace(source,'4edb6748d4f52b32daeb62498f2fb3152b6bc5caa1ac1618b7e89e77c850d587',expected_hash);
 source:=pg_get_functiondef('private.athlete_merge_plan(uuid,uuid,text)'::regprocedure);
 if position('if exists(select 1 from private.weight_test_athletes' in source)=0 then raise exception 'Unexpected athlete merge planner';end if;
 source:=replace(source,'if exists(select 1 from private.weight_test_athletes',
  'if exists(select 1 from private.health_cases where athlete_id in(s,k)) or exists(select 1 from private.health_family_permissions where athlete_id in(s,k)) then blockers:=blockers||jsonb_build_array(''Private health records or health-sharing permissions are attached. Contact support for a trainer-assisted identity review before merging.'');end if;'||chr(10)||' if exists(select 1 from private.weight_test_athletes');
 execute source;
end $$;
