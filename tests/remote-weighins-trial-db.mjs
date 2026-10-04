import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {createRequire} from 'node:module';
import {createRemoteTrialPostgresStore} from '../src/remote-weighins-trial-postgres.mjs';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
test('persistent trial activation is authorized, idempotent and bounded across directors and programs',async()=>{
 const db=new PGlite();try{
 await db.exec(`create schema private;create schema remote_reporting;create role anon;create role authenticated;create table organizations(id uuid primary key);create table remote_reporting.programs(id text primary key,kind text,event_id text,active boolean,covered_until timestamptz,coverage_revoked boolean default true);`);
 await db.exec(await readFile(new URL('../supabase/drafts/remote-director-trials.sql',import.meta.url),'utf8'));
 const org='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';await db.query('insert into organizations values($1),($2)',[org,other]);
 for(let i=1;i<=5;i++){await db.query("insert into remote_reporting.programs(id,kind,event_id,active) values($1,'tournament',$2,true)",['p'+i,'event'+i]);await db.query('insert into private.remote_program_organizations values($1,$2)',['p'+i,org]);}
 await db.exec("insert into remote_reporting.programs(id,kind,event_id,active) values('alias','tournament','event1',true)");await db.query("insert into private.remote_program_organizations values('alias',$1)",[org]);
 const authorizeOrganization=async({session,organizationId})=>['director1','director2'].includes(session)&&organizationId===org;
 const store=createRemoteTrialPostgresStore({db,authorizeOrganization});
 await assert.rejects(store.activate('stranger',{organizationId:org,programId:'p1'}));assert.equal((await db.query('select count(*)::int n from private.remote_director_trials')).rows[0].n,0);
 const first=await store.activate('director1',{organizationId:org,programId:'p1'});assert.equal(first.autoCharge,false);assert.deepEqual(await store.activate('director2',{organizationId:org,programId:'alias'}),first);
 await Promise.all(['p2','p3','p4'].map(programId=>store.activate('director2',{organizationId:org,programId})));
 await assert.rejects(store.activate('director1',{organizationId:org,programId:'p5'}),/limit/);assert.equal((await store.entitlement('p4')).active,true);assert.equal(await store.entitlement('p5'),null);assert.ok((await db.query("select remote_reporting.program_coverage_until('p4') as expiry")).rows[0].expiry);assert.equal((await db.query("select remote_reporting.program_coverage_until('p5') as expiry")).rows[0].expiry,null);
 await assert.rejects(store.activate('director1',{organizationId:other,programId:'p1'}));assert.equal((await db.query('select count(*)::int n from private.remote_director_trials')).rows[0].n,1);
 // Revocation persists and cannot be restarted by changing the activating director.
 await db.exec('update private.remote_director_trials set revoked=true');assert.equal((await db.query("select remote_reporting.program_coverage_until('p4') as expiry")).rows[0].expiry,null);assert.equal(await store.entitlement('p1'),null);await assert.rejects(store.activate('director2',{organizationId:org,programId:'p1'}),/expired/);
 await db.exec("update private.remote_director_trials set revoked=false,started_at='2026-01-31T12:00:00Z',expires_at='2026-02-28T12:00:00Z'");assert.equal(await store.entitlement('p1'),null);await assert.rejects(store.activate('director1',{organizationId:org,programId:'p1'}),/expired/);
 await db.exec('set role authenticated');await assert.rejects(db.query('select * from private.remote_director_trials'));await db.exec('reset role');
 }finally{await db.close();}
});
