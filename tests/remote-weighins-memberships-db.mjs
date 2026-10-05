import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {createRequire} from 'node:module';
import {createAthleteMembershipPostgresStore,createRosterMembershipResolver} from '../src/remote-athlete-memberships-postgres.mjs';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
test('private membership persistence follows canonical profile, checks transaction authority and filters active roster',async()=>{
 const db=new PGlite();try{
 await db.exec(`create schema private;create role anon;create role authenticated;create table athlete_profiles(id uuid primary key);create table athletes(id uuid primary key,organization_id uuid,profile_id uuid references athlete_profiles(id) on delete cascade);create table teams(id uuid primary key,organization_id uuid);create table seasons(id uuid primary key,team_id uuid,active boolean);create table roster_memberships(season_id uuid,athlete_id uuid,active boolean);`);
 await db.exec(await readFile(new URL('../supabase/drafts/athlete-membership-identifiers.sql',import.meta.url),'utf8'));
 const profile='11111111-1111-4111-8111-111111111111',athlete='22222222-2222-4222-8222-222222222222',team='33333333-3333-4333-8333-333333333333',org='44444444-4444-4444-8444-444444444444',season='55555555-5555-4555-8555-555555555555';
 await db.query('insert into athlete_profiles values($1)',[profile]);await db.query('insert into athletes values($1,$2,$3)',[athlete,org,profile]);await db.query('insert into teams values($1,$2)',[team,org]);await db.query('insert into seasons values($1,$2,true)',[season,team]);await db.query('insert into roster_memberships values($1,$2,true)',[season,athlete]);
 let allowed=true;const store=createAthleteMembershipPostgresStore({db,authorize:async({tx,session,athleteId})=>Boolean(tx.query)&&session==='trusted'&&athleteId===athlete&&allowed});
 await store.write({session:'trusted',athleteId:athlete,values:{usawId:'00123',aauNumber:'AB123'}});assert.deepEqual(await store.read('trusted',athlete),{usawId:'00123',aauNumber:'AB123'});
 allowed=false;await assert.rejects(store.write({session:'trusted',athleteId:athlete,values:{usawId:'999'}}));allowed=true;assert.equal((await store.read('trusted',athlete)).usawId,'00123');
 const resolve=createRosterMembershipResolver({db});assert.equal((await resolve([{clubId:team,athleteId:athlete}]))[0].aauNumber,'AB123');await db.exec('update roster_memberships set active=false');assert.deepEqual(await resolve([{clubId:team,athleteId:athlete}]),[]);
 await db.exec('set role authenticated');await assert.rejects(db.query('select * from private.athlete_membership_identifiers'));await db.exec('reset role');
 await db.query('delete from athlete_profiles where id=$1',[profile]);assert.equal((await db.query('select count(*)::int as n from private.athlete_membership_identifiers')).rows[0].n,0);
 }finally{await db.close();}
});
