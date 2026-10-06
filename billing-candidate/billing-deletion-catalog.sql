-- Read-only structural inventory; never approves or updates the live catalog.
select jsonb_build_object(
 'tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'columns',
  (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull) order by a.attnum)
   from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) order by n.nspname,c.relname),'[]')
  from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','wm_billing') and c.relkind='r' and c.relname not like 'scoped_deletion_%'),
 'constraints',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',k.conname,'type',k.contype,
  'columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.conkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=c.oid and a.attnum=z.num),
  'ref_schema',rn.nspname,'ref_table',rc.relname,
  'ref_columns',(select jsonb_agg(a.attname order by z.ord) from unnest(k.confkey) with ordinality z(num,ord) join pg_attribute a on a.attrelid=rc.oid and a.attnum=z.num),
  'delete_action',k.confdeltype) order by n.nspname,c.relname,k.conname),'[]')
  from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
  left join pg_class rc on rc.oid=k.confrelid left join pg_namespace rn on rn.oid=rc.relnamespace
  where n.nspname in ('public','private','wm_billing') and c.relname not like 'scoped_deletion_%')
) as catalog;
