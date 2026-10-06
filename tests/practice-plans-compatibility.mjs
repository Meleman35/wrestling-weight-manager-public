import {fixture} from './helpers/scoped-deletion-db.mjs';
import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomUUID as uuid} from 'node:crypto';
const {db}=await fixture(),checks=[];
process.on('uncaughtException',e=>{console.error(e.message,e.where||'');process.exit(1)});
const pass=x=>{checks.push(x);console.log('PASS',x)};
const file=async p=>{try{await db.exec(await readFile(p,'utf8'))}catch(e){console.error('SQL',p,e.message,e.where||'',e.position||'');throw e}};
await db.exec(`alter table auth.users add column raw_user_meta_data jsonb default '{}';create schema extensions;
 create function extensions.digest(text,text) returns bytea language sql immutable as $$select sha256(convert_to($1,'UTF8'))$$;
 create function extensions.gen_random_bytes(integer) returns bytea language sql volatile as $$select sha256(convert_to(gen_random_uuid()::text,'UTF8'))$$;
 create function private.scoped_deletion_access_ok() returns boolean language sql as $$select true$$;
 create function private.scoped_deletion_freeze() returns trigger language plpgsql as $$begin return coalesce(new,old);end$$;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text,metadata jsonb,unique(bucket_id,name));
 alter table storage.objects enable row level security;
 grant usage on schema public,private,auth,storage to authenticated,service_role;grant select,insert,update,delete on storage.objects to authenticated;`);
for(const f of ['athlete-health-existing','health-communication_person_name','health-team_people_revision','health-accept_manager_invitation'])await file('tests/fixtures/'+f+'.sql');
// Use the real fingerprint implementation after the synthetic pre-migration fixture.
const service=await readFile('supabase/scoped-deletion-service.sql','utf8');
await db.exec(service.slice(service.indexOf('create function private.scoped_deletion_schema_hash()'),service.indexOf('create function private.scoped_deletion_matches')).replace('private.scoped_deletion_schema_hash()','private.fixture_schema_hash()'));
await db.exec(`create function private.scoped_deletion_schema_hash() returns text language sql stable as $$select case when to_regclass('private.health_cases') is null then '4edb6748d4f52b32daeb62498f2fb3152b6bc5caa1ac1618b7e89e77c850d587' else private.fixture_schema_hash() end$$;
 create table private.scoped_deletion_config(id boolean primary key,catalog jsonb,catalog_hash text);
 insert into private.scoped_deletion_config values(true,'{}',private.scoped_deletion_schema_hash());`);
