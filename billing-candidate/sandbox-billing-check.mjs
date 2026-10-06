import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';
import {prepareCoreBillingFixture,fixtureBillingMigration} from './tests/core-billing-fixture.mjs';
import {SandboxBillingAuth,SandboxBillingRepository} from './sandbox-billing-ports.mjs';
import {createBillingHandler} from './billing-handler.mjs';
import {PurchaseIntentService} from './purchase-intent.mjs';
import {PurchaseDeliveryService} from './purchase-delivery.mjs';
import {SubscriptionAccessService} from './subscription-access.mjs';
import {FamilyCoverageService} from './family-coverage.mjs';
import {readApplePublicConfiguration} from './apple-server-config.mjs';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const {db}=await fixture();let checks=0;const pass=s=>{checks++;console.log('PASS '+s);};
const user=uuid(),otherUser=uuid(),session=uuid(),otherSession=uuid(),org=uuid(),team=uuid(),otherTeam=uuid(),now=Date.now();
const productID='com.damonmele.wrestlingmanager.teampro.monthly',config=readApplePublicConfiguration('Sandbox');
const pool={connect:async()=>({query:(...args)=>db.query(...args),release(){}})};
const projectURL='https://vfocpoyexnjsjpxhhyqr.supabase.co';
const bearer=(actor=user,sid=session,extra={})=>'Bearer e30.'+Buffer.from(JSON.stringify({sub:actor,session_id:sid,exp:Math.floor(now/1000)+3600,iss:projectURL+'/auth/v1',aud:'authenticated',role:'authenticated',...extra})).toString('base64url')+'.c2ln';
const auth=new SandboxBillingAuth({pool,projectURL,publishableKey:'synthetic',fetchImpl:async(_,options)=>({ok:true,json:async()=>({id:JSON.parse(Buffer.from(options.headers.Authorization.split('.')[1],'base64url')).sub})})});
const repository=new SandboxBillingRepository({pool,auth});
let evidence,onResolve;
const handler=createBillingHandler({enabled:true,purchaseEnvironment:'Sandbox',auth,intents:new PurchaseIntentService({auth,repository}),delivery:new PurchaseDeliveryService({auth,repository,config,apple:{resolve:async()=>{await onResolve?.();return evidence;}}}),access:new SubscriptionAccessService({auth,repository,environment:'Sandbox'}),coverage:new FamilyCoverageService({auth,repository})});
async function call(action,data={},authorization=bearer()){
 await db.exec('set role wm_billing_runtime');
 try{return await handler(new Request('https://backend.invalid/billing',{method:'POST',headers:{'Content-Type':'application/json',Authorization:authorization},body:JSON.stringify({action,data})}));}
 finally{await db.exec('reset role');}
}
async function enroll(value={team_ids:[team],expires_at:now+3600000}){await db.exec('reset role');await db.query('update auth.users set raw_app_meta_data=$1 where id=$2',[value?{wm_billing_sandbox:value}:{},user]);}
try{
 await prepareCoreBillingFixture(db);await db.exec(await fixtureBillingMigration(db));
 await db.exec('create function wm_billing.notification_deployment_ready() returns boolean language sql as $$select false$$');
 const migration=await read('supabase/migrations/20261005040311_sandbox_billing_enrollment.sql');
 await assert.rejects(db.exec(migration),/BILLING_SANDBOX_REVIEW_REQUIRED/);await db.exec('rollback');
 await db.exec('create or replace function wm_billing.notification_deployment_ready() returns boolean language sql as $$select true$$');await db.exec(migration);
 for(const role of ['anon','authenticated','service_role']){await db.exec('set role '+role);await assert.rejects(db.query('select wm_billing.sandbox_team_enrolled(null)'),/permission/);await db.exec('reset role');}
 pass('migration requires reviewed notification readiness and exposes enrollment only to the restricted runtime');
 for(const [id,sid] of [[user,session],[otherUser,otherSession]]){
  await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,id]);await db.query('insert into public.profiles(id) values($1)',[id]);
 }
 await db.query("insert into public.organizations(id,name) values($1,'Synthetic')",[org]);
 for(const id of [team,otherTeam]){await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Synthetic')",[id,org]);await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[id,user]);}
 for(const value of [null,{team_ids:[team],expires_at:now-1},{team_ids:[team],expires_at:String(now+3600000)},{team_ids:'wrong',expires_at:now+3600000},{team_ids:[uuid()],expires_at:now+3600000}]){await enroll(value);assert.equal((await call('capabilities')).status,401);}
 await enroll(null);assert.equal((await call('capabilities',{},bearer(user,session,{app_metadata:{wm_billing_sandbox:{team_ids:[team],expires_at:now+3600000}}}))).status,401);
 await enroll();const caps=await call('capabilities');assert.equal(caps.status,200);assert.deepEqual(await caps.json(),{ready:true,productIDs:['com.damonmele.wrestlingmanager.teampro.annual',productID],environment:'Sandbox'});
 assert.equal((await call('capabilities',{},bearer(otherUser,otherSession))).status,401);
 pass('only current server-managed enrollment enables Sandbox capabilities; malformed, expired, forged JWT and other-user enrollment fail');
 assert.equal((await call('prepare',{productID,target:{kind:'team',teamID:otherTeam}})).status,403);
 assert.equal((await call('prepare',{productID:'com.damonmele.wrestlingmanager.familyvideo.monthly',target:{kind:'family'}})).status,400);
 assert.equal((await call('coverage-options')).status,403);
 const prepared=await call('prepare',{productID,target:{kind:'team',teamID:team}});assert.equal(prepared.status,200);const {appAccountToken}=await prepared.json();
 assert.equal((await db.query('select count(*)::int n from wm_billing.intents')).rows[0].n,1);
 pass('prepare permits only the enrolled team and Team Pro; unauthorized team and Family Video create no intent');
 evidence={...config,transactionID:'801',originalTransactionID:'801',productID,purchasedProductID:productID,appAccountToken,status:1,expiresAt:now+3600000,revokedAt:null,graceExpiresAt:null,snapshotSignedAt:now};
 const saved=await call('deliver',{signedTransaction:'synthetic.signed.input'});assert.equal(saved.status,200);assert.deepEqual(await saved.json(),{transactionID:'801',originalTransactionID:'801'});
 const access=await call('access',{teamID:team});assert.equal(access.status,200);assert.equal((await access.json()).teamPro,true);
 assert.equal((await call('access',{teamID:otherTeam})).status,401);
 evidence={...evidence,environment:'Production'};assert.equal((await call('deliver',{signedTransaction:'synthetic.signed.input'})).status,401);
 assert.equal((await db.query('select count(*)::int n from wm_billing.subscriptions')).rows[0].n,1);
 pass('actual delivery/access services persist only Sandbox evidence for the original enrolled team; Production evidence cannot change the ledger');
 evidence={...evidence,environment:'Sandbox',snapshotSignedAt:now+1,status:5,revokedAt:now};
 onResolve=async()=>{await enroll(null);await db.exec('set role wm_billing_runtime');};
 assert.equal((await call('deliver',{signedTransaction:'synthetic.signed.input'})).status,401);
 assert.equal((await db.query('select snapshot->>\'status\' s from wm_billing.subscriptions')).rows[0].s,'1');onResolve=null;
 await enroll({team_ids:[otherTeam],expires_at:now+3600000});assert.equal((await call('deliver',{signedTransaction:'synthetic.signed.input'})).status,401);
 await enroll();assert.equal((await call('deliver',{signedTransaction:'synthetic.signed.input'})).status,200);assert.equal((await (await call('access',{teamID:team})).json()).teamPro,false);
 pass('enrollment is rechecked after Apple awaits and against stored restore bindings; verified refund removes access after re-enrollment');
 assert.equal((await call('capabilities',{},bearer(user,uuid()))).status,401);
 await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[user]);assert.equal((await call('capabilities')).status,401);await db.query('update auth.users set banned_until=null where id=$1',[user]);
 await db.query('update public.team_memberships set active=false where user_id=$1',[user]);assert.equal((await call('capabilities')).status,401);
 pass('revoked sessions, banned accounts and lost team membership cannot activate sandbox purchases');
 console.log(`${checks} sandbox billing database scenarios passed; synthetic Auth/Apple providers only.`);
}catch(error){console.error(error.message,error.where??'',error.stack);process.exitCode=1;}finally{await db.close();}
