import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createTeamRemainderReconciler} from './team-paid-remainder-postgres.mjs';
import {createBillingNotificationPersistence} from './billing-notification-persistence.mjs';
import {SubscriptionAccessService} from './subscription-access.mjs';
import {proposedProducts,reconcileSubscription} from './subscription-policy.mjs';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
const db=new PGlite();
let passed=0;
const check=async(name,run)=>{await run();passed++;console.log('PASS '+name);};
const owner=randomUUID(),admin=randomUUID(),viewer=randomUUID(),team=randomUUID(),otherTeam=randomUUID(),organization=randomUUID();
const job=randomUUID(),lease=randomUUID(),token=randomUUID(),familyToken=randomUUID(),now=Date.now();
const config={environment:'Sandbox',bundleID:'com.damonmele.wrestlingmanager',products:proposedProducts};
const productID='com.damonmele.wrestlingmanager.teampro.annual';
const evidence={...config,products:undefined,productID,transactionID:'101',originalTransactionID:'101',appAccountToken:token,
 status:1,snapshotSignedAt:now-1000,expiresAt:now+600000};
const subscription=reconcileSubscription({actor:{userID:owner,confirmed:true,liveSession:true},
 intent:{userID:owner,teamID:team,token,productID,authorized:true},evidence,config,now}).subscription;
