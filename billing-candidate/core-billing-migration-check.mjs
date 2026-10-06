import assert from 'node:assert/strict';
import {randomUUID as uuid} from 'node:crypto';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';
import {prepareCoreBillingFixture,fixtureBillingMigration} from './tests/core-billing-fixture.mjs';
const {db}=await fixture();let checks=0;
const pass=s=>{checks++;console.log('PASS '+s);};
async function absent(){assert.equal((await db.query("select to_regnamespace('wm_billing') n")).rows[0].n,null);}
try{
 await prepareCoreBillingFixture(db);const sql=await fixtureBillingMigration(db);
 const before=(await db.query('select catalog_hash,enabled from private.scoped_deletion_config')).rows[0];
 await db.exec("update private.scoped_deletion_config set catalog_hash='unreviewed'");
 await assert.rejects(()=>db.exec(sql),/CORE_BILLING_SCHEMA_REVIEW_REQUIRED/);await db.exec('rollback');await absent();
 await db.query('update private.scoped_deletion_config set catalog_hash=$1',[before.catalog_hash]);
 await db.exec("create or replace function private.scoped_deletion_read(p_table text,p_predicates jsonb,p_mention jsonb,p_limit integer) returns jsonb language sql as $$select '[]'::jsonb$$");
 await assert.rejects(()=>db.exec(sql),/CORE_BILLING_SOURCE_REVIEW_REQUIRED/);await db.exec('rollback');await absent();
 const {readFile}=await import('node:fs/promises');await db.exec(await readFile(new URL('./tests/core-billing-baseline-functions.sql',import.meta.url),'utf8'));
 pass('schema/catalog drift and changed privileged source block before any billing schema is installed');
 const pending=uuid();
 await db.query("insert into private.scoped_deletion_jobs(id,subject_hash,request_id,kind,personal,team_ids,organization_ids,receipt_hash,policy_version,catalog_hash) values($1,$2,$3,'personal',true,'{}','{}',$2,'scoped-deletion-v1',$4)",[pending,'a'.repeat(64),uuid(),before.catalog_hash]);
 await assert.rejects(()=>db.exec(sql),/CORE_BILLING_DELETION_IN_PROGRESS/);await db.exec('rollback');await absent();
 await db.query('delete from private.scoped_deletion_jobs where id=$1',[pending]);
 await db.exec('alter role wm_billing_runtime login');
 await assert.rejects(()=>db.exec(sql),/CORE_BILLING_RESTRICTED_ROLE_REQUIRED/);await db.exec('rollback');await absent();
 await db.exec('alter role wm_billing_runtime nologin');
 pass('pending deletion and an overprivileged runtime role stop installation without changing application data');
 await db.exec(sql);
 const current=(await db.query('select catalog_hash,enabled,catalog from private.scoped_deletion_config')).rows[0];
 assert.equal(current.enabled,before.enabled);assert.notEqual(current.catalog_hash,before.catalog_hash);
 assert.equal(current.catalog_hash,(await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h);
 assert.equal(current.catalog.tables.filter(t=>t.schema==='wm_billing').length,7);
 const router=(await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d;
 assert.ok(router.includes(current.catalog_hash));assert.ok(router.includes('wm_billing.merge_family_coverage(s,k)'));
 assert.equal(Number((await db.query("select count(*) n from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='wm_billing' and t.tgname='scoped_deletion_freeze'")).rows[0].n),7);
 pass('one transaction installs seven private billing tables and updates deletion/merge compatibility together without enabling deletion or payments');
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);await assert.rejects(()=>db.query('select * from wm_billing.subscriptions'),/permission denied/);await db.exec('reset role');
 }
 await db.exec('set role wm_billing_runtime');await assert.rejects(()=>db.query('insert into wm_billing.family_coverage values($1,1,$2)',[uuid(),uuid()]),/permission denied/);await db.exec('reset role');
 await assert.rejects(()=>db.exec(sql),/CORE_BILLING_ALREADY_INSTALLED/);await db.exec('rollback');
 assert.equal((await db.query('select catalog_hash from private.scoped_deletion_config')).rows[0].catalog_hash,current.catalog_hash);
 pass('client access and direct selection writes stay denied; replay refuses to overwrite an installed schema');
 const coach=uuid(),org=uuid(),team=uuid(),season=uuid(),s=uuid(),k=uuid(),sp=uuid(),kp=uuid();
 await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[coach]);await db.query('insert into public.profiles(id) values($1)',[coach]);
 await db.query("insert into public.organizations(id,name) values($1,'Synthetic')",[org]);await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Synthetic')",[team,org]);
 await db.query("insert into public.seasons(id,team_id,name) values($1,$2,'Current')",[season,team]);await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[team,coach]);
 for(const [id,pid] of [[s,sp],[k,kp]]){
  await db.query('insert into public.athlete_profiles(id) values($1)',[pid]);
  await db.query("insert into public.athletes(id,profile_id,organization_id,first_name,last_name) values($1,$2,$3,'Synthetic','Athlete')",[id,pid,org]);
  await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$2)',[season,id]);
 }
 await db.query('insert into wm_billing.family_coverage values($1,1,$2)',[coach,sp]);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:coach})]);await db.exec('set role authenticated');
 const data={team_id:team,duplicate_id:s,keep_id:k};
 const plan=(await db.query("select public.athlete_merge_request('preview',$1) r",[JSON.stringify(data)])).rows[0].r;
 assert.deepEqual(plan.blockers,[]);
 const result=(await db.query("select public.athlete_merge_request('merge',$1) r",[JSON.stringify({...data,version:plan.version,confirmation:'merge'})])).rows[0].r;
 assert.equal(result.status,'completed');await db.exec('reset role');
 assert.equal((await db.query('select athlete_profile_id from wm_billing.family_coverage where user_id=$1',[coach])).rows[0].athlete_profile_id,kp);
 pass('the migrated real merge router accepts its new fingerprint and preserves family coverage');
 console.log(`${checks} combined migration acceptance scenarios passed; synthetic database only.`);
}catch(error){console.error(error.message,error.where||'');process.exitCode=1;}finally{await db.close();}
