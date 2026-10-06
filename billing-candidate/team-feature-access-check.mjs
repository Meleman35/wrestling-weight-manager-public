import assert from 'node:assert/strict';
import {randomUUID as uuid} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';
import {prepareCoreBillingFixture,fixtureBillingMigration} from './tests/core-billing-fixture.mjs';
import {hasTeamSubscriptionAccess} from './subscription-policy.mjs';
const root=new URL('../',import.meta.url),read=path=>readFile(new URL(path,root),'utf8');
const {db}=await fixture();let checks=0;const pass=s=>{checks++;console.log('PASS '+s);};
const owner=uuid(),coach=uuid(),outsider=uuid(),org=uuid(),team=uuid(),otherTeam=uuid(),season=uuid(),athlete=uuid(),profile=uuid(),token=uuid();
const sessions=new Map([[owner,uuid()],[coach,uuid()],[outsider,uuid()]]),now=Date.now();
const snapshot={environment:'Production',originalTransactionID:'801',transactionID:'801',appAccountToken:token,userID:owner,
 teamID:team,productID:'com.damonmele.wrestlingmanager.teampro.monthly',plan:'team_pro_month',status:1,
 expiresAt:now+3600000,graceExpiresAt:null,revokedAt:null,snapshotSignedAt:now};
