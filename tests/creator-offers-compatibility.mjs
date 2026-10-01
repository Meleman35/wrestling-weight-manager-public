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
const owner=uuid(),oid=uuid();await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'owner@example.test',now())",[owner]);
await db.query('insert into private.creator_accounts(user_id) values($1)',[owner]);
await db.query("insert into private.creator_offer_drafts(id,created_by,code,product,discount_percent,billing_periods,redemption_limit,expires_at) values($1,$2,'SAMPLE','team_pro_year',20,1,100,now()+interval '1 day')",[oid,owner]);
await db.query("insert into private.creator_offer_events(actor_id,offer_id,action,detail) values($1,$2,'create','{}')",[owner,oid]);
const {planDeletion}=await import('../scripts/scoped-deletion-plan.mjs');
const quote=x=>{assert.match(x,/^[a-z_][a-z0-9_]*$/);return '"'+x+'"'},relation=t=>t.split('.').map(quote).join('.');
const reader={
 async select(table,predicates,limit){const values=[],where=predicates.map(p=>'('+Object.entries(p).map(([k,v])=>{values.push(v);return quote(k)+' is not distinct from $'+values.length}).join(' and ')+')').join(' or ');values.push(limit);return (await db.query('select * from '+relation(table)+' where '+where+' limit $'+values.length,values)).rows},
 async identityMentions(table,columns,actor,limit){return (await db.query('select * from '+relation(table)+' where '+columns.map(c=>quote(c)+"::text like '%' || $1 || '%'").join(' or ')+' limit $2',[actor,limit])).rows}
};
const plan=await planDeletion({scope:{actorId:owner,kind:'personal',teamIds:[],organizationIds:[]},catalog:next.catalog,reader});
for(const t of ['creator_accounts','creator_offer_drafts','creator_offer_events'])assert(plan.records.some(x=>x.table==='private.'+t&&x.action==='delete'));
assert(!plan.records.some(x=>x.table==='private.creator_trial_policy'));
pass('The actual deletion planner removes Creator identity/drafts/history and preserves the anonymous launch preference');
await db.exec('alter table private.creator_trial_policy add column fixture_drift text');
assert.notEqual((await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h,next.catalog_hash);
pass('Unreviewed schema changes still invalidate readiness');
await db.close();
