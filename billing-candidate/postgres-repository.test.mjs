import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import pg from 'pg';
import {PostgresBillingRepository} from './postgres-repository.mjs';import {SupabaseBillingAuth} from './supabase-billing-auth.mjs';
import {PurchaseIntentService} from './purchase-intent.mjs';import {PurchaseDeliveryService} from './purchase-delivery.mjs';import {proposedProducts} from './subscription-policy.mjs';
import {SubscriptionAccessService} from './subscription-access.mjs';
import {FamilyCoverageService} from './family-coverage.mjs';
import {createBillingHandler} from './billing-handler.mjs';
const connectionString=process.env.BILLING_TEST_DATABASE_URL;
test('real PostgreSQL transactions, concurrency, permissions and revoked sessions',{skip:!connectionString},async t=>{
 const url=new URL(connectionString);assert.ok(['localhost','127.0.0.1','::1','[::1]'].includes(url.hostname),'Disposable localhost database required');assert.equal(url.pathname,'/billing_test');
 const admin=new pg.Pool({connectionString,max:8});
 const pool=new pg.Pool({connectionString,max:8,options:'-c role=wm_billing_runtime'});
 const user='11111111-1111-4111-8111-111111111111',session='22222222-2222-4222-8222-222222222222',team='33333333-3333-4333-8333-333333333333',other='44444444-4444-4444-8444-444444444444',athlete='55555555-5555-4555-8555-555555555555';
 try{
  await admin.query(fs.readFileSync(new URL('./tests/postgres-fixture.sql',import.meta.url),'utf8'));
  await admin.query(fs.readFileSync(new URL('./tests/access-fixture.sql',import.meta.url),'utf8'));
  await admin.query(fs.readFileSync(new URL('./billing-storage-candidate.sql',import.meta.url),'utf8'));
  await admin.query(fs.readFileSync(new URL('./apple-notification-inbox.sql',import.meta.url),'utf8'));
  await admin.query(fs.readFileSync(new URL('./team-paid-remainder-storage.sql',import.meta.url),'utf8'));
  await admin.query(fs.readFileSync(new URL('./billing-access-candidate.sql',import.meta.url),'utf8'));
  await admin.query('insert into auth.users(id,confirmed_at) values($1,now())',[user]);await admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,user]);
  for(const id of [team,other]){await admin.query('insert into public.teams(id) values($1)',[id]);await admin.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[id,user]);}
  const projectURL='https://vfocpoyexnjsjpxhhyqr.supabase.co',auth=new SupabaseBillingAuth({projectURL,publishableKey:'synthetic',pool,fetchImpl:async()=>({ok:true,json:async()=>({id:user})})});
  const claims={sub:user,session_id:session,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated',iss:projectURL+'/auth/v1'};
  const ctx=await auth.authenticate('Bearer e30.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.c2ln');
  const repository=new PostgresBillingRepository({pool,auth}),intentService=new PurchaseIntentService({auth,repository});
  const productID='com.damonmele.wrestlingmanager.teampro.annual';let token;
  await t.test('a deleting team cannot start a purchase through another administrator',async()=>{
   const deletionActor='aaaaaaaa-1111-4111-8111-111111111111';
   try {
    await admin.query("insert into private.scoped_deletion_jobs(actor_id,state,team_ids) values($1,'pending',array[$2::uuid])",[deletionActor,team]);
    await assert.rejects(intentService.prepare(ctx,{productID,target:{kind:'team',teamID:team}}),/team_purchase_forbidden/);
    assert.equal((await admin.query('select count(*)::int as n from wm_billing.intents')).rows[0].n,0);
   } finally { await admin.query('delete from private.scoped_deletion_jobs where actor_id=$1',[deletionActor]); }
  });
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
  await t.test('database-backed access uses canonical profiles and current event permissions',async t=>{
   const parent='88888888-8888-4888-8888-888888888888',parentSession='99999999-9999-4999-8999-999999999999';
   const profile='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',copy='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
   const season='cccccccc-cccc-4ccc-8ccc-cccccccccccc',season2='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
   const event='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',event2='ffffffff-ffff-4fff-8fff-ffffffffffff';
   await admin.query('insert into auth.users(id,confirmed_at) values($1,now());',[parent]);
   await admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[parentSession,parent]);
   await admin.query('insert into public.athlete_profiles values($1)',[profile]);
   await admin.query('insert into public.athletes values($1,$3),($2,$3)',[athlete,copy,profile]);
   await admin.query('insert into private.video_pilot_control values(true,true,false)');
   for(const [teamID,athleteID,seasonID,eventID] of [[team,athlete,season,event],[other,copy,season2,event2]]){
    await admin.query('insert into public.seasons values($1,$2,true)',[seasonID,teamID]);
    await admin.query('insert into public.roster_memberships values($1,$2,true)',[seasonID,athleteID]);
    await admin.query('insert into public.team_events values($1,$2,$3)',[eventID,teamID,seasonID]);
    await admin.query("insert into public.team_memberships(team_id,user_id,athlete_id,role) values($1,$2,$3,'parent_guardian')",[teamID,parent,athleteID]);
    await admin.query("insert into public.athlete_guardians values($1,$2,'accepted')",[athleteID,parent]);
    await admin.query('insert into private.video_pilot_grants values($1,$2,null,now()+interval \'1 day\')',[teamID,user]);
    await admin.query('insert into private.video_athlete_permissions values($1,$2,$3,true)',[teamID,athleteID,parent]);
    await admin.query('insert into private.video_event_settings values($1,$2,true)',[teamID,eventID]);
   }
   const parentAuth=new SupabaseBillingAuth({projectURL,publishableKey:'synthetic',pool,fetchImpl:async()=>({ok:true,json:async()=>({id:parent})})});
   const parentContext=await parentAuth.authenticate('Bearer e30.'+Buffer.from(JSON.stringify({...claims,sub:parent,session_id:parentSession})).toString('base64url')+'.c2ln');
   const parentRepo=new PostgresBillingRepository({pool,auth:parentAuth});
   const familyProduct='com.damonmele.wrestlingmanager.familyvideo.monthly';
   const familyIntent=await new PurchaseIntentService({auth:parentAuth,repository:parentRepo}).prepare(parentContext,{productID:familyProduct,target:{kind:'family'}});
   await new PurchaseDeliveryService({auth:parentAuth,repository:parentRepo,apple:{resolve:async()=>({...evidence,productID:familyProduct,appAccountToken:familyIntent.appAccountToken,transactionID:'2001',originalTransactionID:'2001'})},config:delivery.config}).deliver(parentContext,{signedTransaction:'synthetic'});
   const coverage=new FamilyCoverageService({auth:parentAuth,repository:parentRepo});
   assert.deepEqual(await coverage.select(parentContext,{athleteIDs:[athlete]}),{selectedCount:1});
   const access=new SubscriptionAccessService({auth,repository,environment:'Sandbox'});
   const target={teamID:team,athleteID:athlete,eventID:event};
   const bound=(await admin.query('select team_id from wm_billing.team_bindings where user_id=$1',[user])).rows[0].team_id;
   await t.test('another member cannot receive Team Pro through an unavailable purchaser',async()=>{
    const viewer=new SubscriptionAccessService({auth:parentAuth,repository:parentRepo,environment:'Sandbox'});
    assert.equal((await viewer.read(parentContext,{teamID:bound})).teamPro,true);
    for(const column of ['deleted_at','banned_until']) {
     try {
      await admin.query(`update auth.users set ${column}=now()+interval '1 day' where id=$1`,[user]);
      assert.equal((await viewer.read(parentContext,{teamID:bound})).teamPro,false);
     } finally { await admin.query(`update auth.users set ${column}=null where id=$1`,[user]); }
    }
    try {
     await admin.query("insert into private.scoped_deletion_jobs(actor_id,state) values($1,'pending')",[user]);
     assert.equal((await viewer.read(parentContext,{teamID:bound})).teamPro,false);
    } finally { await admin.query('delete from private.scoped_deletion_jobs where actor_id=$1',[user]); }
    assert.equal((await viewer.read(parentContext,{teamID:bound})).teamPro,true);
   });
   await t.test('family choices are canonical, selected, and disappear after guardian revocation',async()=>{
    const options=await coverage.options(parentContext,{});
    assert.equal(options.athletes.length,1);assert.equal(options.athletes[0].profile_id,profile);assert.equal(options.athletes[0].selected,true);
    assert.ok([athlete,copy].includes(options.athletes[0].athlete_id));
    assert.deepEqual(Object.keys(options.athletes[0]).sort(),['athlete_id','display_name','profile_id','selected']);
    await assert.rejects(coverage.options(parentContext,{userID:user}),/invalid_request/);
    try{
     await admin.query("update public.athlete_guardians set invitation_status='pending' where guardian_user_id=$1",[parent]);
     assert.deepEqual(await coverage.options(parentContext,{}),{athletes:[]});
    }finally{await admin.query("update public.athlete_guardians set invitation_status='accepted' where guardian_user_id=$1",[parent]);}
   });
   await t.test('family selection validates canonical identity and rolls back invalid replacements',async()=>{
    for(const athleteIDs of [[athlete,copy],[profile]])await assert.rejects(coverage.select(parentContext,{athleteIDs}));
    assert.deepEqual((await admin.query('select athlete_profile_id,slot from wm_billing.family_coverage where user_id=$1',[parent])).rows,[{athlete_profile_id:profile,slot:1}]);
    await assert.rejects(coverage.select(parentContext,{athleteIDs:[athlete,copy,profile]}),/invalid_request/);
    try{await admin.query("update public.athlete_guardians set invitation_status='pending' where guardian_user_id=$1",[parent]);await assert.rejects(coverage.select(parentContext,{athleteIDs:[athlete]}),/family_coverage_forbidden/);}
    finally{await admin.query("update public.athlete_guardians set invitation_status='accepted' where guardian_user_id=$1",[parent]);}
    // Clearing and concurrent replacements are serialized; no partial slots survive.
    assert.deepEqual(await coverage.select(parentContext,{athleteIDs:[]}),{selectedCount:0});
    assert.equal((await access.read(ctx,target)).familyVideo,false);
    const results=await Promise.all([athlete,copy].map(id=>coverage.select(parentContext,{athleteIDs:[id]})));
    assert.deepEqual(results,[{selectedCount:1},{selectedCount:1}]);
    assert.equal((await admin.query('select count(*)::int as n from wm_billing.family_coverage where user_id=$1',[parent])).rows[0].n,1);
   });
   await t.test('one selected profile covers both roster records without granting another team Team Pro',async()=>{
    for(const [teamID,athleteID,eventID] of [[team,athlete,event],[other,copy,event2]]){
     const result=await access.read(ctx,{teamID,athleteID,eventID});
     assert.equal(result.familyVideo,true);assert.equal(result.teamPro,teamID===bound);
     assert.deepEqual(Object.keys(result).sort(),['teamID','athleteID','eventID','teamPro','familyVideo','checkedAt'].sort());
     assert.equal(JSON.stringify(result).includes(parent),false);assert.equal(JSON.stringify(result).includes(profile),false);
    }
   });
   await t.test('event, consent and pilot gates remain required',async()=>{
    assert.equal((await access.read(ctx,{teamID:team,athleteID:athlete})).familyVideo,false);
    assert.equal((await access.read(ctx,{...target,eventID:event2})).familyVideo,false);
    for(const [table,column] of [['video_event_settings','recording_permitted'],['video_athlete_permissions','recording_allowed'],['video_pilot_control','enabled']]){
     try{await admin.query(`update private.${table} set ${column}=false`);assert.equal((await access.read(ctx,target)).familyVideo,false);}
     finally{await admin.query(`update private.${table} set ${column}=true`);}
    }
   });
   await t.test('an accepted guardian, current membership and selected profile are all required',async()=>{
    try{await admin.query("update public.athlete_guardians set invitation_status='pending' where guardian_user_id=$1",[parent]);assert.equal((await access.read(ctx,target)).familyVideo,false);}
    finally{await admin.query("update public.athlete_guardians set invitation_status='accepted' where guardian_user_id=$1",[parent]);}
    try{await admin.query('update public.team_memberships set active=false where user_id=$1',[parent]);assert.equal((await access.read(ctx,target)).familyVideo,false);}
    finally{await admin.query('update public.team_memberships set active=true where user_id=$1',[parent]);}
    try{await admin.query('update wm_billing.family_coverage set athlete_profile_id=$1 where user_id=$2',[team,parent]);assert.equal((await access.read(ctx,target)).familyVideo,false);}
    finally{await admin.query('update wm_billing.family_coverage set athlete_profile_id=$1 where user_id=$2',[profile,parent]);}
   });
   await t.test('subscription ownership alone does not authorize a guardian to record',async()=>{
    const parentAccess=new SubscriptionAccessService({auth:parentAuth,repository:parentRepo,environment:'Sandbox'});
    assert.equal((await parentAccess.read(parentContext,target)).familyVideo,false);
   });
   await t.test('refund, expiry, environment and deletion status are enforced from stored data',async()=>{
    const original=(await admin.query("select snapshot from wm_billing.subscriptions where original_id='2001'")).rows[0].snapshot;
    for(const patch of [{revokedAt:Date.now()},{expiresAt:Date.now()-1000}]){
     try{await admin.query("update wm_billing.subscriptions set snapshot=$1 where original_id='2001'",[{...original,...patch}]);assert.equal((await access.read(ctx,target)).familyVideo,false);}
     finally{await admin.query("update wm_billing.subscriptions set snapshot=$1 where original_id='2001'",[original]);}
    }
    const production=new SubscriptionAccessService({auth,repository,environment:'Production'});
    assert.equal((await production.read(ctx,target)).familyVideo,false);assert.equal((await production.read(ctx,target)).teamPro,false);
    try{await admin.query("insert into private.scoped_deletion_jobs(actor_id,state) values($1,'pending')",[parent]);assert.equal((await access.read(ctx,target)).familyVideo,false);}
    finally{await admin.query('delete from private.scoped_deletion_jobs where actor_id=$1',[parent]);}
    try{await admin.query("insert into private.scoped_deletion_jobs(actor_id,state,team_ids) values($1,'pending',array[$2::uuid])",[parent,team]);await assert.rejects(access.read(ctx,target),/access_forbidden/);}
    finally{await admin.query('delete from private.scoped_deletion_jobs where actor_id=$1',[parent]);}
   });
   await t.test('HTTP access action authenticates, denies unrelated teams and exposes no billing rows',async()=>{
    const handler=createBillingHandler({enabled:true,auth,access});
    const request=data=>new Request('https://backend.invalid/billing',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer e30.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.c2ln'},body:JSON.stringify({action:'access',data})});
    let response=await handler(request(target));assert.equal(response.status,200);assert.equal((await response.json()).familyVideo,true);
    assert.equal(response.headers.get('Cache-Control'),'no-store');
    response=await handler(request({teamID:profile}));assert.equal(response.status,403);assert.deepEqual(await response.json(),{error:'access_not_authorized'});
    assert.equal((await handler(request({...target,paid:true}))).status,400);
   });
   await t.test('access transaction holds the deletion actor lock and live session row lock',async()=>{
    await repository.accessTransaction({userID:user},async tx=>{
     await tx.currentActor(ctx);
     const connection=await admin.connect();
     try{
      await connection.query('BEGIN');await connection.query("set local lock_timeout='100ms'");
      assert.equal((await connection.query('select pg_try_advisory_xact_lock(hashtextextended($1,91347)) as locked',[user])).rows[0].locked,false);
      await assert.rejects(connection.query('delete from auth.sessions where id=$1',[session]),e=>e.code==='55P03');
     }finally{await connection.query('ROLLBACK');connection.release();}
    });
   });
  });
  await t.test('every billing write holds the same actor lock as deletion intake',async()=>{
   const choices=[
    callback=>repository.intentTransaction({userID:user,scope:'team'},callback),
    callback=>repository.abandonTransaction({userID:user,token},callback),
    callback=>repository.transaction({userID:user,environment:'Sandbox',originalTransactionID:'1001',token},callback)
   ];
   for(const transact of choices)await transact(async tx=>{
    await tx.currentActor(ctx);
    const connection=await admin.connect();
    try{
     await connection.query('BEGIN');
     assert.equal((await connection.query('select pg_try_advisory_xact_lock(hashtextextended($1,91347)) as locked',[user])).rows[0].locked,false);
    }finally{await connection.query('ROLLBACK');connection.release();}
   });
  });
  await t.test('deletion freeze and revoked session prevent billing writes',async()=>{
   const bound=(await admin.query('select team_id from wm_billing.team_bindings')).rows[0].team_id,request={productID,target:{kind:'team',teamID:bound}};
   await admin.query("insert into private.scoped_deletion_jobs(actor_id,state) values($1,'pending')",[user]);await assert.rejects(intentService.prepare(ctx,request),/unauthorized/);
   await admin.query('delete from private.scoped_deletion_jobs');await admin.query('delete from auth.sessions where id=$1',[session]);await assert.rejects(intentService.prepare(ctx,request),/unauthorized/);await assert.rejects(delivery.deliver(ctx,{signedTransaction:'synthetic'}),/unauthorized/);
   await assert.rejects(new SubscriptionAccessService({auth,repository,environment:'Sandbox'}).read(ctx,{teamID:bound}),/unauthorized/);
  });
  await t.test('public app roles cannot read billing or invoke privileged helpers',async()=>{
   for(const role of ['anon','authenticated']){
    const conn=await admin.connect();try{await conn.query('BEGIN');await conn.query('set local role '+role);await assert.rejects(conn.query('select * from wm_billing.intents'));await conn.query('ROLLBACK');await conn.query('BEGIN');await conn.query('set local role '+role);await assert.rejects(conn.query('select wm_billing.current_actor($1,$2,$3)',[user,session,Date.now()+10000]));await conn.query('ROLLBACK');}finally{conn.release();}
   }
  });
 }finally{await pool.end();await admin.end();}
});