const admin=()=>db.exec('reset role');
async function as(user=coach,extra={}){await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:sessions.get(user),role:'authenticated',...extra})]);await db.exec('set role authenticated');}
const plans=async(action,data={})=>(await db.query('select public.practice_plans_request($1,$2) r',[action,{team_id:team,...data}])).rows[0].r;
const stats=async(action,data={})=>(await db.query('select public.wrestler_statistics_request($1,$2) r',[action,{team_id:team,athlete_id:athlete,style:'folkstyle',...data}])).rows[0].r;
async function update(changes){await admin();await db.query('update wm_billing.subscriptions set snapshot=$1 where token=$2',[{...snapshot,...changes},token]);await as();}
try{
 await prepareCoreBillingFixture(db);await db.exec(await fixtureBillingMigration(db));
 await db.exec(await read('billing-candidate/tests/team-feature-relationship-fixture.sql'));
 await db.exec(await read('supabase/migrations/20260930151016_wrestler_statistics_020102.sql'));
 await db.exec(await read('supabase/practice-plans.sql'));
 await db.exec('update private.scoped_deletion_config set catalog_hash=private.scoped_deletion_schema_hash()');
 await db.exec(await read('supabase/migrations/20261005025902_team_pro_feature_access.sql'));
 for(const id of sessions.keys()){
  await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);
  await db.query('insert into public.profiles(id) values($1)',[id]);
  await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sessions.get(id),id]);
 }
 await db.query("insert into public.organizations(id,name) values($1,'Synthetic')",[org]);
 for(const id of [team,otherTeam])await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Synthetic')",[id,org]);
 await db.query("insert into public.seasons(id,team_id,name) values($1,$2,'Synthetic')",[season,team]);
 await db.query('insert into public.athlete_profiles(id) values($1)',[profile]);
 await db.query("insert into public.athletes(id,profile_id,organization_id,first_name,last_name) values($1,$2,$3,'Synthetic','Athlete')",[athlete,profile,org]);
 await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$2)',[season,athlete]);
 for(const id of [owner,coach])await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[team,id]);
 await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[otherTeam,outsider]);
 await as();assert.equal((await plans('context')).covered,false);assert.equal((await stats('context')).covered,false);
 await assert.rejects(()=>plans('list',{month:'2026-10'}),/Team Pro/);await assert.rejects(()=>stats('read'),/Team Pro/);
 await as(coach,{app_metadata:{paid:true,wm_billing_sandbox:{team_ids:[team],expires_at:now+3600000}},user_metadata:{paid:true}});
 assert.equal((await plans('context')).covered,false);
 pass('actual protected operations remain unpaid without verified storage; client metadata cannot grant access');

 await admin();await db.query("insert into wm_billing.intents(token,user_id,product_id,scope,team_id,created_at) values($1,$2,$3,'team',$4,$5)",[token,owner,snapshot.productID,team,now]);
 await db.query("insert into wm_billing.subscriptions values('Production','801',$1,$2,'team',$3,null,$4)",[token,owner,team,snapshot]);
 await as();assert.equal((await plans('context')).covered,true);assert.equal((await stats('context')).covered,true);
 const payload={id:uuid(),event_id:null,revision:0,request_id:uuid(),plan_date:'2026-10-05',start_time:'18:00',target_minutes:60,title:'Synthetic plan',focus:'Technique',notes:'',blocks:[]};
 assert.equal((await plans('save',payload)).saved,true);assert.equal((await plans('read',{id:payload.id})).plan.title,payload.title);assert.deepEqual((await stats('read')).matches,[]);
 await as(outsider);await assert.rejects(()=>plans('read',{id:payload.id}),/coaches|administrators/);await assert.rejects(()=>stats('read'),/private/);
 assert.equal((await plans('context',{team_id:otherTeam})).covered,false);
 pass('stored Team Pro unlocks practice save/read and statistics for the bound team; unrelated teams and accounts stay blocked');

 for(const changes of [{status:2},{status:3},{status:5},{expiresAt:now-1},{revokedAt:now},{status:4,graceExpiresAt:now-1},{snapshotSignedAt:now+120000}]){
  await update(changes);assert.equal((await plans('context')).covered,false,JSON.stringify(changes));
  await assert.rejects(()=>plans('read',{id:payload.id}),/Team Pro/);await assert.rejects(()=>stats('read'),/Team Pro/);
 }
 await update({status:4,expiresAt:now-1,graceExpiresAt:now+3600000});assert.equal((await plans('context')).covered,true);
 await update({});
 pass('refund, expiry, billing retry and invalid future evidence deny each operation; verified grace retains access');

 await admin();
 for(const status of [1,2,3,4,5])for(const expired of [false,true])for(const revoked of [false,true]){
  const s={...snapshot,status,expiresAt:expired?now-1:now+10000,graceExpiresAt:expired?now-1:now+10000,revokedAt:revoked?now:null};
  const actual=(await db.query('select wm_billing.team_snapshot_active($1,$2,$3,$4) a',[s,team,'Production',now])).rows[0].a;
  assert.equal(actual,hasTeamSubscriptionAccess(s,{teamID:team,environment:'Production',now}));
 }
 for(const changes of [{expiresAt:'9999999999999999'},{expiresAt:1.25},{snapshotSignedAt:'bad'},{status:'1'},{plan:'family_video_month'},{teamID:otherTeam},{environment:'Sandbox'}])
  assert.equal((await db.query("select wm_billing.team_snapshot_active($1,$2,'Production',$3) a",[{...snapshot,...changes},team,now])).rows[0].a,false);
 pass('database eligibility matches the server policy across 40 status/expiry/refund cases and rejects malformed or wrong-scope evidence');

 await db.query("update wm_billing.subscriptions set environment='Sandbox',snapshot=$1 where token=$2",[{...snapshot,environment:'Sandbox'},token]);
 await as(coach,{app_metadata:{wm_billing_sandbox:{team_ids:[team],expires_at:now+3600000}}});assert.equal((await plans('context')).covered,false);
 await admin();await db.query('update auth.users set raw_app_meta_data=$1 where id=$2',[{wm_billing_sandbox:{team_ids:[team],expires_at:now+3600000}},coach]);
 await as();assert.equal((await plans('context')).covered,true);
 await as(owner);assert.equal((await plans('context')).covered,false);
 for(const enrollment of [{team_ids:[otherTeam],expires_at:now+3600000},{team_ids:[team],expires_at:now-1},{team_ids:team,expires_at:now+3600000}]){
  await admin();await db.query('update auth.users set raw_app_meta_data=$1 where id=$2',[{wm_billing_sandbox:enrollment},coach]);await as();assert.equal((await plans('context')).covered,false);
 }
 await admin();await db.query("update auth.users set raw_app_meta_data='{}' where id=$1",[coach]);await db.query("update wm_billing.subscriptions set environment='Production',snapshot=$1 where token=$2",[snapshot,token]);
 pass('Sandbox cannot unlock ordinary users; only server-enrolled caller/team pairs work until enrollment expiry');

 for(const who of [owner,coach]){
  await admin();await db.query("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[who]);await as();
  if(who===owner)assert.equal((await plans('context')).covered,false);else await assert.rejects(()=>plans('context'),/personal/);
  await assert.rejects(()=>stats('read'),/personal|Team Pro/);
  await admin();await db.query('update auth.users set banned_until=null where id=$1',[who]);
 }
 await as(coach,{session_id:uuid()});await assert.rejects(()=>stats('read'),/Team Pro/);await assert.rejects(()=>plans('context'),/personal/);
 await admin();await db.query("insert into private.scoped_deletion_jobs(actor_id,subject_hash,request_id,kind,personal,team_ids,organization_ids,receipt_hash,policy_version,catalog_hash,state) values($1,'synthetic',$2,'team',false,$3,'{}',$4,'scoped-deletion-v1','synthetic','planning')",[owner,uuid(),[team],'a'.repeat(64)]);
 await as();assert.equal((await plans('context')).covered,false);await assert.rejects(()=>stats('read'),/Team Pro/);
 await admin();await db.exec("delete from private.scoped_deletion_jobs where subject_hash='synthetic'");
 pass('purchaser/caller bans, stale sessions and pending team deletion suppress paid operations');

 await update({status:5});await admin();
 await db.query("insert into wm_billing.team_paid_remainders values($1,$2,'Production','team_pro_month',$3,null,$4)",['b'.repeat(64),team,now+3600000,now]);
 await as();assert.equal((await plans('context')).covered,true);
 await admin();await db.query('update wm_billing.team_paid_remainders set revoked_at=$1',[now]);await as();assert.equal((await plans('context')).covered,false);
 for(const role of ['anon','authenticated','wm_billing_runtime']){
  await admin();await db.exec('set role '+role);
  await assert.rejects(()=>db.query('select wm_billing.team_feature_covered($1)',[team]),/permission/);
 }
 pass('remaining paid team time is honored and revocation removes it; clients and runtime cannot directly invoke the privileged feature helper');
 console.log(`${checks} protected feature integration scenarios passed; disposable database only.`);
}catch(error){console.error(error.message,error.where??'');process.exitCode=1;}finally{await db.close();}
