import test from 'node:test';import assert from 'node:assert/strict';
import {createRequire} from 'node:module';import {createCanonicalRemoteRosterResolver} from '../src/remote-weighins-roster-postgres.mjs';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
test('canonical names require same-organization athlete and active team season/roster',async()=>{
 const db=new PGlite();try{
 await db.exec(`create table teams(id uuid primary key,organization_id uuid,name text);
 create table athletes(id uuid primary key,organization_id uuid,first_name text,last_name text);
 create table seasons(id uuid primary key,team_id uuid,active boolean);
 create table roster_memberships(season_id uuid,athlete_id uuid,active boolean);`);
 const team='11111111-1111-4111-8111-111111111111',athlete='22222222-2222-4222-8222-222222222222',org='33333333-3333-4333-8333-333333333333',season='44444444-4444-4444-8444-444444444444';
 await db.query('insert into teams values($1,$2,$3)',[team,org,'Club']);
 await db.query('insert into athletes values($1,$2,$3,$4)',[athlete,org,'Test','Athlete']);
 await db.query('insert into seasons values($1,$2,true)',[season,team]);
 await db.query('insert into roster_memberships values($1,$2,true)',[season,athlete]);
 const resolve=createCanonicalRemoteRosterResolver({db}),pair={clubId:team,athleteId:athlete};
 assert.deepEqual(await resolve([pair,pair]),[{...pair,clubName:'Club',athleteName:'Test Athlete',firstName:'Test',lastName:'Athlete'}]);
 await db.query('update athletes set first_name=$1,last_name=$2 where id=$3',['María José','De La Cruz',athlete]);
 const compound=(await resolve([pair]))[0];assert.equal(compound.firstName,'María José');assert.equal(compound.lastName,'De La Cruz');
 for(const table of ['seasons','roster_memberships']){await db.exec(`update ${table} set active=false`);await assert.rejects(resolve([pair]),/unavailable/);await db.exec(`update ${table} set active=true`);}
 await db.query('update athletes set organization_id=$1',[season]);await assert.rejects(resolve([pair]),/unavailable/);
 await assert.rejects(resolve([{...pair,clubId:'forged'}]),/Canonical/);
 assert.deepEqual(await resolve([]),[]);
 }finally{await db.close();}
});
