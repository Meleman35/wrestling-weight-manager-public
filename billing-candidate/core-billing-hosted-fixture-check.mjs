// Isolated full-schema regression for the real hosted fixture and lifecycle.
// Auth/Storage providers here are synthetic; this script cannot use a hosted URL.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import {runScopedDeletion} from '../scripts/scoped-deletion-worker.mjs';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';
import {prepareCoreBillingFixture,fixtureBillingMigration} from './tests/core-billing-fixture.mjs';
const {db}=await fixture();
try {
 await prepareCoreBillingFixture(db);await db.exec(await fixtureBillingMigration(db));
 await db.exec(await readFile(new URL('../supabase/migrations/20261005024932_core_billing_hosted_acceptance.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../supabase/migrations/20261005024934_billing_closed_team_remainders.sql',import.meta.url),'utf8'));
 const run=uuid(),actor=uuid(),retained=uuid(),child=uuid(),hash='c'.repeat(64);
 await db.query("insert into private.scoped_deletion_acceptance_runs(id,token_hash,expires_at) values($1,$2,now()+interval '1 hour')",[run,hash]);
 for(const id of [actor,retained,child])await db.query("insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values($1,$2,now(),$3)",[id,id+'@tests.example.invalid',{scoped_deletion_acceptance:run}]);
 const billing=async action=>(await db.query('select public.scoped_deletion_billing_acceptance($1,$2,$3) r',[action,run,hash])).rows[0].r;
 const base=async(action,data={})=>(await db.query('select public.scoped_deletion_acceptance($1,$2,$3,$4) r',[action,run,hash,data])).rows[0].r;
 for(const role of ['anon','authenticated','wm_billing_runtime']){await db.exec('set role '+role);await assert.rejects(()=>billing('seed'),/permission/);await db.exec('reset role');}
 await db.exec('set role service_role');
 await assert.rejects(()=>billing('seed'),/NOT_AUTHORIZED/);await base('authorize');
 await assert.rejects(()=>billing('seed'),/IDENTITIES_REQUIRED/);
 await base('seed',{actor,retained,child});assert.deepEqual(await billing('seed'),{billing_seeded:true});
 await assert.rejects(()=>billing('seed'),/IDENTITIES_REQUIRED/);await assert.rejects(()=>billing('verify'),/COMPLETED_FIXTURE_REQUIRED/);await assert.rejects(()=>billing('cleanup'),/VERIFIED_BILLING_FIXTURE_REQUIRED/);
 await db.exec('reset role');
 assert.equal((await db.query('select count(*)::int n from wm_billing.subscriptions')).rows[0].n,3);
 assert.equal((await db.query('select count(*)::int n from wm_billing.notification_inbox')).rows[0].n,4);
 const runRow=(await db.query('select * from private.scoped_deletion_acceptance_runs where id=$1',[run])).rows[0];
 const session=uuid();await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,actor]);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'authenticated',sub:actor,session_id:session,exp:Math.floor(Date.now()/1000)+3600})]);
 await db.exec('set role authenticated');
 const job=(await db.query("select public.scoped_deletion_begin('all',$1,$2,'delete',$3,$4) r",[[runRow.team_id],[runRow.organization_id],uuid(),'b'.repeat(64)])).rows[0].r;
 await db.exec('reset role;set role service_role');await base('job',{id:job.id});await db.exec('reset role');
 const service=async(op,job,lease,input={})=>{await db.exec('set role service_role');try{return (await db.query('select public.scoped_deletion_service($1,$2,$3,$4) r',[op,job,lease,input])).rows[0].r;}catch(e){console.error('SERVICE',op,e.message,e.where);throw e;}finally{await db.exec('reset role');}};
 const provider={disableIdentity:async id=>{assert.equal(id,actor);await db.query("update auth.users set banned_until=now()+interval '100 years' where id=$1",[id]);},deleteIdentity:async id=>{assert.equal(id,actor);await db.query('delete from auth.users where id=$1',[id]);},identityExists:async id=>(await db.query('select 1 from auth.users where id=$1',[id])).rows.length>0,removeObject:async()=>{throw Error('unexpected object');},objectExists:async()=>{throw Error('unexpected object');}};
 const outcome=await runScopedDeletion({service,provider,jobId:job.id,receiptHash:'b'.repeat(64),budgetMs:120000});assert.equal(outcome.state,'completed',JSON.stringify(outcome));
 await db.exec('set role service_role');const verified=await billing('verify');assert.equal(Object.values(verified).every(x=>x===true),true);await base('verify',verified);assert.deepEqual(await billing('cleanup'),{billing_fixtures_cleaned:true});await db.exec('reset role');
 for(const table of ['team_bindings','intents','subscriptions','family_coverage','deliveries','notification_inbox','team_paid_remainders'])assert.equal((await db.query('select count(*)::int n from wm_billing.'+table)).rows[0].n,0,table);
 console.log('PASS actual deletion planner/worker/service removes selected billing, preserves the other account, and verifies scoped fixture cleanup.');
 console.log('PASS synthetic billing fixture requires service role, expiring capability, tagged identities and correct lifecycle; seeds all billing scopes.');
} catch(e){console.error(e.message,e.where);process.exitCode=1;} finally {await db.close();}