for(const name of ['20260930155742_athlete_merge_020103','20260930172502_athlete_merge_guardian_conflicts_020103','20260930174240_athlete_merge_contact_review_020104'])await file('supabase/migrations/'+name+'.sql');
await file('supabase/migrations/20260930233008_team_trainer_athlete_health_020106.sql');
const config=(await db.query('select catalog,catalog_hash,private.scoped_deletion_schema_hash() current from private.scoped_deletion_config')).rows[0];
assert.equal(config.catalog_hash,config.current);assert.equal(config.catalog.tables.filter(t=>t.name.startsWith('health_')).length,8);
assert((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(config.current));
pass('Atomic migration registers every health table and FK while preserving deletion and merge drift guards');
// Even a mistakenly broad permissive policy cannot expose or overwrite this bucket.
await db.exec('create policy fixture_permissive on storage.objects for all to authenticated using(true) with check(true)');

const actualPreHash=config.current;
const migration=(await readFile('supabase/migrations/20261001002730_creator_offer_controls_020107.sql','utf8')).replaceAll('27d274de0c35fb69ae2ed5ff35a959b9b001de1ef865fad1a804b5ba8b39f57e',actualPreHash);
await db.exec(migration);
const next=(await db.query('select catalog,catalog_hash,private.scoped_deletion_schema_hash() current from private.scoped_deletion_config')).rows[0];
assert.equal(next.catalog_hash,next.current);assert.notEqual(next.current,actualPreHash);
assert.equal(next.catalog.tables.filter(t=>t.name.startsWith('creator_')).length,4);
assert((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(next.current));
assert.equal((await db.query("select count(*)::int n from pg_trigger where tgname='scoped_deletion_freeze' and tgrelid in ('private.creator_accounts'::regclass,'private.creator_offer_drafts'::regclass,'private.creator_trial_policy'::regclass,'private.creator_offer_events'::regclass)")).rows[0].n,4);
pass('Creator migration preserves the exact live schema gates and freezes every new table');
await file('supabase/migrations/20260930151016_wrestler_statistics_020102.sql');
const practiceMigration=(await readFile('supabase/migrations/20261001010602_practice_plans_020109.sql','utf8')).replaceAll('77511a6731a00bdd44ab3767a9581c873cb8e69f97f54cbbb51547f8276568d0',next.current);
await db.exec(practiceMigration);
let final=(await db.query('select catalog,catalog_hash,private.scoped_deletion_schema_hash() current from private.scoped_deletion_config')).rows[0];
assert.equal(final.catalog_hash,final.current);assert.notEqual(final.current,next.current);
assert(final.catalog.tables.some(t=>t.schema==='private'&&t.name==='practice_plans'));
assert.equal(final.catalog.constraints.filter(k=>k.table==='practice_plans'&&k.type==='f').length,4);
assert((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(final.current));
assert.equal((await db.query("select count(*)::int n from pg_trigger where tgname='scoped_deletion_freeze' and tgrelid='private.practice_plans'::regclass")).rows[0].n,1);
assert.equal((await db.query('select private.practice_plans_covered(gen_random_uuid()) covered')).rows[0].covered,false);
pass('Practice migration registers the complete catalog and exact deletion/merge fingerprints; paid coverage remains closed');

const reviewBefore=final.current;
await db.exec(await readFile('supabase/practice-plan-review.sql','utf8'));
final=(await db.query('select catalog,catalog_hash,private.scoped_deletion_schema_hash() current from private.scoped_deletion_config')).rows[0];
assert.equal(final.catalog_hash,final.current);assert.notEqual(final.current,reviewBefore);
assert(final.catalog.tables.find(t=>t.name==='practice_plans').columns.some(c=>c.name==='athlete_visible'));
assert((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(final.current));
assert.equal((await db.query("select count(*)::int n from pg_trigger where tgname='scoped_deletion_freeze' and tgrelid='private.practice_plans'::regclass")).rows[0].n,1);
assert.equal((await db.query("select has_table_privilege('authenticated','private.practice_plans','select') allowed")).rows[0].allowed,false);
pass('Review/athlete-sharing migration preserves private storage, refreshes the complete deletion catalog and exact merge guard, and retains the deletion freeze');

const owner=uuid(),other=uuid(),team=uuid(),org=uuid(),pid=uuid(),sid=uuid();
await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'owner@example.test',now()),($2,'other@example.test',now())",[owner,other]);
await db.query("insert into public.profiles(id) values($1),($2)",[owner,other]);
await db.query("insert into public.organizations(id,name) values($1,'School')",[org]);
await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Team')",[team,org]);
await db.query("insert into private.practice_plans(id,team_id,plan_date,title,created_by,updated_by,last_request_id,last_payload_hash) values($1,$2,'2026-10-01','Shared plan',$3,$3,$4,'fixture')",[pid,team,owner,uuid()]);
const {planDeletion}=await import('../scripts/scoped-deletion-plan.mjs');
const quote=x=>{assert.match(x,/^[a-z_][a-z0-9_]*$/);return '"'+x+'"'},relation=t=>t.split('.').map(quote).join('.');
const reader={
 async select(table,predicates,limit){const values=[],where=predicates.map(p=>'('+Object.entries(p).map(([k,v])=>{values.push(v);return quote(k)+' is not distinct from $'+values.length}).join(' and ')+')').join(' or ');values.push(limit);return (await db.query('select * from '+relation(table)+' where '+where+' limit $'+values.length,values)).rows},
 async identityMentions(table,columns,actor,limit){return (await db.query('select * from '+relation(table)+' where '+columns.map(c=>quote(c)+"::text like '%' || $1 || '%'").join(' or ')+' limit $2',[actor,limit])).rows}
};

const personal=await planDeletion({scope:{actorId:owner,kind:'personal',teamIds:[],organizationIds:[]},catalog:final.catalog,reader});
const kept=personal.records.find(x=>x.table==='private.practice_plans');assert.equal(kept.action,'null');assert.deepEqual(kept.columns,['created_by','updated_by']);
assert(!personal.records.some(x=>x.table==='public.profiles'&&x.key.id===other));
const workspace=await planDeletion({scope:{actorId:owner,kind:'team',teamIds:[team],organizationIds:[]},catalog:final.catalog,reader});
assert(workspace.records.some(x=>x.table==='private.practice_plans'&&x.action==='delete'));
assert(!workspace.records.some(x=>x.table==='public.profiles'||x.table==='auth.users'));
pass('Actual deletion planner removes team plans with the team and only detaches personal coach authorship');
await db.exec('alter table private.practice_plans add column fixture_drift text');
assert.notEqual((await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h,final.catalog_hash);
pass('Unreviewed future schema changes still stop deletion and athlete merging');
await db.close();
