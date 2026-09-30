import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {fixture} from './helpers/scoped-deletion-db.mjs';
import {planDeletion,validateScope,ScopeError} from '../scripts/scoped-deletion-plan.mjs';
const passed=[],pass=x=>{passed.push(x);console.log('PASS',x);};
const id=()=>randomUUID();
const a=id(),b=id(),child=id(),o1=id(),o2=id(),t1=id(),t2=id(),s1=id(),s2=id(),ap=id(),ath=id(),unclaimedProfile=id(),unclaimed=id(),w=id(),th1=id(),th2=id(),m1=id(),m2=id(),reply=id(),g1=id(),g2=id();
const {db,reader,catalog}=await fixture();
const input=(kind='all',teams=[t1],orgs=[o1])=>({actorId:a,kind,teamIds:teams,organizationIds:orgs});
const plan=scope=>planDeletion({scope,catalog,reader});
import {runScopedDeletion} from '../scripts/scoped-deletion-worker.mjs';
try{
 await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$4,now()),($2,$5,now()),($3,$6,now())',[a,b,child,'a@example.invalid','b@example.invalid','child@example.invalid']);
 await db.query('insert into public.profiles(id,display_name) values($1,$4),($2,$5),($3,$6)',[a,b,child,'Departing adult','Retained adult','Retained child']);
 await db.query('insert into public.organizations(id,name) values($1,$3),($2,$4)',[o1,o2,'Selected organization','Surviving organization']);
 await db.query('insert into public.teams(id,organization_id,name) values($1,$3,$5),($2,$4,$6)',[t1,t2,o1,o2,'Selected team','Surviving team']);
 await db.query('insert into public.seasons(id,team_id,name) values($1,$3,$5),($2,$4,$5)',[s1,s2,t1,t2,'Synthetic season']);
 await db.query('insert into public.athlete_profiles(id) values($1),($2)',[ap,unclaimedProfile]);
 await db.query("insert into public.athletes(id,organization_id,profile_id,first_name,last_name) values($1,$3,$4,'Shared','Child'),($2,$3,$5,'Unclaimed','Athlete')",[ath,unclaimed,o1,ap,unclaimedProfile]);
 await db.query("insert into private.wrestling_profiles(id,user_id,name) values($1,$2,'Departing adult')",[w,a]);
 await db.query("insert into private.wrestling_profiles(athlete_profile_id,name) values($1,'Retained child')",[ap]);
 await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$3,'head_coach'),($2,$3,'assistant_coach'),($1,$4,'manager'),($2,$4,'head_coach')",[t1,t2,a,b]);
 await db.query("insert into public.team_memberships(team_id,user_id,role,athlete_id) values($1,$3,'athlete',$4),($2,$3,'athlete',$4)",[t1,t2,child,ath]);
 await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$3,'organization_admin'),($2,$3,'assistant_coach'),($1,$4,'head_coach'),($2,$4,'organization_admin')",[o1,o2,a,b]);
 await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$3),($2,$3),($1,$4)',[s1,s2,ath,unclaimed]);
 await db.query("insert into public.athlete_guardians(id,athlete_id,guardian_user_id,name,email) values($1,$3,$4,'Departing guardian','a@example.invalid'),($2,$3,$5,'Retained guardian','b@example.invalid')",[g1,g2,ath,a,b]);
 await db.query("insert into public.communication_threads(id,team_id,kind,created_by) values($1,$3,'group',$5),($2,$4,'group',$5)",[th1,th2,t1,t2,a]);
 await db.query("insert into public.communication_messages(id,thread_id,team_id,sender_user_id,body) values($1,$3,$5,$7,'Own selected-team message'),($2,$4,$6,$7,'Own other-team message')",[m1,m2,th1,th2,t1,t2,a]);
 await db.query("insert into public.communication_messages(id,thread_id,team_id,sender_user_id,reply_to_message_id,body) values($1,$2,$3,$4,$5,'Other person reply must stay')",[reply,th2,t2,b,m2]);
 await db.query("insert into public.communication_attachments(message_id,thread_id,team_id,uploader_user_id,storage_path,mime_type,size_bytes) values($1,$2,$3,$4,'synthetic/message.jpg','image/jpeg',100)",[m1,th1,t1,a]);
 await db.query("insert into public.communication_message_audit(message_id,thread_id,team_id,actor_user_id,event_type,body_snapshot) values($1,$2,$3,$4,'created','Own message snapshot')",[m1,th1,t1,a]);
 await db.query("insert into public.audit_log(actor_user_id,action,entity_type,metadata) values($1::uuid,'fixture','profile',jsonb_build_object('user',($1::uuid)::text))",[a]);


 await db.exec(`create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,version text,owner uuid,owner_id text,unique(bucket_id,name));
 grant usage on schema private,auth,public to authenticated,service_role;
 create function private.enforce_team_login_request() returns void language plpgsql as $$begin return;end$$;`);
 const phone=await readFile(new URL('../supabase/migrations/20260930031742_account_deletion_phone_preflight.sql',import.meta.url),'utf8');
 await db.exec(phone.slice(phone.indexOf('create function private.account_deletion_phone_preflight()'),phone.indexOf('create function public.account_deletion_phone_preflight()')));
 await db.exec(await readFile(new URL('./fixtures/scoped-deletion-mutation-triggers.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../supabase/migrations/20260930060258_scoped_deletion_worker.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../supabase/migrations/20260930065511_scoped_deletion_hosted_acceptance.sql',import.meta.url),'utf8'));
 await db.query('update private.scoped_deletion_config set catalog=$1::jsonb,catalog_hash=private.scoped_deletion_schema_hash()',[JSON.stringify(catalog)]);
 const sid=id(),request=id(),receipt='a'.repeat(64);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,a]);
 await db.query("insert into private.account_deletion_phone_testers(user_id,expires_at) values($1,now()+interval '1 day')",[a]);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'authenticated',sub:a,session_id:sid,exp:Math.floor(Date.now()/1000)+3600})]);
 const begin=async(kind='all',teams=[t1],orgs=[o1],rid=request)=>{
  await db.exec('set role authenticated');
  try{return (await db.query("select public.scoped_deletion_begin($1,$2,$3,'delete',$4,$5) result",[kind,teams,orgs,rid,receipt])).rows[0].result;}
  finally{await db.exec('reset role');}
 };
 const service=async(op,job,lease,input={})=>{
  await db.exec('set role service_role');
  try{return (await db.query('select public.scoped_deletion_service($1,$2,$3,$4::jsonb) result',[op,job,lease,JSON.stringify(input)])).rows[0].result;}
  catch(e){if(op==='erase_records')console.error('SERVICE',op,e.message,e.where);throw e;}
  finally{await db.exec('reset role');}
 };
 await assert.rejects(()=>begin(),/DELETION_NOT_ENABLED/);
 await db.exec('update private.scoped_deletion_config set enabled=true');
 await assert.rejects(()=>begin('personal',[],[]),/DELETION_ORGANIZATION_HANDOFF_REQUIRED/);
 await assert.rejects(()=>begin('organization',[],[o1]),/DELETION_LINKED_TEAMS_NOT_SELECTED/);
 const job=await begin();assert.equal(job.state,'planning');assert.deepEqual(await begin(),job);
 await assert.rejects(()=>begin('team',[t1],[],request),/DELETION_REQUEST_MISMATCH/);
 await assert.rejects(()=>begin('all',[t1],[o1],id()),/DELETION_ALREADY_IN_PROGRESS/);
 pass('Actual intake enforces enrollment, disabled defaults, accepted administrator handoff, exact scope and retry identity');
 await assert.rejects(()=>service('claim',job.id,null,{receipt_hash:'b'.repeat(64)}),/DELETION_RECEIPT_REQUIRED/);
 await db.exec('set role authenticated');
 await assert.rejects(()=>db.query("select public.scoped_deletion_service('claim',$1,null,'{}')",[job.id]),/permission denied/);
 await db.exec('reset role');
 pass('Authenticated callers cannot reach service operations or claim another receipt');
 // Populate real relational paths, with an independent unselected file to protect.
 const image=id(),attachment=id(),retainedImage=id();
 await db.query("update public.profiles set photo_path='synthetic/account.jpg' where id=$1",[a]);
 await db.query("insert into storage.objects(id,bucket_id,name,version,owner) values($1,'profile-photos','synthetic/account.jpg','v1',$4),($2,'communication-media','synthetic/message.jpg','v1',$4),($3,'profile-photos','synthetic/retained.jpg','v1',$5)",[image,attachment,retainedImage,a,b]);
 await db.query("update public.profiles set photo_path='synthetic/retained.jpg' where id=$1",[b]);
 await db.query("insert into public.team_staff_profiles(team_id,user_id,display_name,photo_path) values($1,$2,'Retained adult','synthetic/retained.jpg')",[t1,b]);
 const keptBefore=(await db.query('select to_jsonb(p) value from public.profiles p where id<>$1 order by id',[a])).rows;
 let failMedia=true,failAuth=true,mediaCalls=0,authCalls=0,banCalls=0;
 const provider={
  async disableIdentity(actor){assert.equal(actor,a);banCalls++;await db.query("update auth.users set banned_until=now()+interval '100 years' where id=$1",[actor]);},
  async removeObject(bucket,path){mediaCalls++;if(failMedia){failMedia=false;throw Error('Transient provider outage');}await db.query('delete from storage.objects where bucket_id=$1 and name=$2',[bucket,path]);},
  async objectExists(bucket,path){return (await db.query('select 1 from storage.objects where bucket_id=$1 and name=$2',[bucket,path])).rows.length>0;},
  async identityExists(actor){return (await db.query('select 1 from auth.users where id=$1',[actor])).rows.length>0;},
  async deleteIdentity(actor){assert.equal(actor,a);authCalls++;if(failAuth){failAuth=false;throw Error('Transient Auth outage');}await db.query('delete from auth.users where id=$1',[actor]);}
 };
 let result=await runScopedDeletion({service,provider,jobId:job.id,receiptHash:receipt,budgetMs:120000});
 assert.equal(result.state,'media',JSON.stringify(result));assert.equal(result.pending,true);assert.equal(banCalls,1);
 assert.equal((await db.query('select count(*)::int n from auth.sessions where user_id=$1',[a])).rows[0].n,0);
 assert.equal((await db.query('select private.scoped_deletion_access_ok() ok')).rows[0].ok,false);
 await assert.rejects(()=>db.query("insert into public.communication_messages(thread_id,team_id,sender_user_id,body) values($1,$2,$3,'Late write')",[th1,t1,b]),/DELETION_RECORDS_LOCKED/);
 await assert.rejects(()=>db.query("update public.profiles set photo_path='synthetic/account.jpg' where id=$1",[b]),/DELETION_RECORDS_LOCKED/);
 await assert.rejects(()=>db.query("update storage.objects set version='v2' where id=$1",[image]),/DELETION_OBJECT_(LOCKED|ADDRESS_RETIRED)/);
 assert.equal((await db.query('select count(*)::int n from public.profiles')).rows[0].n,3);
 pass('A provider outage leaves records intact, revokes only the departing login and freezes late dependencies and shared-file copies');
 await db.exec('update private.scoped_deletion_jobs set retry_after=null');
 result=await runScopedDeletion({service,provider,jobId:job.id,receiptHash:receipt,budgetMs:120000});
 assert.equal(result.state,'auth',JSON.stringify(result));assert.equal(result.pending,true);
 assert.equal((await db.query('select count(*)::int n from public.profiles where id=$1',[a])).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[a])).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from storage.objects where id=$1',[retainedImage])).rows[0].n,1);
 pass('Files are verified absent before records commit, and an Auth outage preserves the retry job without erasing other users');
 await db.exec('update private.scoped_deletion_jobs set retry_after=null');
 result=await runScopedDeletion({service,provider,jobId:job.id,receiptHash:receipt,budgetMs:120000});
 assert.equal(result.state,'completed',JSON.stringify(result));assert.equal(result.personal,true);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,2);
 assert.deepEqual((await db.query('select to_jsonb(p) value from public.profiles p order by id')).rows,keptBefore);
 assert.deepEqual((await db.query('select id,organization_id from public.athletes order by id')).rows.map(x=>x.organization_id),[null,null]);
 assert.equal((await db.query('select count(*)::int n from public.athlete_profiles')).rows[0].n,2);
 assert.equal((await db.query('select count(*)::int n from public.teams')).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from public.organizations')).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from public.athlete_guardians where id=$1',[g2])).rows[0].n,1);
 assert.equal((await db.query('select reply_to_message_id from public.communication_messages where id=$1',[reply])).rows[0].reply_to_message_id,null);
 assert.equal((await db.query('select count(*)::int n from public.team_memberships where team_id=$1 and user_id=$2',[t2,child])).rows[0].n,1);
 const receiptRow=(await db.query('select actor_id,team_ids,organization_ids from private.scoped_deletion_jobs where id=$1',[job.id])).rows[0];
 assert.deepEqual(receiptRow,{actor_id:null,team_ids:[],organization_ids:[]});
 const oldCalls={mediaCalls,authCalls};
 assert.equal((await runScopedDeletion({service,provider,jobId:job.id,receiptHash:receipt})).state,'completed');
 assert.deepEqual({mediaCalls,authCalls},oldCalls);
 pass('Actual PostgreSQL erasure preserves other identities, an unclaimed athlete, another guardian, another team and a reply; completed retries do no work');
 await writeFile(new URL('../validation/scoped-deletion-service.json',import.meta.url),JSON.stringify({passed,tableCount:catalog.tables.length,realDataChanged:false,limits:'Actual deletion SQL and worker against synthetic PostgreSQL data; injected Storage/Auth providers. Hosted provider and native-device acceptance are still separate gates.'},null,2));
}catch(error){console.error(error.message);if(error.query)console.error(error.query.slice(0,600));process.exitCode=1;}finally{await db.close();}
