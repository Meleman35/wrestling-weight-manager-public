import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {billingDeletionIntegrationSQL} from './billing-deletion-integration.mjs';

export const coreBillingMigrationPath=new URL('../supabase/migrations/20261005021830_core_billing_deletion_merge.sql',import.meta.url);
export const reviewedBaselineHash='c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8';
const read=name=>readFile(new URL(name,import.meta.url),'utf8');
export async function coreBillingMigrationSQL(){
 const pins=JSON.parse(await read('tests/billing-migration-source-pins.json'));
 const assertions=pins.map(({signature,hash})=>{
  if(!/^private\.[a-z_]+\([a-z,]*\)$/.test(signature)||!/^[a-f0-9]{64}$/.test(hash))throw Error('Invalid source pin');
  return ` if encode(sha256(convert_to(pg_get_functiondef('${signature}'::regprocedure),'UTF8')),'hex')<>'${hash}' then raise exception 'CORE_BILLING_SOURCE_REVIEW_REQUIRED: ${signature}';end if;`;
 }).join('\n');
 const preflight=`-- Generated from reviewed candidate sources by core-billing-migration.mjs.
-- This migration installs storage and lifecycle integration, not purchase activation.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
select pg_advisory_xact_lock(hashtext('athlete_merge'));
lock table private.scoped_deletion_config,private.scoped_deletion_jobs in exclusive mode;
do $$begin
 if to_regnamespace('wm_billing') is not null then raise exception 'CORE_BILLING_ALREADY_INSTALLED';end if;
 if private.scoped_deletion_schema_hash() is distinct from '${reviewedBaselineHash}'
  or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash() and policy_version='scoped-deletion-v1') then
  raise exception 'CORE_BILLING_SCHEMA_REVIEW_REQUIRED';end if;
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('cancelled','completed')) then
  raise exception 'CORE_BILLING_DELETION_IN_PROGRESS';end if;
 if not exists(select 1 from pg_roles where rolname='wm_billing_runtime' and not rolcanlogin and not rolsuper and not rolbypassrls and not rolcreaterole and not rolcreatedb) then
  raise exception 'CORE_BILLING_RESTRICTED_ROLE_REQUIRED';end if;
${assertions}
end $$;`;
 const parts=[preflight];
 for(const file of ['billing-storage-candidate.sql','apple-notification-inbox.sql','team-paid-remainder-storage.sql','billing-access-candidate.sql','billing-merge-integration.sql'])parts.push(await read(file));
 parts.push(await billingDeletionIntegrationSQL());
 const catalog=(await read('billing-deletion-catalog.sql')).replace('-- Read-only structural inventory; never approves or updates the live catalog.\n','').trim().replace(/ as catalog;$/,' into reviewed_catalog;');
 if(!catalog.endsWith(' into reviewed_catalog;'))throw Error('Catalog assembly changed');
 parts.push(`-- The unchanged baseline and six source pins were checked before any DDL.
-- Enroll exactly the seven reviewed tables, then update both compatibility gates
-- atomically with their lifecycle hooks. Never approve an arbitrary drifted hash.
do $$declare reviewed_catalog jsonb;new_hash text;source text;actual_tables text[];
 old_hash text:='${reviewedBaselineHash}';
begin
 select array_agg(c.relname::text order by c.relname) into actual_tables from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and c.relkind='r';
 if actual_tables is distinct from array['deliveries','family_coverage','intents','notification_inbox','subscriptions','team_bindings','team_paid_remainders'] then raise exception 'CORE_BILLING_TABLE_REVIEW_REQUIRED';end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and c.relkind='r' and not c.relrowsecurity) then raise exception 'CORE_BILLING_RLS_REQUIRED';end if;
 if (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and t.tgname='scoped_deletion_freeze' and not t.tgisinternal)<>7 then raise exception 'CORE_BILLING_FREEZE_REQUIRED';end if;
 ${catalog}
 new_hash:=private.scoped_deletion_schema_hash();
 if new_hash=old_hash or new_hash!~'^[a-f0-9]{64}$' then raise exception 'CORE_BILLING_FINGERPRINT_REQUIRED';end if;
 source:=pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure);
 if (length(source)-length(replace(source,old_hash,'')))<>length(old_hash)
  or position('wm_billing.merge_family_coverage(s,k)' in source)=0 then raise exception 'CORE_BILLING_MERGE_REVIEW_REQUIRED';end if;
 execute replace(source,old_hash,new_hash);
 update private.scoped_deletion_config set catalog=reviewed_catalog,catalog_hash=new_hash where id;
end $$;
commit;`);
 return parts.join('\n\n')+'\n';
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const sql=await coreBillingMigrationSQL();
 if(process.argv.includes('--write'))await writeFile(coreBillingMigrationPath,sql);
 else if(await readFile(coreBillingMigrationPath,'utf8')!==sql)throw Error('Core billing migration is stale');
 console.log('PASS core billing migration matches its reviewed source assembly');
}