const runAs=async(role,fn)=>{await db.exec('set role '+role);try{return await fn();}finally{await db.exec('reset role');}};
const remaining=async()=> (await db.query('select wm_billing.remaining_team_admin($1,$2) as allowed',[team,owner])).rows[0].allowed;
const transition=()=>runAs('service_role',()=>db.query("update private.scoped_deletion_jobs set state='auth' where id=$1",[job]));
try {
 for(const name of ['tests/postgres-fixture.sql','tests/access-fixture.sql','billing-storage-candidate.sql',
  'apple-notification-inbox.sql','team-paid-remainder-storage.sql','billing-access-candidate.sql'])
  await db.exec(await readFile(new URL(name,import.meta.url),'utf8'));
 await db.exec('grant usage on schema private to service_role;grant select,update on private.scoped_deletion_jobs to service_role');
 for(const id of [owner,admin,viewer])await db.query('insert into auth.users(id,confirmed_at) values($1,now())',[id]);
 for(const id of [team,otherTeam])await db.query('insert into public.teams values($1,$2)',[id,organization]);
 await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach'),($1,$3,'head_coach'),($1,$4,'parent_guardian')",[team,owner,admin,viewer]);
 await db.query("insert into private.scoped_deletion_jobs(id,actor_id,state,personal,sealed_at,subject_hash,lease_token,lease_until) values($1,$2,'records',true,now(),encode(sha256(convert_to(($2::uuid)::text,'UTF8')),'hex'),$3,now()+interval '5 minutes')",[job,owner,lease]);
 await check('remaining admin follows current roles, permissions, identity and team deletion state',async()=>{
  assert.equal(await remaining(),true);
  for(const role of ['assistant_coach','manager','parent_guardian','athlete']){
   await db.query("update public.team_memberships set role=$1,permissions='{}' where user_id=$2",[role,admin]);
   assert.equal(await remaining(),false,role);
   await db.query("update public.team_memberships set permissions='{"+'"team_admin":true'+"}' where user_id=$1",[admin]);
   assert.equal(await remaining(),['assistant_coach','manager'].includes(role),role);
  }
  await db.query("update public.team_memberships set role='head_coach' where user_id=$1",[admin]);
  for(const [apply,undo] of [
   ["update public.team_memberships set active=false where user_id=$1","update public.team_memberships set active=true where user_id=$1"],
   ["update auth.users set banned_until=now()+interval '1 day' where id=$1","update auth.users set banned_until=null where id=$1"],
   ["update auth.users set deleted_at=now() where id=$1","update auth.users set deleted_at=null where id=$1"],
   ["insert into private.team_logins(user_id) values($1)","delete from private.team_logins where user_id=$1"],
   ["insert into private.test_minors values($1)","delete from private.test_minors where user_id=$1"],
   ["insert into private.scoped_deletion_jobs(actor_id,state) values($1,'planning')","delete from private.scoped_deletion_jobs where actor_id=$1"]]){
   await db.query(apply,[admin]);assert.equal(await remaining(),false);await db.query(undo,[admin]);assert.equal(await remaining(),true);
  }
  await db.query('update public.team_memberships set active=false where user_id=$1',[admin]);
  await db.query("insert into public.organization_memberships values($1,$2,'organization_admin')",[admin,organization]);
  assert.equal(await remaining(),true);
  await db.query("update private.scoped_deletion_jobs set team_ids=array[$1::uuid] where id=$2",[team,job]);assert.equal(await remaining(),false);
  await db.query("update private.scoped_deletion_jobs set team_ids='{}',organization_ids=array[$1::uuid] where id=$2",[organization,job]);assert.equal(await remaining(),false);
  await db.query("update private.scoped_deletion_jobs set organization_ids='{}' where id=$1",[job]);assert.equal(await remaining(),true);
 });
 await db.query('insert into wm_billing.team_bindings values($1,$2)',[owner,team]);
 await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at) values($1,$2,$3,'team',$4,$5)",[token,owner,productID,team,now]);
 await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,family_owner_id,created_at) values($1,$2,'com.damonmele.wrestlingmanager.familyvideo.monthly','family',$2,$3)",[familyToken,owner,now]);
 await db.query("insert into wm_billing.subscriptions values('Sandbox','101',$1,$2,'team',$3,null,$4)",[token,owner,team,subscription]);
 await db.exec("insert into wm_billing.deliveries(environment,transaction_id,original_id) values('Sandbox','101','101')");
 await db.query('insert into wm_billing.family_coverage values($1,1,$2)',[owner,randomUUID()]);
 for(const t of [token,familyToken])await db.query("insert into wm_billing.notification_inbox(environment,notification_id,original_id,token,evidence) values('Sandbox',$1,'101',$2,$3)",[randomUUID(),t,t===token?evidence:{}]);
 await check('deletion requires a live service lease and failure is atomic',async()=>{
  await db.query("update private.scoped_deletion_jobs set lease_until=now()-interval '1 minute' where id=$1",[job]);
  await assert.rejects(transition(),/LEASE_REQUIRED/);
  assert.equal((await db.query('select count(*)::int as n from wm_billing.subscriptions')).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int as n from wm_billing.team_paid_remainders')).rows[0].n,0);
  await db.query("update private.scoped_deletion_jobs set lease_until=now()+interval '5 minutes' where id=$1",[job]);
  await db.exec("create function wm_billing.test_failure() returns trigger language plpgsql as $$begin raise exception 'synthetic deletion failure';end$$; create trigger test_failure before delete on wm_billing.intents for each row execute function wm_billing.test_failure()");
  await assert.rejects(transition(),/synthetic deletion failure/);
  assert.equal((await db.query('select count(*)::int as n from wm_billing.team_paid_remainders')).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int as n from wm_billing.notification_inbox')).rows[0].n,2);
  await db.exec('drop trigger test_failure on wm_billing.intents;drop function wm_billing.test_failure()');
 });
 await check('personal deletion preserves only paid team time and erases purchaser billing links',async()=>{
  await transition();
  const rows=(await db.query('select * from wm_billing.team_paid_remainders')).rows;assert.equal(rows.length,1);
  assert.equal(Number(rows[0].paid_through),subscription.expiresAt);
  for(const value of [owner,token,familyToken,'originalTransactionID','appAccountToken'])assert.equal(JSON.stringify(rows).includes(value),false);
  for(const table of ['team_bindings','intents','subscriptions','deliveries','family_coverage','notification_inbox'])
   assert.equal((await db.query('select count(*)::int as n from wm_billing.'+table)).rows[0].n,0,table);
  await db.query('delete from auth.users where id=$1',[owner]);
 });
 const actor={userID:viewer,liveSession:true,confirmed:true};
 const access=new SubscriptionAccessService({environment:'Sandbox',clock:()=>now,auth:{currentActor:async()=>actor},
  repository:{accessTransaction:async(_,fn)=>fn({currentActor:async()=>actor,resolveAccess:async(u,t,a,e)=>{
   await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u})]);
   return (await db.query('select wm_billing.resolve_access($1,$2,$3,$4) as result',[u,t,a,e])).rows[0].result;
  }})}});
 await check('remaining team members receive preserved access without billing identity disclosure',async()=>{
  const result=await access.read({}, {teamID:team});assert.equal(result.teamPro,true);assert.equal(result.familyVideo,false);
  assert.deepEqual(Object.keys(result).sort(),['teamID','athleteID','eventID','teamPro','familyVideo','checkedAt'].sort());
  await db.query('update auth.users set banned_until=now()+interval \'1 day\' where id=$1',[admin]);
  assert.equal((await access.read({}, {teamID:team})).teamPro,false);
  await db.query('update auth.users set banned_until=null where id=$1',[admin]);
 });
 const reconcile=createTeamRemainderReconciler({db,config,clock:()=>now});
 await check('refund matching denies different tokens and environments; renewals never extend access',async()=>{
  assert.deepEqual(await reconcile({...evidence,appAccountToken:randomUUID()}),{status:'unknown'});
  await assert.rejects(reconcile({...evidence,environment:'Production'}),/binding/);
  await reconcile({...evidence,expiresAt:now+999999,snapshotSignedAt:now});
  assert.equal(Number((await db.query('select paid_through from wm_billing.team_paid_remainders')).rows[0].paid_through),subscription.expiresAt);
  await reconcile({...evidence,status:5,revokedAt:now,snapshotSignedAt:now});
  assert.equal((await access.read({}, {teamID:team})).teamPro,false);
  await reconcile(evidence);
  await reconcile({...evidence,snapshotSignedAt:now+1});
  assert.equal((await access.read({}, {teamID:team})).teamPro,false);
  await reconcile({...evidence,status:5,revokedAt:now+1,snapshotSignedAt:now+2});
  assert.equal(Number((await db.query('select revoked_at from wm_billing.team_paid_remainders')).rows[0].revoked_at),now);
  const persist=createBillingNotificationPersistence({db,config,clock:()=>now});
  const notification={notificationID:randomUUID(),evidence:{...evidence,status:5,revokedAt:now,snapshotSignedAt:now+2}};
  for(let i=0;i<2;i++)assert.deepEqual(await persist(notification),{notificationID:notification.notificationID,status:'stored'});
  assert.equal((await db.query('select count(*)::int as n from wm_billing.notification_inbox')).rows[0].n,0);
 });
 await check('an acknowledged pending refund survives deletion before the notification worker runs',async()=>{
  const secondOwner=randomUUID(),secondToken=randomUUID(),secondJob=randomUUID(),secondLease=randomUUID();
  const secondEvidence={...evidence,appAccountToken:secondToken,transactionID:'303',originalTransactionID:'303'};
  const s=reconcileSubscription({actor:{userID:secondOwner,confirmed:true,liveSession:true},intent:{userID:secondOwner,teamID:team,token:secondToken,productID,authorized:true},evidence:secondEvidence,config,now}).subscription;
  await db.query('insert into auth.users(id,confirmed_at) values($1,now())',[secondOwner]);
  await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at) values($1,$2,$3,'team',$4,$5)",[secondToken,secondOwner,productID,team,now]);
  await db.query("insert into wm_billing.subscriptions values('Sandbox','303',$1,$2,'team',$3,null,$4)",[secondToken,secondOwner,team,s]);
  const persist=createBillingNotificationPersistence({db,config,clock:()=>now});
  const notice={notificationID:randomUUID(),evidence:{...secondEvidence,status:5,revokedAt:now,snapshotSignedAt:now}};
  assert.equal((await persist(notice)).status,'stored');
  await db.query("insert into private.scoped_deletion_jobs(id,actor_id,state,personal,sealed_at,lease_token,lease_until) values($1,$2,'records',true,now(),$3,now()+interval '5 minutes')",[secondJob,secondOwner,secondLease]);
  await runAs('service_role',()=>db.query("update private.scoped_deletion_jobs set state='auth' where id=$1",[secondJob]));
  const r=(await db.query("select * from wm_billing.team_paid_remainders where binding_hash=wm_billing.remainder_binding('Sandbox','303',$1)",[secondToken])).rows[0];
  assert.equal(Number(r.revoked_at),now);
  assert.equal((await db.query('select count(*)::int as n from wm_billing.notification_inbox')).rows[0].n,0);
  await db.query('delete from wm_billing.team_paid_remainders where binding_hash=$1',[r.binding_hash]);
 });
 await check('expiry cleanup, team deletion and private role restrictions are enforced',async()=>{
  for(const role of ['anon','authenticated','wm_billing_runtime'])await runAs(role,async()=>{
   await assert.rejects(db.query("insert into wm_billing.team_paid_remainders values($1,$2,'Sandbox','team_pro_year',$3,null,$4)",['a'.repeat(64),team,now+1000,now]),/permission/);
   await assert.rejects(db.query('select wm_billing.finalize_deletion($1,$2)',[job,lease]),/permission/);
  });
  for(const sql of ['paid_through=paid_through+1','revoked_at=null','snapshot_signed_at=snapshot_signed_at-1'])
   await runAs('wm_billing_runtime',()=>assert.rejects(db.query('update wm_billing.team_paid_remainders set '+sql),/IMMUTABLE/));
  await db.query('update wm_billing.team_paid_remainders set paid_through=$1',[now-1000]);
  assert.equal(await runAs('wm_billing_runtime',async()=> (await db.query('select wm_billing.purge_paid_remainders() as n')).rows[0].n),1);
  await db.query("insert into wm_billing.team_paid_remainders values($1,$2,'Sandbox','team_pro_year',$3,null,$4)",['a'.repeat(64),otherTeam,now+60000,now]);
  await db.query('delete from public.teams where id=$1',[otherTeam]);
  assert.equal((await db.query('select count(*)::int as n from wm_billing.team_paid_remainders')).rows[0].n,0);
 });
 console.log(`${passed} paid-remainder database scenarios passed; synthetic data only.`);
} catch(error) {console.error(error.message,error.code??'',error.where??'');process.exitCode=1;} finally {await db.close();}
