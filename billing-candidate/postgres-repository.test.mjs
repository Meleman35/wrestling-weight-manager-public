import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import pg from 'pg';
import {PostgresBillingRepository} from './postgres-repository.mjs';import {SupabaseBillingAuth} from './supabase-billing-auth.mjs';
import {PurchaseIntentService} from './purchase-intent.mjs';import {PurchaseDeliveryService} from './purchase-delivery.mjs';import {proposedProducts} from './subscription-policy.mjs';
const connectionString=process.env.BILLING_TEST_DATABASE_URL;
test('real PostgreSQL transactions, concurrency, permissions and revoked sessions',{skip:!connectionString},async t=>{
 const url=new URL(connectionString);assert.ok(['localhost','127.0.0.1','::1','[::1]'].includes(url.hostname),'Disposable localhost database required');assert.equal(url.pathname,'/billing_test');
 const admin=new pg.Pool({connectionString,max:8});
 const pool=new pg.Pool({connectionString,max:8,options:'-c role=wm_billing_runtime'});
 const user='11111111-1111-4111-8111-111111111111',session='22222222-2222-4222-8222-222222222222',team='33333333-3333-4333-8333-333333333333',other='44444444-4444-4444-8444-444444444444',athlete='55555555-5555-4555-8555-555555555555';
 try{
  await admin.query(fs.readFileSync(new URL('./tests/postgres-fixture.sql',import.meta.url),'utf8'));
  await admin.query(fs.readFileSync(new URL('./billing-storage-candidate.sql',import.meta.url),'utf8'));
  await admin.query('insert into auth.users(id,confirmed_at) values($1,now())',[user]);await admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,user]);
  for(const id of [team,other]){await admin.query('insert into public.teams(id) values($1)',[id]);await admin.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[id,user]);}
  const projectURL='https://vfocpoyexnjsjpxhhyqr.supabase.co',auth=new SupabaseBillingAuth({projectURL,publishableKey:'synthetic',pool,fetchImpl:async()=>({ok:true,json:async()=>({id:user})})});
  const claims={sub:user,session_id:session,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated',iss:projectURL+'/auth/v1'};
  const ctx=await auth.authenticate('Bearer e30.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.c2ln');
  const repository=new PostgresBillingRepository({pool,auth}),intentService=new PurchaseIntentService({auth,repository});
  const productID='com.damonmele.wrestlingmanager.teampro.annual';let token;
  await t.test('concurrent team choices persist exactly one team binding',async()=>{
   const r=await Promise.allSettled([team,other].map(teamID=>intentService.prepare(ctx,{productID,target:{kind:'team',teamID}})));
   assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.equal(r.filter(x=>x.status==='rejected').length,1);
   token=r.find(x=>x.status==='fulfilled').value.appAccountToken;
   const row=(await admin.query('select * from wm_billing.team_bindings')).rows;assert.equal(row.length,1);
  });
  const now=Date.now(),evidence={bundleID:'com.damonmele.wrestlingmanager',environment:'Sandbox',productID,transactionID:'1001',originalTransactionID:'1001',appAccountToken:token,status:1,snapshotSignedAt:now,expiresAt:now+600000};
  const delivery=new PurchaseDeliveryService({auth,repository,apple:{resolve:async()=>({...evidence})},config:{bundleID:evidence.bundleID,environment:'Sandbox',products:proposedProducts}});
  await t.test('duplicate deliveries commit one subscription and one delivery',async()=>{
   const results=await Promise.all(Array.from({length:6},()=>delivery.deliver(ctx,{signedTransaction:'synthetic'})));
   assert.equal(results.every(x=>x.transactionID==='1001'),true);
   assert.equal((await admin.query('select count(*)::int as n from wm_billing.subscriptions')).rows[0].n,1);
   assert.equal((await admin.query('select count(*)::int as n from wm_billing.deliveries')).rows[0].n,1);
  });
  await t.test('transaction rollback removes subscription and intent binding together',async()=>{
   const bound=(await admin.query('select team_id from wm_billing.team_bindings')).rows[0].team_id;
   const newToken=(await intentService.prepare(ctx,{productID,target:{kind:'team',teamID:bound}})).appAccountToken;
   const failing=new PurchaseDeliveryService({auth,repository,apple:{resolve:async()=>({...evidence,appAccountToken:newToken,transactionID:'1002',originalTransactionID:'1002'})},config:delivery.config});
   await admin.query("create function wm_billing.fail_delivery() returns trigger language plpgsql as $$begin if new.transaction_id='1002' then raise exception 'synthetic commit failure';end if;return new;end$$;create trigger fail_delivery before insert on wm_billing.deliveries for each row execute function wm_billing.fail_delivery()");
   await assert.rejects(failing.deliver(ctx,{signedTransaction:'synthetic'}));
   assert.equal((await admin.query("select count(*)::int as n from wm_billing.subscriptions where original_id='1002'")).rows[0].n,0);
   assert.equal((await admin.query('select bound_original_id from wm_billing.intents where token=$1',[newToken])).rows[0].bound_original_id,null);
  });
  await t.test('family intent requires accepted guardian relationship',async()=>{
   const request={productID:'com.damonmele.wrestlingmanager.familyvideo.monthly',target:{kind:'family'}};
   await assert.rejects(intentService.prepare(ctx,request),/family_purchase_forbidden/);
   await admin.query("insert into public.team_memberships(team_id,user_id,athlete_id,role) values($1,$2,$3,'parent_guardian')",[team,user,athlete]);
   await admin.query("insert into public.athlete_guardians values($1,$2,'pending')",[athlete,user]);await assert.rejects(intentService.prepare(ctx,request),/family_purchase_forbidden/);
   await admin.query("update public.athlete_guardians set invitation_status='accepted'");await intentService.prepare(ctx,request);
  });
  await t.test('cancelled unpaid intent releases selection but a paid binding cannot be erased',async()=>{
   await assert.rejects(intentService.abandon(ctx,{appAccountToken:token}),/purchase_already_bound/);
   const user2='66666666-6666-4666-8666-666666666666',session2='77777777-7777-4777-8777-777777777777';
   await admin.query('insert into auth.users(id,confirmed_at) values($1,now())',[user2]);await admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[session2,user2]);
   for(const id of [team,other])await admin.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[id,user2]);
   const auth2=new SupabaseBillingAuth({projectURL,publishableKey:'synthetic',pool,fetchImpl:async()=>({ok:true,json:async()=>({id:user2})})});
   const claims2={...claims,sub:user2,session_id:session2};const ctx2=await auth2.authenticate('Bearer e30.'+Buffer.from(JSON.stringify(claims2)).toString('base64url')+'.c2ln');
   const repo2=new PostgresBillingRepository({pool,auth:auth2}),service2=new PurchaseIntentService({auth:auth2,repository:repo2});
   const first=await service2.prepare(ctx2,{productID,target:{kind:'team',teamID:team}});
   await assert.rejects(intentService.abandon(ctx,{appAccountToken:first.appAccountToken}),/intent_not_owned/);
   await service2.abandon(ctx2,first);assert.equal((await admin.query('select count(*)::int as n from wm_billing.team_bindings where user_id=$1',[user2])).rows[0].n,0);
   await service2.prepare(ctx2,{productID,target:{kind:'team',teamID:other}});
   assert.equal((await admin.query('select team_id from wm_billing.team_bindings where user_id=$1',[user2])).rows[0].team_id,other);
  });
  await t.test('base family coverage allows two unique profile slots only',async()=>{
   await admin.query('insert into wm_billing.family_coverage values($1,1,$2),($1,2,$3)',[user,athlete,other]);
   await assert.rejects(admin.query('insert into wm_billing.family_coverage values($1,3,$2)',[user,team]));
   await assert.rejects(admin.query('update wm_billing.family_coverage set athlete_profile_id=$2 where user_id=$1 and slot=2',[user,athlete]));
  });
  await t.test('deletion freeze and revoked session prevent billing writes',async()=>{
   const bound=(await admin.query('select team_id from wm_billing.team_bindings')).rows[0].team_id,request={productID,target:{kind:'team',teamID:bound}};
   await admin.query("insert into private.scoped_deletion_jobs values($1,'pending')",[user]);await assert.rejects(intentService.prepare(ctx,request),/unauthorized/);
   await admin.query('delete from private.scoped_deletion_jobs');await admin.query('delete from auth.sessions where id=$1',[session]);await assert.rejects(intentService.prepare(ctx,request),/unauthorized/);await assert.rejects(delivery.deliver(ctx,{signedTransaction:'synthetic'}),/unauthorized/);
  });
  await t.test('public app roles cannot read billing or invoke privileged helpers',async()=>{
   for(const role of ['anon','authenticated']){
    const conn=await admin.connect();try{await conn.query('BEGIN');await conn.query('set local role '+role);await assert.rejects(conn.query('select * from wm_billing.intents'));await conn.query('ROLLBACK');await conn.query('BEGIN');await conn.query('set local role '+role);await assert.rejects(conn.query('select wm_billing.current_actor($1,$2,$3)',[user,session,Date.now()+10000]));await conn.query('ROLLBACK');}finally{conn.release();}
   }
  });
 }finally{await pool.end();await admin.end();}
});
