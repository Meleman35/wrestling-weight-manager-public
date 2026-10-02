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
const ids=Object.fromEntries(['coach','trainer','parent','teen','other','team','team2','org','org2','season','athlete','profile','athlete2','profile2'].map(k=>[k,uuid()])),sessions={};
for(const k of ['coach','trainer','parent','teen','other']){
 sessions[ids[k]]=uuid();await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[ids[k],k+'@example.test']);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sessions[ids[k]],ids[k]]);
 await db.query('insert into public.profiles(id,display_name) values($1,$2)',[ids[k],'Sample '+k]);
}
await db.query("insert into public.organizations(id,name) values($1,'School'),($2,'Other school')",[ids.org,ids.org2]);
await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Wrestling'),($3,$4,'Other team')",[ids.team,ids.org,ids.team2,ids.org2]);
await db.query("insert into public.seasons(id,team_id,name) values($1,$2,'School year')",[ids.season,ids.team]);
for(const [a,p] of [['athlete','profile'],['athlete2','profile2']]){
 await db.query('insert into public.athlete_profiles(id) values($1)',[ids[p]]);
 await db.query("insert into public.athletes(id,profile_id,organization_id,first_name,last_name,birth_date) values($1,$2,$3,'Sample',$4,current_date-interval '16 years')",[ids[a],ids[p],ids.org,a]);
 await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$2)',[ids.season,ids[a]]);
}
await db.query(`insert into public.team_memberships(team_id,user_id,role,athlete_id,permissions) values
 ($1,$2,'head_coach',null,'{}'),($1,$3,'manager',null,'{"staff_role":"team_trainer"}'),($1,$4,'parent_guardian',$6,'{}'),($1,$5,'athlete',$6,'{}'),($7,$8,'head_coach',null,'{}')`,[ids.team,ids.coach,ids.trainer,ids.parent,ids.teen,ids.athlete,ids.team2,ids.other]);
await db.query("insert into public.athlete_guardians(athlete_id,guardian_user_id,name) values($1,$2,'Sample Parent')",[ids.athlete,ids.parent]);
const admin=()=>db.exec('reset role');
const as=async u=>{await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,role:'authenticated',session_id:sessions[u]})]);await db.exec('set role authenticated')};
const rpc=async(action,data={})=>(await db.query('select public.athlete_health_request($1,$2) r',[action,{team_id:ids.team,...data}])).rows[0].r;
const denied=async(fn,re=(error=>error.code==='42501'))=>{await assert.rejects(fn,re)};
const today=(await db.query('select current_date::text d')).rows[0].d;

export {db,ids,sessions,as,admin,rpc,denied,today,config};
