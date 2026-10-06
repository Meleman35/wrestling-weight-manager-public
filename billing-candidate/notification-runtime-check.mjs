import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';
import {prepareCoreBillingFixture,fixtureBillingMigration} from './tests/core-billing-fixture.mjs';
const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');
const {db}=await fixture();let checks=0;const pass=s=>{checks++;console.log('PASS '+s);};
const knownSecret='e'.repeat(64),owner=uuid(),token=uuid(),team=uuid(),organization=uuid(),old=new Date(Date.now()-31*86400000).toISOString();
async function role(name,fn){await db.exec('set role '+name);try{return await fn();}finally{await db.exec('reset role');}}
const ready=async()=>(await db.query('select wm_billing.notification_deployment_ready() ready')).rows[0].ready;
const purge=async()=>(await db.query('select wm_billing.purge_notification_operations() r')).rows[0].r;
try{
 await prepareCoreBillingFixture(db);await db.exec(await fixtureBillingMigration(db));
 await db.exec(await read('supabase/migrations/20261005024934_billing_closed_team_remainders.sql'));
 // Provider infrastructure is synthetic. The tested migration remains exact
 // except its initial structural fingerprint, because fixture OIDs differ.
 await db.exec(`create schema vault;create schema cron;create schema net;
  create table vault.secrets(id uuid primary key default gen_random_uuid(),name text unique,secret text,description text);
  create view vault.decrypted_secrets as select name,secret as decrypted_secret from vault.secrets;
  create function vault.create_secret(secret text,name text,description text) returns uuid language sql as $$insert into vault.secrets(secret,name,description) values($1,$2,$3) returning id$$;
  create table cron.job(jobid bigint generated always as identity,jobname text,schedule text,command text,active boolean default true);
  create function cron.schedule(job_name text,schedule text,command text) returns bigint language sql as $$insert into cron.job(jobname,schedule,command) values($1,$2,$3) returning jobid$$;
  create function cron.alter_job(job_id bigint,active boolean) returns void language sql as $$update cron.job set active=$2 where jobid=$1$$;
  create table net.requests(id bigint generated always as identity,url text,headers jsonb,body jsonb,timeout_milliseconds integer);
  create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language sql as $$insert into net.requests(url,headers,body,timeout_milliseconds) values($1,$2,$3,$4) returning id$$;`);
 await db.query("insert into vault.secrets(name,secret) values('wm-billing-notification-worker',$1)",[knownSecret]);
 const fingerprint=(await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h;
 const migration=(await read('supabase/migrations/20261005032225_billing_notification_runtime.sql')).replaceAll('22b2b942416753db8212d4f2bb4550da01713e687376eb2becaa8f6dfb22f350',fingerprint);
 await db.exec(migration);
 assert.equal(await ready(),false);
 for(const actor of ['anon','authenticated'])await role(actor,async()=>{
  for(const sql of ['select wm_billing.notification_deployment_ready()',"select wm_billing.authorize_notification_worker('x')",'select wm_billing.purge_notification_operations()','select private.billing_notification_tick(true)'])await assert.rejects(()=>db.query(sql),/permission/);
 });
 await role('wm_billing_runtime',async()=>{
  assert.equal(await ready(),false);await assert.rejects(()=>db.query('select * from vault.decrypted_secrets'),/permission/);
  await assert.rejects(()=>db.query('select private.billing_notification_tick(true)'),/permission/);
  for(const value of ['',null,'a'.repeat(64),knownSecret+'\n'])assert.equal((await db.query('select wm_billing.authorize_notification_worker($1) allowed',[value])).rows[0].allowed,false);
  assert.equal((await db.query('select wm_billing.authorize_notification_worker($1) allowed',[knownSecret])).rows[0].allowed,true);
 });
 pass('notification helpers require the restricted role; worker authorization never exposes Vault and rejects malformed/wrong capabilities');
 const flags={fixtures_cleaned:true,provider_auth:true,provider_files:true,old_jwt_rejected:true,billing_actor_absent:true,billing_inbox_absent:true,billing_deliveries_absent:true,billing_other_preserved:true};
 await db.query("insert into private.scoped_deletion_acceptance_runs(token_hash,expires_at,state,result) values($1,now(),'cleaned',$2)",['a'.repeat(64),flags]);
 assert.equal(await ready(),false);await db.exec('update private.scoped_deletion_config set enabled=true');assert.equal(await ready(),true);
 await db.exec('begin;alter table wm_billing.intents add synthetic_drift text');assert.equal(await ready(),false);await db.exec('rollback');
 await db.exec('begin;alter table wm_billing.intents disable row level security');assert.equal(await ready(),false);await db.exec('rollback');
 assert.equal((await db.query("select active from cron.job where jobname='wm-billing-notifications'")).rows[0].active,false);
 pass('readiness requires completed hosted acceptance, enabled deletion, unchanged schema and all RLS gates; schedule starts paused');

 await db.query("insert into public.organizations(id,name) values($1,'Synthetic')",[organization]);
 await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Synthetic')",[team,organization]);
 await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at) values($1,$2,'com.damonmele.wrestlingmanager.teampro.monthly','team',$3,0)",[token,owner,team]);
 const keep=[];
 for(const [state,age,bound] of [['completed',old,false],['pending',old,false],['completed',new Date().toISOString(),false],['pending',old,true],['processing',old,false]]){
  const id=uuid();if(keep.length<3&&!(age===old&&!bound&&state!=='processing'))keep.push(id);
  await db.query("insert into wm_billing.notification_inbox(environment,notification_id,original_id,token,evidence,received_at,state) values('Sandbox',$1,'801',$2,'{}',$3,$4)",[id,bound?token:uuid(),age,state]);
 }
 await db.query("insert into wm_billing.team_paid_remainders values($1,$2,'Sandbox','team_pro_month',0,null,0)",['b'.repeat(64),team]);
 const cleaned=await role('wm_billing_runtime',purge);assert.deepEqual(cleaned,{deferred:false,inbox:2,remainders:1});
 assert.equal((await db.query('select count(*)::int n from wm_billing.notification_inbox')).rows[0].n,3);
 assert.equal((await db.query('select count(*)::int n from wm_billing.intents')).rows[0].n,1);
 pass('bounded cleanup removes only old completed/unbound inbox entries and expired remainders; bound pending/leased work and purchase records remain');

 await db.query("insert into private.scoped_deletion_jobs(actor_id,subject_hash,request_id,kind,personal,team_ids,organization_ids,receipt_hash,policy_version,catalog_hash,state) values($1,'synthetic',$2,'team',false,$3,'{}',$4,'scoped-deletion-v1','synthetic','planning')",[owner,uuid(),[team],'a'.repeat(64)]);
 assert.deepEqual(await purge(),{deferred:true,inbox:0,remainders:0});
 await db.exec("delete from private.scoped_deletion_jobs where subject_hash='synthetic'");
 const tick=(await db.query('select private.billing_notification_tick(true) r')).rows[0].r;assert.equal(tick.ready,true);assert.equal(tick.requests.length,2);
 const requests=(await db.query('select * from net.requests order by id')).rows;
 assert.deepEqual(requests.map(r=>r.url),['production','sandbox'].map(env=>'https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-apple-notifications/'+env+'/reconcile'));
 assert(requests.every(r=>r.headers.Authorization==='Bearer '+knownSecret&&r.timeout_milliseconds===45000));
 assert.equal(JSON.stringify(tick).includes(knownSecret),false);
 pass('cleanup defers to active deletions; the scheduler targets only fixed environment endpoints and returns no credential');
 console.log(`${checks} notification runtime database scenarios passed; synthetic providers only.`);
}catch(error){console.error(error.message,error.where??'');process.exitCode=1;}finally{await db.close();}
