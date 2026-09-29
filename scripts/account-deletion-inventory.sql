-- Read-only catalogue inventory. No account values, row counts, object names,
-- credentials, function bodies or application writes are returned/performed.
-- This is not a deletion query or a migration.
with relations as (
  select c.oid, n.nspname as schema_name, c.relname as table_name,
    format('%I.%I', n.nspname, c.relname) as key
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private', 'auth', 'storage')
    and c.relkind in ('r', 'p')
), tables as (
  select r.key, r.schema_name, r.table_name,
    coalesce((select jsonb_agg(a.attname order by a.attnum)
      from pg_catalog.pg_attribute a where a.attrelid = r.oid
      and a.attnum > 0 and not a.attisdropped), '[]'::jsonb) as columns,
    coalesce((select jsonb_agg(a.attname order by a.attnum)
      from pg_catalog.pg_attribute a where a.attrelid = r.oid
      and a.attnum > 0 and not a.attisdropped and a.atttypid in
      ('json'::regtype, 'jsonb'::regtype)), '[]'::jsonb) as json_columns
  from relations r
), foreign_keys as (
  select child.key || '.' || c.conname as key,
    child.key as from_table, parent.key as to_table,
    (select jsonb_agg(a.attname order by k.ord)
      from unnest(c.conkey) with ordinality k(attnum, ord)
      join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) as from_columns,
    (select jsonb_agg(a.attname order by k.ord)
      from unnest(c.confkey) with ordinality k(attnum, ord)
      join pg_catalog.pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.attnum) as to_columns,
    case c.confdeltype when 'a' then 'NO ACTION' when 'r' then 'RESTRICT'
      when 'c' then 'CASCADE' when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT'
      else 'UNKNOWN' end as on_delete,
    c.condeferrable as deferrable, c.convalidated as validated
  from pg_catalog.pg_constraint c
  join relations child on child.oid = c.conrelid
  join relations parent on parent.oid = c.confrelid
  where c.contype = 'f'
)
select jsonb_build_object(
  'format_version', 1,
  'scope', jsonb_build_array('auth', 'private', 'public', 'storage'),
  'tables', coalesce((select jsonb_agg(to_jsonb(t) order by t.key) from tables t), '[]'::jsonb),
  'foreign_keys', coalesce((select jsonb_agg(to_jsonb(f) order by f.key) from foreign_keys f), '[]'::jsonb)
) as inventory;
