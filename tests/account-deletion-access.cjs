'use strict';
// Isolated PostgreSQL semantics with synthetic identities. No project URL, key or network client.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {PGlite} = require('@electric-sql/pglite');
const {createLedger, FLAGS} = require('../scripts/account-deletion-worker.cjs');
const root = path.resolve(__dirname, '..'), db = new PGlite(), ledger = createLedger(db), passed = [];
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const {setup} = require('./helpers/account-deletion-access-fixture.cjs');
const pass = label => { passed.push(label); console.log('PASS', label); };
const policy = 'synthetic-access-v1', hash = 'a'.repeat(64);
const a = randomUUID(), b = randomUUID(), recorder = randomUUID();
const a1 = randomUUID(), a2 = randomUUID(), b1 = randomUUID(), r1 = randomUUID();
const denied = e => e.code === '42501';
const proof = n => Object.fromEntries(FLAGS[n].map(key => [key, true]));
async function owner(sql, args = []) { await db.exec('reset role'); return db.query(sql, args); }
async function ownerExec(sql) { await db.exec('reset role'); return db.exec(sql); }
async function service() { await db.exec('reset role; set role service_role'); }
async function as(user, sid, extra = {}, role = 'authenticated') {
  assert(['authenticated', 'anon', 'service_role'].includes(role));
  await db.exec('reset role; set role ' + role);
  await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false),set_config('request.path','/access_fixture',false)",
    [user || '', JSON.stringify({sub:user, session_id:sid, role, exp:Math.floor(Date.now()/1000)+3600, ...extra})]);
}
const allowed = async () => (await db.query('select private.account_deletion_access_allowed() value')).rows[0].value;
const pre = () => db.query('select public.account_deletion_pre_request()');
const requestPath = p => db.query("select set_config('request.path',$1,false)", [p]);
async function makeJob(user) {
  await owner('update public.account_deletion_settings set fulfillment_enabled=true,policy_version=$1,inventory_sha256=$2', [policy,hash]);
  const receipt = (await owner('insert into public.account_deletion_requests(user_id) values($1) returning id', [user])).rows[0].id;
  await service(); await ledger.enqueue(receipt,policy,hash);
  const job = await ledger.claim(policy,hash); assert.equal(job.id,receipt); return job;
}
(async()=>{
  try {
    await setup(db);
    await db.query('insert into auth.users(id) values($1),($2),($3)',[a,b,recorder]);
    for(const [sid,user] of [[a1,a],[a2,a],[b1,b],[r1,recorder]]) await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,user]);
    await assert.rejects(db.exec(read('scripts/account-deletion-access-draft.sql')),e=>e.code==='55000');
    await db.exec("select set_config('wm.deletion_access_fixture','isolated-test',false)");
    await db.exec(read('scripts/account-deletion-access-draft.sql'));
    assert.equal((await db.query("select current_setting('pgrst.db_pre_request') value")).rows[0].value,'public.enforce_team_login_request');
    assert.equal((await db.query('select fulfillment_enabled from public.account_deletion_settings')).rows[0].fulfillment_enabled,false);
    assert.equal((await db.query('select count(*)::int n from private.account_deletion_jobs')).rows[0].n,0);
    assert.equal((await db.query('select count(*)::int n from auth.sessions')).rows[0].n,4);
    assert(!read('index.html').includes('account_deletion_pre_request'));
    pass('Prototype does not wire the live hook, enable fulfillment, remove sessions or enter the app bundle');

    for(const sid of [a1,a2]) { await as(a,sid); assert.equal(await allowed(),true); await pre(); }
    await as(b,b1); assert.equal(await allowed(),true); await pre();
    pass('Both registered personal sessions and the unrelated account pass the additional guard');

    for(const [user,sid,extra] of [[null,null,{}],[a,null,{}],[a,'not-a-uuid',{}],[a,a1,{sub:b}],[a,b1,{}],
      [a,a1,{role:'anon'}],[a,a1,{exp:0}],[a,a1,{exp:'9999999999'}],[a,a1,{exp:1.5}],[a,a1,{exp:null}]]) {
      await as(user,sid,extra); assert.equal(await allowed(),false); await assert.rejects(pre(),denied);
    }
    await as(a,a1); await db.query("select set_config('request.jwt.claims','{',false)"); assert.equal(await allowed(),false);
    pass('Missing, malformed, mismatched, expired or wrong-role claims fail closed without trusting user metadata');

    await as(a,a1);
    for(const table of ['auth.users','auth.sessions','private.account_deletion_jobs']) await assert.rejects(db.query('select * from '+table),denied);
    await assert.rejects(db.query('select private.account_deletion_access_allowed($1::uuid)',[b]),e=>e.code==='42883');
    await assert.rejects(db.query('update public.account_deletion_settings set fulfillment_enabled=true'),denied);
    await as(null,null,{},'anon'); await assert.rejects(allowed(),denied); await pre();
    await as(null,null,{},'service_role'); await pre();
    pass('Clients cannot inspect private identity/job rows, choose another subject or enable deletion; anonymous routes keep their original guard');

    await owner('delete from auth.sessions where id=$1',[a1]);
    await as(a,a1); assert.equal(await allowed(),false);
    await as(a,a2); assert.equal(await allowed(),true);
    await owner('insert into auth.sessions(id,user_id) values($1,$2)',[a1,a]);
    await owner("update auth.sessions set not_after=now()-interval '1 second' where id=$1",[a1]);
    await as(a,a1); assert.equal(await allowed(),false);
    await owner('update auth.sessions set not_after=null where id=$1',[a1]);
    await as(a,a1); assert.equal(await allowed(),true);
    pass('A removed or expired session is rejected without invalidating a different active session');

    await owner("update auth.users set banned_until=now()+interval '1 day' where id=$1",[a]);
    await as(a,a1); assert.equal(await allowed(),false);
    await owner("update auth.users set banned_until=now()-interval '1 day',deleted_at=now() where id=$1",[a]);
    await as(a,a1); assert.equal(await allowed(),false);
    await owner('update auth.users set banned_until=null,deleted_at=null where id=$1',[a]);
    await as(a,a1); assert.equal(await allowed(),true);
    pass('Banned and soft-deleted identities are denied; unrelated valid identities remain usable');

    let job=await makeJob(a);
    await as(a,a1); assert.equal(await allowed(),true);
    await service(); await assert.rejects(ledger.checkpoint(job,'advance',{}),e=>e.code==='22023');
    job=await ledger.checkpoint(job,'advance',proof(0)); assert.equal(job.phase,1);
    for(const sid of [a1,a2]) { await as(a,sid); assert.equal(await allowed(),false); await assert.rejects(pre(),denied); }
    const a3=randomUUID(); await owner('insert into auth.sessions(id,user_id) values($1,$2)',[a3,a]);
    await as(a,a3,{user_metadata:{bypass_deletion:true,user_id:b},app_metadata:{admin:true}}); assert.equal(await allowed(),false);
    await as(b,b1); assert.equal(await allowed(),true);
    pass('Intake/review alone does not lock an account; advancing approved review denies all its sessions, including a newly issued one');

    await owner('update public.account_deletion_settings set fulfillment_enabled=false');
    await as(a,a1); assert.equal(await allowed(),false);
    await owner("update private.account_deletion_jobs set state='blocked',lease_token=null,lease_until=null where id=$1",[job.id]);
    await as(a,a1); assert.equal(await allowed(),false);
    await owner("update private.account_deletion_jobs set state='retry' where id=$1",[job.id]);
    await as(a,a1); assert.equal(await allowed(),false);
    await owner("update private.account_deletion_jobs set state='blocked' where id=$1",[job.id]);
    pass('Paused fulfillment, blocked jobs and retry state never reopen an already-revoked account');

    const login=randomUUID();
    await owner("insert into private.team_logins values($1,$2,'team_device',true,'ready',1,null,'{\"record_matches\":true}')",[login,recorder]);
    await owner('insert into private.team_login_sessions(session_id,login_id,revision) values($1,$2,1)',[r1,login]);
    await as(recorder,r1); await requestPath('/rpc/video_match_request'); await pre();
    await requestPath('/rpc/send_communication_message'); await assert.rejects(pre(),e=>denied(e)&&/recording only/.test(e.message));
    await owner('update private.team_logins set revision=2 where id=$1',[login]);
    await as(recorder,r1); await requestPath('/rpc/video_match_request'); await assert.rejects(pre(),e=>denied(e)&&/TEAM_LOGIN_REVOKED/.test(e.message));
    await owner('update private.team_logins set revision=1 where id=$1',[login]);
    let recorderJob=await makeJob(recorder); await service(); recorderJob=await ledger.checkpoint(recorderJob,'advance',proof(0));
    await as(recorder,r1); await requestPath('/rpc/video_match_request'); await assert.rejects(pre(),denied);
    pass('The real recorder/session guard still rejects forbidden tools and stale revisions; an allowed recorder route cannot bypass deletion');

    // Integration examples only: these synthetic tables/policies are NOT installed in production.
    await ownerExec(`create table public.access_fixture(id int primary key,user_id uuid,shared boolean not null default false,body text);
      alter table public.access_fixture enable row level security;
      grant select,insert,update,delete on public.access_fixture to authenticated;
      create policy fixture_owner on public.access_fixture for all to authenticated
        using(user_id=auth.uid() or shared) with check(user_id=auth.uid());
      create policy deletion_guard on public.access_fixture as restrictive for all to authenticated
        using((select private.account_deletion_access_allowed())) with check((select private.account_deletion_access_allowed()));
      create table public.no_grant_fixture(id int);
      alter table public.no_grant_fixture enable row level security;
      grant select on public.no_grant_fixture to authenticated;
      create policy deletion_only on public.no_grant_fixture as restrictive for select to authenticated
        using((select private.account_deletion_access_allowed()));
      insert into public.no_grant_fixture values(1);
    `);
    await owner("insert into public.access_fixture values(1,$1,false,'departing'),(2,$2,false,'unrelated'),(3,$1,true,'shared team record')",[a,b]);
    await as(a,a1); assert.deepEqual((await db.query('select id from public.access_fixture')).rows,[]);
    await assert.rejects(db.query('insert into public.access_fixture values(4,$1,false,$2)',[a,'queued offline write']),denied);
    assert.equal((await db.query('update public.access_fixture set body=$1 where id=1 returning id',['old queued edit'])).rows.length,0);
    assert.equal((await db.query('delete from public.access_fixture where id=1 returning id')).rows.length,0);
    await as(b,b1); assert.deepEqual((await db.query('select id from public.access_fixture order by id')).rows.map(r=>r.id),[2,3]);
    await db.query('insert into public.access_fixture values(5,$1,false,$2)',[b,'new allowed work']);
    await assert.rejects(db.query('update public.access_fixture set user_id=$1 where id=2',[a]),denied);
    assert.deepEqual((await db.query('select * from public.no_grant_fixture')).rows,[]);
    pass('Restrictive RLS blocks new reads and queued writes for the departing account without granting extra access or deleting shared records');

    await ownerExec(`create schema storage; create table storage.objects(name text primary key,owner_id uuid);
      alter table storage.objects enable row level security;
      grant usage on schema storage to authenticated;
      grant select,insert,update,delete on storage.objects to authenticated;
      create policy fixture_owner on storage.objects for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
      create policy deletion_guard on storage.objects as restrictive for all to authenticated
        using((select private.account_deletion_access_allowed())) with check((select private.account_deletion_access_allowed()));`);
    await owner("insert into storage.objects values('departing/test',$1),('other/test',$2)",[a,b]);
    await as(a,a1); assert.deepEqual((await db.query('select * from storage.objects')).rows,[]);
    await assert.rejects(db.query("insert into storage.objects values('departing/new',$1)",[a]),denied);
    await as(b,b1); assert.deepEqual((await db.query('select name from storage.objects')).rows,[{name:'other/test'}]);
    pass('The restrictive check also works without a pre-request hook in a synthetic Storage-policy fixture, not a physical-media test');

    await ownerExec(`create table private.privileged_fixture_calls(id int generated always as identity);
      create function public.privileged_fixture() returns int language plpgsql security definer set search_path='' as $$
      declare n int; begin insert into private.privileged_fixture_calls default values; select count(*)::int into n from public.access_fixture; return n; end $$;
      revoke all on function public.privileged_fixture() from public,anon;
      grant execute on function public.privileged_fixture() to authenticated;`);
    await as(a,a1); assert.equal((await db.query('select public.privileged_fixture() n')).rows[0].n,4);
    await assert.rejects(db.exec('begin; select public.account_deletion_pre_request(); select public.privileged_fixture(); commit;'),denied);
    await db.exec('rollback');
    assert.equal((await owner('select count(*)::int n from private.privileged_fixture_calls')).rows[0].n,1);
    pass('Negative control proves unguarded definers bypass RLS; the composed request check prevents their body running on that guarded route');

    const def=(await owner("select prosecdef,proconfig,pronargs from pg_proc where oid='private.account_deletion_access_allowed()'::regprocedure")).rows[0];
    assert.equal(def.prosecdef,true); assert.equal(def.pronargs,0); assert(def.proconfig.includes('search_path=""'));
    for(const signature of ['private.require_account_deletion_access()','public.account_deletion_pre_request()']) {
      assert.equal((await owner('select prosecdef from pg_proc where oid=$1::regprocedure',[signature])).rows[0].prosecdef,false);
    }
    await as(b,b1);
    await db.exec('reset role; begin; alter table private.account_deletion_jobs rename column subject_id to unavailable_subject; set local role authenticated;');
    await assert.rejects(allowed(),e=>e.code==='42703'); await db.exec('rollback');
    await as(b,b1); assert.equal(await allowed(),true);
    pass('Only the argument-free private reader is a definer; missing backend schema errors do not turn into successful access');

    await owner('delete from auth.users where id=$1',[a]);
    await owner("update public.account_deletion_requests set user_id=null,status='completed',completed_at=now() where id=$1",[job.id]);
    await owner("update private.account_deletion_jobs set subject_id=null,phase=8,state='completed',lease_token=null,lease_until=null,completed_at=now() where id=$1",[job.id]);
    await as(a,a1); assert.equal(await allowed(),false);
    await as(b,b1); assert.equal(await allowed(),true);
    assert.equal((await db.query('select id from public.access_fixture where id=3')).rows.length,1);
    pass('Old tokens remain denied after synthetic Auth removal and job unlinking while another account retains the shared record');

    fs.mkdirSync(path.join(root,'validation'),{recursive:true});
    fs.writeFileSync(path.join(root,'validation/account-deletion-access.json'),JSON.stringify({passed,
      engine:'PGlite; synthetic Auth/data fixtures, actual deletion draft schemas and existing managed-login guard bodies',
      productionChanged:false, mounted:false, globalRevocationProven:false,
      limitations:['No JWT cryptographic verification or hosted gateway in this fixture','No live Storage/Realtime/Edge coverage','No in-flight request drain, sign-in/refresh revocation, native or physical-device proof']},null,2));
  } finally { await db.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
