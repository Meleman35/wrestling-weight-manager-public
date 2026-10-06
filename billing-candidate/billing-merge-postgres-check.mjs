import assert from 'node:assert/strict';
import {randomUUID as uuid,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture} from '../tests/helpers/scoped-deletion-db.mjs';

// Actual full-schema merge router, plan, profile triggers and billing selection.
// Synthetic adults, Auth and deletion status only; no hosted data is used.
const {db}=await fixture();
const root=new URL('../',import.meta.url),read=path=>readFile(new URL(path,root),'utf8');
const pinned='991e2028b296773026c1a090426585d7af554636572e6ff42d2aa66754af4835';
const approved='c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8';
let checks=0;const pass=name=>{checks++;console.log('PASS '+name);};
const admin=()=>db.exec('reset role');
async function as(user,role='authenticated'){
 await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user})]);
 await db.exec('set role '+role);
}
const coach=uuid(),stranger=uuid(),org=uuid(),team=uuid(),season=uuid();
async function adult(){const id=uuid();await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);await db.query('insert into public.profiles(id) values($1)',[id]);return id;}
async function athlete(pid=uuid(),organization=org){
 const id=uuid();await db.query('insert into public.athlete_profiles(id) values($1) on conflict do nothing',[pid]);
 await db.query("insert into public.athletes(id,profile_id,organization_id,first_name,last_name) values($1,$2,$3,'Synthetic','Athlete')",[id,pid,organization]);
 await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$2)',[season,id]);return {id,pid};
}
async function guardian(user,a){
 await db.query("insert into public.athlete_guardians(athlete_id,guardian_user_id,name,invitation_status) values($1,$2,'Synthetic Parent','accepted')",[a.id,user]);
 await db.query("insert into public.team_memberships(team_id,user_id,athlete_id,role) values($1,$2,$3,'parent_guardian')",[team,user,a.id]);
}
const pair=(s,k)=>({duplicate_id:s.id,keep_id:k.id});
const req=async(action,data={})=>(await db.query('select public.athlete_merge_request($1,$2) r',[action,JSON.stringify({team_id:team,...data})])).rows[0].r;
const selected=async user=>(await db.query('select slot,athlete_profile_id from wm_billing.family_coverage where user_id=$1 order by slot',[user])).rows;
const count=async(table,column,id)=>Number((await db.query(`select count(*) n from ${table} where ${column}=$1`,[id])).rows[0].n);
const select=async(user,ids)=>(await db.query('select wm_billing.set_family_coverage($1,$2) r',[user,ids])).rows[0].r;
try{
 await db.exec(`create role wm_billing_runtime;
  grant usage on schema public,private,auth to authenticated;
  alter table auth.users add confirmed_at timestamptz generated always as (email_confirmed_at) stored;
  alter table auth.users add is_anonymous boolean not null default false;
  create table private.scoped_deletion_jobs(id uuid primary key default gen_random_uuid(),actor_id uuid,state text,
   team_ids uuid[] default '{}',organization_ids uuid[] default '{}');
  create function public.is_team_admin(t uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.team_memberships where team_id=t and user_id=auth.uid() and role='head_coach' and active)$$;
  create function private.board_personal(u uuid) returns boolean language sql as $$select u is not null and not exists(select 1 from private.team_logins where user_id=u)$$;
  create function private.board_minor(u uuid) returns boolean language sql as $$select false$$;
  create function private.scoped_deletion_access_ok() returns boolean language sql as $$select true$$;
  create function private.scoped_deletion_schema_hash() returns text language sql as $$select '4edb6748d4f52b32daeb62498f2fb3152b6bc5caa1ac1618b7e89e77c850d587'::text$$;`);
 for(const path of ['supabase/migrations/20260930155742_athlete_merge_020103.sql',
  'supabase/migrations/20260930172502_athlete_merge_guardian_conflicts_020103.sql',
  'supabase/migrations/20260930174240_athlete_merge_contact_review_020104.sql',
  'tests/fixtures/scoped-deletion-mutation-triggers.sql','tests/fixtures/athlete-merge-profile-triggers.sql',
  'billing-candidate/billing-storage-candidate.sql'])await db.exec(await read(path));
 const access=await read('billing-candidate/billing-access-candidate.sql');
 const start=access.indexOf('create function wm_billing.set_family_coverage(');
 assert.ok(start>=0);
 await db.exec(access.slice(start,access.indexOf('-- Only accepted, currently active guardian/roster relationships',start)));
 const router=await read('billing-candidate/tests/billing-merge-router.sql');
 assert.equal(createHash('sha256').update(router).digest('hex'),pinned);
 await db.exec(router);
 const integration=await read('billing-candidate/billing-merge-integration.sql');
 await db.exec('begin');
 await db.exec(router.replace('Unknown merge action','Synthetic changed router'));
 await assert.rejects(()=>db.exec(integration),/BILLING_MERGE_ROUTER_REVIEW_REQUIRED/);
 await db.exec('rollback');
 assert.equal((await db.query("select to_regprocedure('wm_billing.merge_family_coverage(uuid,uuid)') r")).rows[0].r,null);
 await db.exec('begin');await db.exec(integration);await db.exec('commit');
 // Production hash approval is deliberately not supplied by the candidate.
 assert.ok((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(approved));
 await db.exec(`create or replace function private.scoped_deletion_schema_hash() returns text language sql as $$select '${approved}'::text$$`);
 pass('source-pinned router patch rejects drift atomically and preserves the production compatibility gate');
 for(const id of [coach,stranger]){await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);await db.query('insert into public.profiles(id) values($1)',[id]);}
 await db.query("insert into public.organizations(id,name) values($1,'Synthetic Organization')",[org]);
 await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Synthetic Team')",[team,org]);
 await db.query("insert into public.seasons(id,team_id,name) values($1,$2,'Current')",[season,team]);
 await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach')",[team,coach]);
 let s=await athlete(),k=await athlete();
 const unrelated=await athlete(),sourceParent=await adult(),targetParent=await adult(),bothParent=await adult();
 await guardian(sourceParent,s);await guardian(sourceParent,unrelated);await guardian(targetParent,k);
 await as(sourceParent,'wm_billing_runtime');assert.deepEqual(await select(sourceParent,[s.id,unrelated.id]),{selectedCount:2});
 await assert.rejects(()=>db.query('update wm_billing.family_coverage set athlete_profile_id=$1 where user_id=$2',[k.pid,sourceParent]),/permission denied/);
 await assert.rejects(()=>db.query('insert into wm_billing.family_coverage values($1,1,$2)',[stranger,k.pid]),/permission denied/);
 await assert.rejects(()=>db.query('delete from wm_billing.family_coverage where user_id=$1',[sourceParent]),/permission denied/);
 for(const helper of ['coverage_merge_version','merge_family_coverage'])await assert.rejects(()=>db.query(`select wm_billing.${helper}($1,$2)`,[s.id,k.id]),/permission denied/);
 await as(stranger);await assert.rejects(()=>req('preview',pair(s,k)),/administrator/);
 await as(coach);await assert.rejects(()=>db.query('select wm_billing.merge_family_coverage($1,$2)',[s.id,k.id]),/permission denied/);
 pass('only authorized selection and the administrator merge router can change family coverage');
 let plan=await req('preview',pair(s,k));assert.deepEqual(plan.blockers,[]);
 await admin();await db.query('insert into wm_billing.family_coverage values($1,2,$2)',[targetParent,k.pid]);
 await as(coach);await assert.rejects(()=>req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'}),/Records changed/);
 await admin();
 // A historical duplicate selection is deliberately seeded without granting a
 // second guardian relationship. Coverage rows alone never authorize access.
 await db.query('insert into wm_billing.family_coverage values($1,1,$2),($1,2,$3)',[bothParent,s.pid,k.pid]);
 await as(coach);plan=await req('preview',pair(s,k));
 for(const id of [sourceParent,targetParent,bothParent])assert.equal(JSON.stringify(plan).includes(id),false);
 assert.match(plan.version,/^[a-f0-9]{64}$/);
 const receipt=await req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'});
 assert.equal(receipt.status,'completed');assert.deepEqual(await req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'}),receipt);
 await admin();
 assert.deepEqual(await selected(sourceParent),[{slot:1,athlete_profile_id:k.pid},{slot:2,athlete_profile_id:unrelated.pid}]);
 assert.deepEqual(await selected(targetParent),[{slot:2,athlete_profile_id:k.pid}]);
 assert.deepEqual(await selected(bothParent),[{slot:2,athlete_profile_id:k.pid}]);
 assert.equal(await count('public.athlete_profiles','id',s.pid),0);
 assert.equal(await count('wm_billing.family_coverage','athlete_profile_id',s.pid),0);
 assert.equal(await count('wm_billing.subscriptions','user_id',sourceParent),0);
 await as(sourceParent,'wm_billing_runtime');await assert.rejects(()=>select(sourceParent,[s.id]),/family_coverage_forbidden/);
 assert.deepEqual(await select(sourceParent,[k.id,unrelated.id]),{selectedCount:2});
 pass('stale previews fail; merge preserves family slots and guardian selection, deduplicates coverage and retries safely');
 await admin();s=await athlete();k=await athlete();const rollbackParent=await adult();
 await db.query('insert into wm_billing.family_coverage values($1,1,$2)',[rollbackParent,s.pid]);
 await db.exec(`create function private.synthetic_merge_failure() returns trigger language plpgsql as $$begin
  if current_setting('wm.synthetic_merge_failure',true)='on' then raise exception 'SYNTHETIC_LATE_FAILURE';end if;return old;end$$;
  create trigger synthetic_merge_failure before delete on public.athletes for each row execute function private.synthetic_merge_failure();`);
 await as(coach);plan=await req('preview',pair(s,k));await db.exec("set wm.synthetic_merge_failure='on'");
 await assert.rejects(()=>req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'}),/SYNTHETIC_LATE_FAILURE/);
 await db.exec("set wm.synthetic_merge_failure='off'");await admin();
 assert.deepEqual(await selected(rollbackParent),[{slot:1,athlete_profile_id:s.pid}]);
 assert.equal(await count('public.athletes','id',s.id),1);assert.equal(await count('public.roster_memberships','athlete_id',s.id),1);
 assert.equal(await count('public.audit_log','entity_id',k.id),0);
 pass('a failure after coverage moves rolls back coverage, profiles, roster and receipt together');
 await db.query("insert into private.scoped_deletion_jobs(actor_id,state) values($1,'pending')",[rollbackParent]);
 await as(coach);plan=await req('preview',pair(s,k));
 await assert.rejects(()=>req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'}),/BILLING_MERGE_DELETION_PENDING/);
 await admin();assert.deepEqual(await selected(rollbackParent),[{slot:1,athlete_profile_id:s.pid}]);
 await db.query("update private.scoped_deletion_jobs set state='cancelled' where actor_id=$1",[rollbackParent]);
 const shared=await athlete(s.pid,null);
 await as(coach);plan=await req('preview',pair(s,k));
 await assert.rejects(()=>req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'}),/shares an identity|BILLING_MERGE_SHARED_PROFILE_REVIEW/);
 await admin();assert.equal(await count('public.athletes','id',shared.id),1);
 assert.deepEqual(await selected(rollbackParent),[{slot:1,athlete_profile_id:s.pid}]);
 pass('pending account deletion and a shared source identity block coverage transfers without partial changes');
 s=await athlete(uuid(),null);k=await athlete(s.pid,null);const sameParent=await adult();await db.query('insert into wm_billing.family_coverage values($1,1,$2)',[sameParent,s.pid]);
 await as(coach);plan=await req('preview',pair(s,k));
 await req('merge',{...pair(s,k),version:plan.version,confirmation:'merge'});await admin();
 assert.deepEqual(await selected(sameParent),[{slot:1,athlete_profile_id:k.pid}]);assert.equal(await count('public.athlete_profiles','id',k.pid),1);
 await db.exec("create or replace function private.scoped_deletion_schema_hash() returns text language sql as $$select 'changed'::text$$");
 await as(coach);await assert.rejects(()=>req('preview',pair(s,k)),/compatibility/);
 pass('same-profile duplicates retain coverage; later schema drift still blocks unreviewed merges');
 console.log(`${checks} billing merge integration checks passed; no live data changed.`);
}catch(error){console.error(error.message,error.where||'');process.exitCode=1;}finally{await db.close();}
