import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {coreBillingMigrationPath,coreBillingMigrationSQL,reviewedBaselineHash} from '../core-billing-migration.mjs';
const root=new URL('../../',import.meta.url),read=path=>readFile(new URL(path,root),'utf8');

// Full structural fixture, actual inspected function bodies, synthetic providers
// and adult eligibility. Does not accept a connection string or hosted database.
export async function prepareCoreBillingFixture(db){
 await db.exec(`create role wm_billing_runtime;
  alter table auth.users add confirmed_at timestamptz generated always as (email_confirmed_at) stored;
  alter table auth.users add is_anonymous boolean not null default false;
  create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,version text,owner uuid,owner_id text,unique(bucket_id,name));
  grant usage on schema private,auth,public to authenticated,service_role;
  create function private.enforce_team_login_request() returns void language plpgsql as $$begin return;end$$;
  create function private.board_personal(u uuid) returns boolean language sql as $$select u is not null and not exists(select 1 from private.team_logins where user_id=u)$$;
  create function private.board_minor(u uuid) returns boolean language sql as $$select false$$;
  create function public.is_team_admin(t uuid) returns boolean language sql as $$select exists(select 1 from public.team_memberships where team_id=t and user_id=auth.uid() and active and role='head_coach')$$;`);
 const phone=await read('supabase/migrations/20260930031742_account_deletion_phone_preflight.sql');
 await db.exec(phone.slice(phone.indexOf('create function private.account_deletion_phone_preflight()'),phone.indexOf('create function public.account_deletion_phone_preflight()')));
 for(const path of ['tests/fixtures/scoped-deletion-mutation-triggers.sql','supabase/migrations/20260930060258_scoped_deletion_worker.sql',
  'supabase/migrations/20260930065511_scoped_deletion_hosted_acceptance.sql',
  'supabase/migrations/20260930155742_athlete_merge_020103.sql',
  'supabase/migrations/20260930172502_athlete_merge_guardian_conflicts_020103.sql',
  'supabase/migrations/20260930174240_athlete_merge_contact_review_020104.sql',
  'tests/fixtures/athlete-merge-profile-triggers.sql','billing-candidate/tests/core-billing-baseline-functions.sql'])await db.exec(await read(path));
 const access=await read('billing-candidate/tests/access-fixture.sql');
 await db.exec(access.slice(access.indexOf('create function private.managed_login_access_ok()')));
 await db.exec('update private.scoped_deletion_config set catalog_hash=private.scoped_deletion_schema_hash()');
}
export async function fixtureBillingMigration(db){
 const sql=await readFile(coreBillingMigrationPath,'utf8');assert.equal(sql,await coreBillingMigrationSQL());
 const hash=(await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h;
 // Fixture type OIDs/defaults differ from the hosted database. Adapt only the
 // initial environment fingerprint. Every function-source pin remains exact.
 const old=`private.scoped_deletion_schema_hash() is distinct from '${reviewedBaselineHash}'`;
 assert.equal(sql.split(old).length,2);
 return sql.replace(old,`private.scoped_deletion_schema_hash() is distinct from '${hash}'`);
}
