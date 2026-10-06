import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';
import {runScopedDeletion} from '../scripts/scoped-deletion-worker.mjs';
import {prepareCoreBillingFixture,fixtureBillingMigration} from './tests/core-billing-fixture.mjs';
import {reconcileSubscription,proposedProducts} from './subscription-policy.mjs';

// Actual planner, service SQL, freeze triggers and worker; only Auth/Storage
// providers and adult eligibility helpers are synthetic. Never uses a live URL.
const {db}=await fixture();
const uuid=()=>randomUUID();
const config={environment:'Sandbox',bundleID:'com.damonmele.wrestlingmanager',products:proposedProducts};
let checks=0,sequence=500;
const pass=name=>{checks++;console.log('PASS '+name);};
const runAs=async(role,fn)=>{await db.exec('set role '+role);try{return await fn();}finally{await db.exec('reset role');}};
const service=(op,job,lease,input={})=>runAs('service_role',async()=>
 (await db.query('select public.scoped_deletion_service($1,$2,$3,$4::jsonb) as result',[op,job,lease,JSON.stringify(input)])).rows[0].result);
const count=async(table,where='',args=[])=>Number((await db.query('select count(*) as n from '+table+where,args)).rows[0].n);
const retry=()=>db.exec('update private.scoped_deletion_jobs set retry_after=null');
async function seed(){
 const owner=uuid(),admin=uuid(),org=uuid(),team=uuid(),token=uuid(),family=uuid(),unpaid=uuid(),session=uuid(),now=Date.now();
 const original=String(++sequence),familyOriginal=String(++sequence),productID='com.damonmele.wrestlingmanager.teampro.annual';
 for(const id of [owner,admin]){
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);
  await db.query('insert into public.profiles(id,display_name) values($1,$2)',[id,'Synthetic adult']);
 }
 await db.query("insert into public.organizations(id,name) values($1,'Synthetic organization')",[org]);
 await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Synthetic team')",[team,org]);
 await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach'),($1,$3,'head_coach')",[team,owner,admin]);
 // A surviving adult's portable photo is also used by their team staff row.
 // Team closure must preserve the actual file and the adult's profile reference.
 const photo='synthetic/'+admin+'.jpg';
 await db.query('update public.profiles set photo_path=$1 where id=$2',[photo,admin]);
 await db.query("insert into public.team_staff_profiles(team_id,user_id,display_name,photo_path) values($1,$2,'Synthetic adult',$3)",[team,admin,photo]);
 await db.query("insert into storage.objects(bucket_id,name,version,owner) values('profile-photos',$1,'v1',$2)",[photo,admin]);
 const evidence={...config,products:undefined,productID,transactionID:original,originalTransactionID:original,
  appAccountToken:token,status:1,snapshotSignedAt:now-1000,expiresAt:now+600000};
 const subscription=reconcileSubscription({actor:{userID:owner,confirmed:true,liveSession:true},
  intent:{userID:owner,teamID:team,token,productID,authorized:true},evidence,config,now}).subscription;
 await db.query('insert into wm_billing.team_bindings values($1,$2)',[owner,team]);
 for(const t of [token,unpaid])await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at) values($1,$2,$3,'team',$4,$5)",[t,owner,productID,team,now]);
 await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,family_owner_id,created_at) values($1,$2,'com.damonmele.wrestlingmanager.familyvideo.monthly','family',$2,$3)",[family,owner,now]);
 await db.query("insert into wm_billing.subscriptions values('Sandbox',$1,$2,$3,'team',$4,null,$5)",[original,token,owner,team,subscription]);
 const fs={...subscription,plan:'family_video_month',productID:'com.damonmele.wrestlingmanager.familyvideo.monthly',
  originalTransactionID:familyOriginal,appAccountToken:family,teamID:null,familyOwnerID:owner};
 await db.query("insert into wm_billing.subscriptions values('Sandbox',$1,$2,$3,'family',null,$3,$4)",[familyOriginal,family,owner,fs]);
 for(const n of [original,familyOriginal])await db.query("insert into wm_billing.deliveries(environment,transaction_id,original_id) values('Sandbox',$1,$1)",[n]);
 await db.query('insert into wm_billing.family_coverage values($1,1,$2)',[owner,uuid()]);
 for(const t of [token,unpaid,family])await db.query("insert into wm_billing.notification_inbox(environment,notification_id,original_id,token,evidence) values('Sandbox',$1,$2,$3,$4)",[uuid(),t===family?familyOriginal:original,t,t===token?evidence:{}]);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,owner]);
 await db.query("insert into private.account_deletion_phone_testers(user_id,expires_at) values($1,now()+interval '1 day')",[owner]);
 return {owner,admin,org,team,token,family,unpaid,session,now,evidence,subscription,original,familyOriginal};
}
async function begin(s,kind='personal'){
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'authenticated',sub:s.owner,session_id:s.session,exp:Math.floor(Date.now()/1000)+3600})]);
 return runAs('authenticated',async()=>
  (await db.query("select public.scoped_deletion_begin($1,$2,'{}','delete',$3,$4) as result",[kind,kind==='personal'?[]:[s.team],uuid(),'a'.repeat(64)])).rows[0].result);
}
function providers(s,{pauseRevocation=false,pauseAuth=false}={}){
 return {
  async disableIdentity(actor){assert.equal(actor,s.owner);if(pauseRevocation){pauseRevocation=false;throw Error('Synthetic provider outage');}
   await db.query("update auth.users set banned_until=now()+interval '100 years' where id=$1",[actor]);},
  async deleteIdentity(actor){assert.equal(actor,s.owner);if(pauseAuth){pauseAuth=false;throw Error('Synthetic Auth outage');}
   await db.query('delete from auth.users where id=$1',[actor]);},
  async identityExists(actor){return await count('auth.users',' where id=$1',[actor])>0;},
  async removeObject(){throw Error('Unexpected object');},async objectExists(){throw Error('Unexpected object');}
 };
}
const run=(job,provider)=>runScopedDeletion({service,provider,jobId:job.id,receiptHash:'a'.repeat(64),budgetMs:120000});
try{
 await prepareCoreBillingFixture(db);
 await db.exec(await fixtureBillingMigration(db));
 // A fixed synthetic failure trigger is present before inventory fingerprinting.
 await db.exec(`create function wm_billing.synthetic_failure() returns trigger language plpgsql as $$begin
  if current_setting('wm.synthetic_billing_failure',true)='on' then raise exception 'SYNTHETIC_FAILURE';end if;return old;end$$;
  create trigger synthetic_failure before delete on wm_billing.intents for each row execute function wm_billing.synthetic_failure();`);
 const catalog=(await db.query(await readFile(new URL('billing-deletion-catalog.sql',import.meta.url),'utf8'))).rows[0].catalog;
 assert.equal(catalog.tables.filter(t=>t.schema==='wm_billing').length,7);
 await db.query('update private.scoped_deletion_config set enabled=true,catalog=$1,catalog_hash=private.scoped_deletion_schema_hash()',[catalog]);
 const hash=(await db.query('select private.scoped_deletion_schema_hash() as hash')).rows[0].hash;
 await db.exec('begin;alter table wm_billing.intents add synthetic_drift text');
 assert.notEqual((await db.query('select private.scoped_deletion_schema_hash() as hash')).rows[0].hash,hash);
 await db.exec('rollback');
 pass('all seven billing tables are inventoried and billing schema drift changes the deletion fingerprint');

 const retained=await seed(),s=await seed(),job=await begin(s),provider=providers(s,{pauseRevocation:true,pauseAuth:true});
 let result=await run(job,provider);assert.equal(result.state,'sealed',JSON.stringify(result));
 assert.equal((await db.query('select state from private.scoped_deletion_jobs where id=$1',[job.id])).rows[0].state,'revoking');
 assert.equal((await db.query("select count(distinct table_name)::int n from private.scoped_deletion_rows where job_id=$1 and table_name like 'wm_billing.%'",[job.id])).rows[0].n,6);
 await assert.rejects(db.query('update wm_billing.intents set cancelled=true where token=$1',[s.token]),/DELETION_RECORDS_LOCKED/);
 await assert.rejects(db.query("insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at) values($1,$2,$3,'team',$4,$5)",[uuid(),s.owner,s.evidence.productID,s.team,s.now]),/DELETION_RECORDS_LOCKED/);
 await assert.rejects(db.query("insert into wm_billing.notification_inbox(environment,notification_id,original_id,token,evidence) values('Sandbox',$1,$2,$3,'{}')",[uuid(),s.original,s.token]),/DELETION_RECORDS_LOCKED/);
 await db.query('update wm_billing.intents set cancelled=true where token=$1',[retained.unpaid]);
 pass('sealed deletion freezes existing and late billing writes while another account remains writable');

 await db.exec("select set_config('wm.synthetic_billing_failure','on',false)");await retry();
 result=await run(job,provider);assert.equal(result.state,'records',JSON.stringify(result));
 assert.equal(await count('wm_billing.team_paid_remainders'),0);
 assert.equal(await count('wm_billing.subscriptions',' where user_id=$1',[s.owner]),2);
 assert.equal(await count('public.profiles',' where id=$1',[s.owner]),1);
 pass('billing failure rolls back the paid grant, all billing cleanup and ordinary profile erasure together');

 await db.exec("select set_config('wm.synthetic_billing_failure','off',false)");await retry();
 result=await run(job,provider);assert.equal(result.state,'auth',JSON.stringify(result));
 let grant=(await db.query('select * from wm_billing.team_paid_remainders where team_id=$1',[s.team])).rows;
 assert.equal(grant.length,1);assert.equal(Number(grant[0].paid_through),s.subscription.expiresAt);
 for(const raw of [s.owner,s.token,s.family,s.original,'originalTransactionID','appAccountToken'])
  assert.equal(JSON.stringify(grant).includes('"'+raw+'"'),false);
 for(const table of ['team_bindings','intents','subscriptions','family_coverage'])assert.equal(await count('wm_billing.'+table,' where user_id=$1',[s.owner]),0,table);
 assert.equal(await count('wm_billing.notification_inbox',' where token=any($1::uuid[])',[[s.token,s.family,s.unpaid]]),0);
 assert.equal(await count('wm_billing.deliveries',' where original_id=any($1::text[])',[[s.original,s.familyOriginal]]),0);
 await retry();result=await run(job,provider);assert.equal(result.state,'completed',JSON.stringify(result));
 assert.equal(await count('auth.users',' where id=$1',[s.owner]),0);
 assert.equal(await count('wm_billing.subscriptions',' where user_id=$1',[retained.owner]),2);
 assert.equal(await count('auth.users',' where id=any($1::uuid[])',[[s.admin,retained.owner,retained.admin]]),3);
 assert.equal(await count('private.scoped_deletion_rows',' where job_id=$1',[job.id]),0);
 pass('full worker preserves exact paid team time, removes personal/family billing and completes after an Auth retry');

 const refunded=await seed();
 await db.query("update wm_billing.notification_inbox set evidence=$1 where token=$2",[{...refunded.evidence,status:5,revokedAt:refunded.now,snapshotSignedAt:refunded.now},refunded.token]);
 const refundJob=await begin(refunded);result=await run(refundJob,providers(refunded));
 assert.equal(result.state,'completed',JSON.stringify(result));
 grant=(await db.query('select revoked_at from wm_billing.team_paid_remainders where team_id=$1',[refunded.team])).rows;
 assert.equal(grant.length,1);assert.equal(Number(grant[0].revoked_at),refunded.now);
 pass('the full worker applies an acknowledged pending refund before deleting the inbox');

 for(const kind of ['team','all']){
  const selected=await seed(),selectedJob=await begin(selected,kind);
  result=await run(selectedJob,providers(selected));assert.equal(result.state,'completed',JSON.stringify(result));
  assert.equal(await count('public.teams',' where id=$1',[selected.team]),0);
  assert.equal(await count('wm_billing.team_paid_remainders',' where team_id=$1',[selected.team]),0);
  assert.equal(await count('wm_billing.intents',' where team_id=$1',[selected.team]),0);
  assert.equal(await count('wm_billing.subscriptions',' where user_id=$1',[selected.owner]),kind==='team'?1:0);
  assert.equal(await count('auth.users',' where id=$1',[selected.owner]),kind==='team'?1:0);
  assert.equal(await count('storage.objects',' where owner=$1',[selected.admin]),1);
 }
 pass('team-only and combined deletion remove selected team billing and preserve only the intended personal account/family scope');
 for(const role of ['anon','authenticated','wm_billing_runtime'])await runAs(role,()=>assert.rejects(db.query('select wm_billing.prepare_deletion($1,$2)',[uuid(),uuid()]),/permission/));
 pass('clients and the billing runtime cannot invoke the privileged deletion preparation');
 console.log(`${checks} complete billing/deletion worker scenarios passed; synthetic data and provider adapters only.`);
}catch(error){console.error(error.message,error.code??'',error.where??'');process.exitCode=1;}finally{await db.close();}
