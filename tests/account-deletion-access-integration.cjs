'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {PGlite} = require('@electric-sql/pglite');
const {setup} = require('./helpers/account-deletion-access-fixture.cjs');
const {installIsolatedAccessIntegration:install,scope,POLICY} = require('../scripts/account-deletion-access-integration.cjs');
const {createLedger,FLAGS} = require('../scripts/account-deletion-worker.cjs');
const db = new PGlite(), passed = [], root = path.resolve(__dirname,'..');
const a=randomUUID(),b=randomUUID(),a1=randomUUID(),a2=randomUUID(),b1=randomUUID();
const pass = name => {passed.push(name);console.log('PASS',name);};
const denied = e => e.code==='42501';
const owner = async(sql,args=[])=>{await db.exec('reset role');return db.query(sql,args);};
async function as(user,sid){
  await db.exec('reset role; set role authenticated');
  await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false),set_config('request.path','/weigh_ins',false)",
    [user,JSON.stringify({sub:user,session_id:sid,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})]);
}
const countGuards=async()=>Number((await owner('select count(*) n from pg_policy where polname=$1',[POLICY])).rows[0].n);
const hook=async()=>{
  const rows=(await db.query("select to_json(setconfig) settings from pg_db_role_setting where setrole=(select oid from pg_roles where rolname='authenticator') and setdatabase=0")).rows;
  return rows[0].settings.find(s=>s.startsWith('pgrst.db_pre_request=')).split('=')[1];
};
async function rest(sql,args=[]){
  // SQL route harness reads the installed hook. This is not a hosted JWT gateway.
  assert.equal(await hook(),'public.account_deletion_pre_request');
  await db.query('select public.account_deletion_pre_request()');
  return db.query(sql,args);
}
async function advance(user){
  await owner("update public.account_deletion_settings set fulfillment_enabled=true,policy_version='integration-fixture',inventory_sha256=$1",['b'.repeat(64)]);
  const id=(await owner('insert into public.account_deletion_requests(user_id) values($1) returning id',[user])).rows[0].id;
  await db.exec('reset role; set role service_role');
  const ledger=createLedger(db);await ledger.enqueue(id,'integration-fixture','b'.repeat(64));
  let job=await ledger.claim('integration-fixture','b'.repeat(64));
  assert.equal(job.id,id);
  // Synthetic review acceptance only; never reported as verified real erasure evidence.
  job=await ledger.checkpoint(job,'advance',Object.fromEntries(FLAGS[0].map(k=>[k,true])));
  assert.equal(job.phase,1);return job;
}
(async()=>{try{
  await setup(db);
  await assert.rejects(install(db),/isolated test database/);
  await db.exec("select set_config('wm.deletion_access_fixture','isolated-test',false)");
  await db.exec(fs.readFileSync(path.join(root,'scripts/account-deletion-access-draft.sql'),'utf8'));
  await db.exec("create role authenticator; alter role authenticator set pgrst.db_pre_request='public.enforce_team_login_request'");
  // Catalog-name fixtures exercise installation across the real reviewed scope.
  // Unrelated table shapes are minimal: this is NOT a complete production-schema copy.
  for(const name of scope.publicTables){
    if(!(await db.query('select to_regclass($1)::text value',['public.'+name])).rows[0].value){
      await db.exec(`create table public."${name}"(id int primary key,user_id uuid,shared boolean not null default false,body text)`);
    }
    await db.exec(`alter table public."${name}" enable row level security; grant select on public."${name}" to authenticated`);
  }
  await db.exec(`grant insert,update,delete on public.weigh_ins to authenticated;
    create policy weight_owner on public.weigh_ins for all to authenticated
      using(user_id=auth.uid() or shared) with check(user_id=auth.uid());
    create schema storage;create schema realtime;
    grant usage on schema storage,realtime to authenticated;`);
  for(const [schema,names] of [['storage',scope.storageTables],['realtime',scope.realtimeTables]]){
    for(const name of names){
      await db.exec(`create table ${schema}."${name}"(id int primary key,user_id uuid,body text);
        alter table ${schema}."${name}" enable row level security;
        grant select,insert,update,delete on ${schema}."${name}" to authenticated;`);
      if(schema==='storage')await db.exec(`create policy owner_policy on ${schema}."${name}" for all to authenticated
        using(user_id=auth.uid()) with check(user_id=auth.uid())`);
    }
  }
  for(const name of scope.publicInvokerViews){
    await db.exec(`create view public."${name}" with (security_invoker=true) as select * from public.weigh_ins;
      grant select on public."${name}" to authenticated`);
  }
  for(const user of [a,b])await db.query('insert into auth.users(id) values($1)',[user]);
  for(const [sid,user] of [[a1,a],[a2,a],[b1,b]])await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,user]);
  await db.query("insert into public.weigh_ins values(1,$1,false,'personal'),(2,$2,false,'unrelated'),(3,$1,true,'team history')",[a,b]);
  for(const name of scope.storageTables)await db.query(`insert into storage."${name}" values(1,$1,'departing'),(2,$2,'unrelated')`,[a,b]);
  await db.exec(`create table private.test_privileged_calls(id int generated always as identity);create function public.test_privileged_rpc() returns boolean language plpgsql security definer set search_path='' as $$begin insert into private.test_privileged_calls default values;return true;end$$;
    revoke all on function public.test_privileged_rpc() from public,anon;grant execute on function public.test_privileged_rpc() to authenticated;
    create table public.unreviewed(id int);grant select(id) on public.unreviewed to authenticated`);
  await assert.rejects(install(db),/public tables/);assert.equal(await countGuards(),0);
  await db.exec('drop table public.unreviewed');
  await db.exec('alter view public.roster_dashboard set(security_invoker=false)');
  await assert.rejects(install(db),/Owner-executed view/);assert.equal(await countGuards(),0);
  await db.exec('alter view public.roster_dashboard set(security_invoker=true)');
  await db.exec('alter table public.weigh_ins disable row level security');
  await assert.rejects(install(db),/Missing RLS target/);assert.equal(await countGuards(),0);
  await db.exec('alter table public.weigh_ins enable row level security');
  await db.exec("alter role authenticator set pgrst.db_pre_request='public.some_other_guard'");
  await assert.rejects(install(db),/hook configuration changed/);assert.equal(await countGuards(),0);
  await db.exec("alter role authenticator set pgrst.db_pre_request='public.enforce_team_login_request'");
  pass('Missing isolation, new column-granted tables, owner views, missing RLS and unexpected hooks stop installation before changes');

  let writes=0;
  await assert.rejects(install({query:(...args)=>db.query(...args),exec:sql=>{
    if(sql.startsWith('create policy')&&++writes===7)throw Error('Injected interrupted installation');
    return db.exec(sql);
  }}),/interrupted installation/);
  assert.equal(await countGuards(),0);assert.equal(await hook(),'public.enforce_team_login_request');
  const originalPolicies=(await db.query('select polrelid::regclass::text relation,polname,pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) check_expr from pg_policy order by 1,2')).rows;
  const outcome=await install(db);assert.equal(outcome.policyCount,82);assert.equal(outcome.globalRevocationProven,false);
  assert.equal(await countGuards(),82);assert.equal(await hook(),'public.account_deletion_pre_request');
  assert.equal((await db.query('select fulfillment_enabled from public.account_deletion_settings')).rows[0].fulfillment_enabled,false);
  assert.deepEqual((await db.query('select polrelid::regclass::text relation,polname,pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) check_expr from pg_policy where polname<>$1 order by 1,2',[POLICY])).rows,originalPolicies);
  await assert.rejects(install(db),/already exists/);assert.equal(await countGuards(),82);
  pass('Atomic install adds 82 restrictive guards, retains every existing policy, composes the hook, and leaves fulfillment disabled');

  for(const sid of [a1,a2]){
    await as(a,sid);assert.equal((await rest('select public.account_deletion_check_access() value')).rows[0].value,true);
    assert.deepEqual((await db.query('select id from public.weigh_ins order by id')).rows.map(r=>r.id),[1,3]);
  }
  await as(b,b1);assert.deepEqual((await db.query('select id from public.latest_effective_weigh_ins order by id')).rows.map(r=>r.id),[2,3]);
  assert.deepEqual((await db.query('select * from realtime.messages')).rows,[]);
  await assert.rejects(db.query('insert into realtime.messages values(1,$1,$2)',[b,'no permissive policy']),denied);
  pass('Two active sessions retain authorized reads; invoker views retain row filtering and the new policy grants no new Realtime access');

  const job=await advance(a);
  for(const sid of [a1,a2]){
    await as(a,sid);await assert.rejects(rest('select public.test_privileged_rpc()'),denied);
    for(const query of ['select * from public.weigh_ins','select * from public.latest_effective_weigh_ins'])assert.deepEqual((await db.query(query)).rows,[]);
    await assert.rejects(db.query("insert into public.weigh_ins values(9,$1,false,'queued insert')",[a]),denied);
    assert.deepEqual((await db.query("update public.weigh_ins set body='queued update' where id=1 returning id")).rows,[]);
    assert.deepEqual((await db.query('delete from public.weigh_ins where id=1 returning id')).rows,[]);
    for(const name of scope.storageTables){
      assert.deepEqual((await db.query(`select * from storage."${name}"`)).rows,[]);
      await assert.rejects(db.query(`insert into storage."${name}" values(9,$1,'queued upload')`,[a]),denied);
    }
  }
  assert.equal((await owner('select count(*)::int n from private.test_privileged_calls')).rows[0].n,0);
  await owner("update private.account_deletion_jobs set state='blocked',lease_token=null,lease_until=null where id=$1",[job.id]);
  await owner('update public.account_deletion_settings set fulfillment_enabled=false');
  await as(a,a1);await assert.rejects(rest('select 1'),denied);
  await as(b,b1);assert.deepEqual((await rest('select id from public.weigh_ins order by id')).rows.map(r=>r.id),[2,3]);
  await db.query("insert into public.weigh_ins values(4,$1,false,'still active')",[b]);
  await assert.rejects(db.query('update public.weigh_ins set user_id=$1 where id=2',[a]),denied);
  for(const name of scope.storageTables)assert.deepEqual((await db.query(`select id from storage."${name}"`)).rows,[{id:2}]);
  pass('Deletion cutoff blocks both old sessions, queued CRUD, invoker-view reads and Storage/multipart rows while preserving the other account and shared history');

  // Wire the actual Edge handler through the installed SQL guard; all other HTTP is fake.
  const {createHandler:member}=await import('../supabase/functions/send-member-invitation/handler.ts');
  const {createHandler:organization}=await import('../supabase/functions/send-organization-invitation/handler.ts');
  const {accountAccessAllowed}=await import('../supabase/functions/_shared/account-access.ts');
  const invitationId=randomUUID(),requestId=randomUUID(),orgId=randomUUID();
  const env=k=>({SUPABASE_URL:'https://synthetic.invalid',SUPABASE_ANON_KEY:'fake-anon',SUPABASE_SERVICE_ROLE_KEY:'fake-service',RESEND_API_KEY:'fake-email'}[k]);
  async function edgeRun(kind,user,sid,{revokeAt,broken,role='athlete'}={}){
    let checks=0;const calls=[];
    const deps={env,fetch:async(url,o)=>{
      calls.push(url);const data=JSON.parse(o.body);
      if(url.endsWith('/account_deletion_check_access')){
        checks++;assert.equal(o.headers.Authorization,'Bearer original-user-token');assert.equal(o.headers.apikey,'fake-anon');
        if(checks===revokeAt)await owner("update auth.users set banned_until=now()+interval '1 hour' where id=$1",[user]);
        if(broken)return new Response('not available',{status:503});
        await as(user,sid);
        try{return new Response(JSON.stringify((await rest('select public.account_deletion_check_access() value')).rows[0].value));}
        catch(e){if(!denied(e))throw e;return new Response('{}',{status:403});}
      }
      if(url.endsWith('/invitation_email_context'))return Response.json({id:invitationId,request_id:requestId,email:'recipient@example.invalid',role,name:'Recipient',team_name:'Team'});
      if(url.endsWith('/organization_leadership_invites'))return Response.json({id:invitationId,request_id:requestId,email:'recipient@example.invalid',organization_name:'Organization',access:{access_role:'board',title:'Member'}});
      if(url.endsWith('/parent_browser_service'))return Response.json(data.p_action==='email_mode'?{enabled:true}:{ok:true,email:'recipient@example.invalid'});
      if(url.includes('/auth/'))return Response.json({hashed_token:'synthetic-hash',email_otp:'123456',verification_type:'invite'});
      if(url==='https://api.resend.com/emails')return Response.json({id:'synthetic-email'});
      throw Error('Unexpected synthetic request');
    }};
    const body=kind==='member'?{token:(role==='athlete'?'WMWA-':'WMWG-')+'a'.repeat(48),request_id:requestId}:{token:'WMO-'+'a'.repeat(64),id:invitationId,request_id:requestId,organization_id:orgId};
    const response=await (kind==='member'?member:organization)(deps)(new Request('https://edge.invalid',{method:'POST',headers:{Authorization:'Bearer original-user-token'},body:JSON.stringify(body)}));
    return {response,calls};
  }
  for(const kind of ['member','organization']){
    const blocked=await edgeRun(kind,a,a1);assert.equal(blocked.response.status,403);
    assert(!blocked.calls.some(url=>url.includes('/auth/')||url.includes('resend.com')||url.endsWith('/parent_browser_service')));
    const good=await edgeRun(kind,b,b1);assert.equal(good.response.status,200);
    assert.equal(good.calls.filter(url=>url.includes('resend.com')).length,1);
    const unavailable=await edgeRun(kind,b,b1,{broken:true});assert.equal(unavailable.response.status,403);
    assert(!unavailable.calls.some(url=>url.includes('resend.com')));
  }
  for(const role of ['athlete','parent_guardian']){
    for(const revokeAt of [1,2,3]){
      await owner('update auth.users set banned_until=null where id=$1',[b]);
      const result=await edgeRun('member',b,b1,{revokeAt,role});
      assert.notEqual(result.response.status,200);assert(!result.calls.some(url=>url.includes('resend.com')));
      if(revokeAt<=2)assert(!result.calls.some(url=>url.includes('/auth/')));
    }
  }
  await owner('update auth.users set banned_until=null where id=$1',[b]);
  for(const body of ['false','"true"','{}','null','invalid'])assert.equal(await accountAccessAllowed({fetch:async()=>new Response(body)},'https://synthetic.invalid','fake','Bearer fake'),false);
  assert.equal(await accountAccessAllowed({fetch:async()=>{throw Error('timeout');}},'https://synthetic.invalid','fake','Bearer fake'),false);
  pass('Actual invitation handlers use the installed SQL check and stop before later Auth/capability/email actions on revocation or backend failure');

  await owner('delete from auth.users where id=$1',[a]);
  await owner("update private.account_deletion_jobs set subject_id=null where id=$1",[job.id]);
  await as(a,a2);await assert.rejects(rest('select 1'),denied);
  await as(b,b1);assert.equal((await rest('select public.account_deletion_check_access() value')).rows[0].value,true);
  assert.equal((await db.query('select id from public.weigh_ins where id=3')).rows.length,1);
  pass('Removed identity stays denied after job unlinking and shared records remain accessible to the other authorized account');

  await db.exec('reset role;set role anon');
  await assert.rejects(db.query('select public.account_deletion_check_access()'),denied);
  const report={passed,policyCount:82,engine:'PGlite plus real invitation handlers with injected HTTP transport',
    source:'Reviewed catalog names with minimal synthetic table/view fixtures and actual draft/recorder SQL',
    productionChanged:false,globalRevocationProven:false,realMessagesSent:0,
    limitations:['No hosted JWT/Auth/Storage/Realtime/Edge acceptance','No full production-schema copy','No provider erasure, request draining, anonymous-token shutdown or native-device proof']};
  fs.writeFileSync(path.join(root,'validation/account-deletion-access-integration.json'),JSON.stringify(report,null,2));
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
