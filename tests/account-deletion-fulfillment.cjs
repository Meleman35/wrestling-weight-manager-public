'use strict';
const {PGlite} = require('@electric-sql/pglite');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {createLedger,createWorker,DeletionError,FLAGS} = require('../scripts/account-deletion-worker.cjs');
const {createSupabaseAdapters} = require('../scripts/account-deletion-supabase-adapters.cjs');
const root = path.resolve(__dirname,'..'), checks=[];
const pass = label => {checks.push(label);console.log('PASS',label);};
const sql = name => fs.readFileSync(path.join(root,'supabase/migrations',name),'utf8');
const proof = phase => Object.fromEntries(FLAGS[phase].map(k=>[k,true]));
const policy='synthetic-v1', hash='a'.repeat(64), db=new PGlite();
const ledger=createLedger(db), a=randomUUID(),b=randomUUID(),c=randomUUID(),d=randomUUID(),child=randomUUID(),team=randomUUID();
async function owner(query,args=[]) {await db.exec('reset role');return db.query(query,args);}
async function service() {await db.exec('reset role; set role service_role');}
async function makeRequest(subject) {
  await owner('insert into auth.users(id) values($1) on conflict do nothing',[subject]);
  const r=(await owner('insert into public.account_deletion_requests(user_id) values($1) returning id',[subject])).rows[0].id;
  await service();await ledger.enqueue(r,policy,hash);return r;
}
async function due(id) {await owner("update private.account_deletion_jobs set next_attempt_at=now()-interval '1 second' where id=$1",[id]);await service();}
const count = async (table,clause='',args=[]) => (await owner(`select count(*)::int n from ${table} ${clause}`,args)).rows[0].n;
(async()=>{
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create schema auth;create schema private;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth,public to authenticated,anon,service_role;
    grant select,delete on auth.users to service_role;
    create table public.teams(id uuid primary key);
    create table public.athletes(id uuid primary key);
    create table public.team_memberships(id uuid primary key,team_id uuid references public.teams,user_id uuid references auth.users on delete cascade);
    create table public.communication_threads(id uuid primary key);
    create table public.athlete_guardians(id uuid primary key,athlete_id uuid references public.athletes on delete cascade,guardian_user_id uuid references auth.users on delete set null);
    create table public.guardian_invitations(id uuid primary key);
    create table private.wrestling_profiles(id uuid primary key);
    create table private.synthetic_personal_records(user_id uuid references auth.users on delete restrict,body text);
    grant select,delete on private.synthetic_personal_records to service_role;
  `);
  await db.exec(sql('20260929114400_parent_browser_approval.sql').split('create function private.parent_browser_verification_valid')[0]);
  await db.exec(sql('20260929123507_quiet_conversation_reviewers.sql').split('create function private.conversation_review_admin')[0]);
  await db.exec(sql('20260929052714_account_deletion_intake_draft.sql'));
  await db.exec(sql('20260929190649_account_deletion_fulfillment_draft.sql'));
  await db.query('insert into auth.users values($1),($2),($3),($4)',[a,b,c,d]);
  await db.query('insert into public.teams values($1)',[team]);
  await db.query('insert into public.athletes values($1)',[child]);
  await db.query('insert into private.wrestling_profiles values($1)',[child]);
  const guardians=[randomUUID(),randomUUID(),randomUUID()];
  for(let i=0;i<3;i++) {
    await db.query('insert into public.athlete_guardians values($1,$2,$3)',[guardians[i],child,[a,b,c][i]]);
    await db.query(`insert into private.parent_browser_verifications(guardian_id,athlete_id,profile_id,team_id,email,birth_date,verified_by)
      values($1,$2,$2,$3,'synthetic@example.invalid','2010-01-01',$4)`,[guardians[i],child,team,i===2?a:d]);
    await db.query(`insert into private.parent_browser_permissions(guardian_id,mode,verification_at,notice_version)
      values($1,'teen_managed',now(),'teen-profile-v1')`,[guardians[i]]);
    await db.query(`insert into private.parent_browser_links(token_hash,guardian_id,email,purpose,expires_at)
      values($1,$2,'synthetic@example.invalid','manage',now()+interval '1 day')`,[String(i+1).repeat(64),guardians[i]]);
  }
  for(const [reviewer,approver] of [[a,d],[b,a],[c,d]]) {
    const member=randomUUID();await db.query('insert into public.team_memberships values($1,$2,$3)',[member,team,reviewer]);
    await db.query(`insert into private.conversation_reviewers(team_id,user_id,membership_id,role_key,approved_by,accepted_at)
      values($1,$2,$3,'team_mom',$4,now())`,[team,reviewer,member,approver]);
  }
  await db.query("insert into private.synthetic_personal_records values($1,'erase me'),($2,'preserve me')",[a,b]);
  const req=(await db.query('insert into public.account_deletion_requests(user_id) values($1) returning id',[a])).rows[0].id;
  await service();
  await assert.rejects(ledger.enqueue(req,policy,hash),e=>e.code==='55000');
  assert.equal(await ledger.claim(policy,hash),null);
  await owner('update public.account_deletion_settings set fulfillment_enabled=true,policy_version=$1,inventory_sha256=$2',[policy,hash]);
  for(const role of ['anon','authenticated']) {
    await db.exec('reset role;set role '+role);
    await assert.rejects(ledger.enqueue(req,policy,hash),e=>e.code==='42501');
    await assert.rejects(db.query('select * from private.account_deletion_jobs'),e=>e.code==='42501');
  }
  await service();
  await assert.rejects(ledger.enqueue(req,'wrong',hash),e=>e.code==='55000');
  assert.equal(await ledger.enqueue(req,policy,hash),req);
  assert.equal(await ledger.enqueue(req,policy,hash),req);
  let job=await ledger.claim(policy,hash);
  assert.equal(job.subject_id,a);assert.equal(await ledger.claim(policy,hash),null);
  await assert.rejects(ledger.checkpoint({...job,phase:7},'advance',proof(7)),e=>e.code==='40001');
  await assert.rejects(ledger.checkpoint(job,'advance',{}),e=>e.code==='22023');
  pass('Default-off release gate, private privileges, account binding, idempotent queue and phase checks');

  const stale={...job};
  await owner("update private.account_deletion_jobs set lease_until=now()-interval '1 second' where id=$1",[req]);await service();
  job=await ledger.claim(policy,hash);
  assert.notEqual(job.lease_token,stale.lease_token);
  await assert.rejects(ledger.checkpoint(stale,'advance',proof(0)),e=>e.code==='40001');
  job=await ledger.checkpoint(job,'advance',proof(0));
  await ledger.checkpoint(job,'revoke_related_access');await ledger.checkpoint(job,'revoke_related_access');
  assert.equal(await count('private.conversation_reviewers'),1);
  assert.equal(await count('private.conversation_reviewers','where user_id=$1',[c]),1);
  assert.equal(await count('private.parent_browser_permissions',"where mode='revoked'"),2);
  assert.equal(await count('private.parent_browser_links','where revoked_at is not null'),2);
  assert.equal(await count('private.parent_browser_verifications','where guardian_id=$1',[guardians[1]]),1);
  assert.equal(await count('public.athletes'),1);assert.equal(await count('public.athlete_guardians'),3);
  assert.equal(await count('private.parent_browser_settings'),1);assert.equal(await count('private.conversation_review_settings'),1);
  await service();job=await ledger.checkpoint(job,'yield');
  pass('Expired workers are fenced; actual reviewer/parent capability cleanup preserves child, other guardian and unrelated reviewer');

  let mediaFails=true,authCalls=0,confirmCalls=0,recordCalls=0;
  const objects=new Set(['personal/photo.jpg']);
  const adapters={
    schemaFingerprint:async()=>hash,
    review:async()=>proof(0),revoke:async()=>proof(1),
    inventory:async scope=>({...proof(2),objects:[{subject_id:scope.subjectId,disposition:'erase_personal_content',provider:'supabase',bucket:'photos',key:'personal/photo.jpg'}]}),
    objects:{supabase:async(scope,o)=>{
      objects.delete(o.object_key); // Simulate success followed by a lost acknowledgement.
      if(mediaFails){mediaFails=false;throw new DeletionError('provider_unavailable',true);}
      return {absent:!objects.has(o.object_key)};
    }},
    eraseRecords:async scope=>{recordCalls++;await db.query('delete from private.synthetic_personal_records where user_id=$1',[scope.subjectId]);return proof(4);},
    eraseAuth:async scope=>{authCalls++;await db.query('delete from auth.users where id=$1',[scope.subjectId]);return proof(5);},
    verify:async()=>proof(6),
    confirm:async()=>{confirmCalls++;return proof(7);}
  };
  const worker=createWorker({ledger,adapters,policy,inventoryHash:hash});
  assert.equal((await worker.runOne()).state,'retry');
  assert.equal(authCalls,0);assert.equal(recordCalls,0);assert.equal(confirmCalls,0);
  assert.equal(await count('auth.users','where id=$1',[a]),1);
  assert.equal(await count('private.account_deletion_objects','where removed_at is null'),1);
  await service();assert.equal((await worker.runOne()).state,'idle');
  pass('Storage lost acknowledgements retain durable manifests, apply backoff and block records/Auth/completion');

  await due(req);assert.equal((await worker.runOne()).state,'completed');
  assert.equal(authCalls,1);assert.equal(recordCalls,1);assert.equal(confirmCalls,1);
  assert.equal(await count('auth.users','where id=$1',[a]),0);
  assert.equal(await count('auth.users','where id=$1',[b]),1);
  assert.equal(await count('private.synthetic_personal_records','where user_id=$1',[b]),1);
  assert.equal(await count('public.athletes'),1);
  assert.equal(await count('private.account_deletion_objects'),0);
  const receipt=(await owner('select * from public.account_deletion_requests where id=$1',[req])).rows[0];
  assert.equal(receipt.status,'completed');assert.equal(receipt.user_id,null);
  assert.equal((await owner('select subject_id from private.account_deletion_jobs where id=$1',[req])).rows[0].subject_id,null);
  await service();assert.equal((await worker.runOne()).state,'idle');
  pass('Retry completes only after all phases; completion removes manifest paths and subject linkage while preserving unrelated synthetic records');

  const changed=await makeRequest(randomUUID());
  assert.equal((await createWorker({ledger,adapters:{...adapters,schemaFingerprint:async()=>'b'.repeat(64)},policy,inventoryHash:hash}).runOne()).state,'blocked');
  assert.equal((await owner('select last_error_code from private.account_deletion_jobs where id=$1',[changed])).rows[0].last_error_code,'schema_changed');
  await service();assert.equal((await worker.runOne()).state,'idle');
  pass('Schema drift blocks automatic processing without discarding the request or deadline');

  const foreign=await makeRequest(randomUUID());
  const badInventory={...adapters,inventory:async()=>({...proof(2),objects:[{subject_id:b,disposition:'erase_personal_content',provider:'supabase',bucket:'photos',key:'other/photo'}]})};
  assert.equal((await createWorker({ledger,adapters:badInventory,policy,inventoryHash:hash}).runOne()).state,'blocked');
  assert.equal(await count('private.account_deletion_objects','where job_id=$1',[foreign]),0);
  pass('A foreign-account media manifest is rejected atomically before any object removal');

  const pending=await makeRequest(randomUUID());
  let deliveries=0;
  const confirmAdapters={...adapters,inventory:async()=>({...proof(2),objects:[]}),confirm:async()=>{
    deliveries++;if(deliveries===1)throw new DeletionError('provider_unavailable',true);return proof(7);
  }};
  const finalWorker=createWorker({ledger,adapters:confirmAdapters,policy,inventoryHash:hash});
  assert.equal((await finalWorker.runOne()).state,'retry');
  assert.equal((await owner('select status from public.account_deletion_requests where id=$1',[pending])).rows[0].status,'processing');
  const authBefore=authCalls;await due(pending);assert.equal((await finalWorker.runOne()).state,'completed');assert.equal(authCalls,authBefore);
  pass('Notification failure stays pending after Auth removal; retry resumes confirmation without repeating completed phases');

  const unrevoked=await makeRequest(randomUUID());
  const authCount=authCalls;
  const denied=createWorker({ledger,adapters:{...adapters,revoke:async()=>({...proof(1),stale_tokens_blocked:false})},policy,inventoryHash:hash});
  assert.equal((await denied.runOne()).state,'blocked');assert.equal(authCalls,authCount);
  assert.equal((await owner('select phase from private.account_deletion_jobs where id=$1',[unrevoked])).rows[0].phase,1);
  pass('Missing stale-token revocation proof blocks erasure; this checks the gate, not production JWT coverage');

  const residue=await makeRequest(randomUUID());
  const notificationCount=confirmCalls;
  const residueWorker=createWorker({ledger,adapters:{...adapters,inventory:async()=>({...proof(2),objects:[]}),verify:async()=>({...proof(6),personal_records_absent:false})},policy,inventoryHash:hash});
  assert.equal((await residueWorker.runOne()).state,'blocked');assert.equal(confirmCalls,notificationCount);
  assert.equal((await owner('select status from public.account_deletion_requests where id=$1',[residue])).rows[0].status,'processing');
  pass('Residual personal data prevents completion and confirmation even after Auth deletion');

  const budget=await makeRequest(randomUUID());
  const shortWorker=createWorker({ledger,adapters,policy,inventoryHash:hash,maxActions:1});
  assert.equal((await shortWorker.runOne()).state,'retry');
  await owner('update public.account_deletion_settings set fulfillment_enabled=false');await service();
  assert.equal((await worker.runOne()).state,'idle');
  const privateFunctions=(await owner(`select prosecdef,proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname like 'account_deletion_%'`)).rows;
  assert(privateFunctions.every(x=>!x.prosecdef));
  assert.throws(()=>createWorker({ledger,adapters:{},policy,inventoryHash:hash}),/Missing deletion adapter/);
  pass('Bounded work yields safely; pause prevents new claims; worker functions are invokers and missing adapters cannot run');

  let physical=0,deletedUser=false;
  const sdk={storage:{from:bucket=>({remove:async keys=>{assert.equal(bucket,'photos');assert.deepEqual(keys,['exact/key']);physical++;return {error:null};}})},auth:{admin:{
    getUserById:async id=>deletedUser?{error:{status:404,code:'user_not_found'}}:{data:{user:{id}}},
    deleteUser:async(id,soft)=>{assert.equal(id,b);assert.equal(soft,false);deletedUser=true;return {error:null};}
  }}};
  const real=createSupabaseAdapters({admin:sdk,objectExists:async()=>false});
  assert.deepEqual(await real.removeObject({subjectId:b},{bucket:'photos',object_key:'exact/key'}),{absent:true});assert.equal(physical,1);
  assert.deepEqual(await real.eraseAuth({subjectId:b}),{auth_absent:true});
  assert.deepEqual(await real.eraseAuth({subjectId:b}),{auth_absent:true});
  sdk.auth.admin.getUserById=async()=>({error:{status:403,code:'forbidden'}});
  await assert.rejects(real.eraseAuth({subjectId:b}),e=>e.code==='provider_unavailable');
  const retained=createSupabaseAdapters({admin:sdk,objectExists:async()=>true});
  await assert.rejects(retained.removeObject({subjectId:b},{bucket:'photos',object_key:'exact/key'}),e=>e.code==='verification_failed');
  pass('SDK contracts use exact Storage API objects and hard Auth deletion; ambiguous/forbidden responses never count as absence');

  fs.writeFileSync(path.join(root,'validation/account-deletion-fulfillment.json'),JSON.stringify({
    environment:'Local PGlite with production reviewer/parent table definitions; synthetic Auth/record/provider adapters. No production mutations.',
    limits:'Does not prove production schema erasure, global stale-JWT denial, device cleanup, provider delivery, backup policy or legal retention.',checks
  },null,2)+'\n');
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>db.close());
