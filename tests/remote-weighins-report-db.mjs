import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {createRequire} from 'node:module';
import {createCanonicalRemoteReportReader} from '../src/remote-weighins-report-postgres.mjs';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
test('canonical SQL report pages 32 clubs consistently without returning every athlete',async()=>{
 const db=new PGlite();try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
   create table auth.users(id uuid primary key,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
   create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
   create function private.board_personal(uuid) returns boolean language sql as $$select true$$;
   create table private.scoped_deletion_jobs(actor_id uuid,state text,personal boolean,sealed_at timestamptz,subject_hash text);
   create table public.teams(id uuid primary key,organization_id uuid,name text);
   create table public.athlete_profiles(id uuid primary key);
   create table public.athletes(id uuid primary key,profile_id uuid,organization_id uuid,first_name text,last_name text);
   create table public.seasons(id uuid primary key,team_id uuid,active boolean);
   create table public.roster_memberships(season_id uuid,athlete_id uuid,active boolean,primary key(season_id,athlete_id));`);
  await db.exec(await readFile('supabase/drafts/remote-weighins.sql','utf8'));
  await db.exec(await readFile('supabase/drafts/athlete-membership-identifiers.sql','utf8'));
  await db.exec(`insert into public.teams select md5('club'||n)::uuid,md5('org'||(n%2))::uuid,'Club '||lpad(n::text,2,'0') from generate_series(1,32) n;
   insert into public.seasons select id,id,true from public.teams;
   insert into public.athlete_profiles select md5('athlete'||n)::uuid from generate_series(0,3199) n;
   insert into public.athletes select md5('athlete'||n)::uuid,md5('athlete'||n)::uuid,md5('org'||((n/100+1)%2))::uuid,'Athlete',lpad(n::text,4,'0') from generate_series(0,3199) n;
   insert into public.roster_memberships select md5('club'||(n/100+1))::uuid,md5('athlete'||n)::uuid,true from generate_series(0,3199) n;
   insert into remote_reporting.programs values('program','network',null,true,now()+interval '10 days',false);
   insert into remote_reporting.windows values('week','program',null,now()-interval '1 day',now()+interval '1 hour','America/Denver',86400000,true);
   insert into remote_reporting.club_enrollments select 'program',id::text,true from public.teams;
   insert into remote_reporting.roster select 'program','week',season_id::text,athlete_id::text,true,true from public.roster_memberships;`);
  const read=createCanonicalRemoteReportReader({db}),q={programId:'program',windowId:'week',limit:500};
  const first=await read(q);assert.equal(first.total,3200);assert.equal(first.rows.length,500);assert.equal(first.nextOffset,500);assert.deepEqual(first.counts,{expected:3200,submitted:0,late:0,missing:3200});
  const seen=new Set(first.rows.map(r=>r.athleteId));let page=first;
  while(page.nextOffset!==null){page=await read({...q,offset:page.nextOffset,revision:first.revision});for(const row of page.rows){assert.ok(!seen.has(row.athleteId));seen.add(row.athleteId);}}
  assert.equal(seen.size,3200);assert.equal(page.rows.length,200);
  const row=first.rows[0],club={...q,clubId:row.clubId};const scoped=await read(club);assert.equal(scoped.total,100);assert.ok(scoped.rows.every(r=>r.clubId===row.clubId));
  await db.query('insert into private.athlete_membership_identifiers(profile_id,usaw_id,aau_number) values($1,$2,$3)',[row.athleteId,'0012345','AB001']);
  await assert.rejects(read({...q,revision:first.revision}),/Report changed/);
  const updated=await read(club);assert.equal(updated.rows[0].usawId,'0012345');assert.equal(updated.rows[0].aauNumber,'AB001');
  await db.query('insert into auth.users values($1,now(),null,null)',[row.athleteId]);
  await db.query("insert into remote_reporting.evidence values('photo','program','{}','private/photo',$1,true,now()+interval '1 day',true,true,'camera',1000)",['a'.repeat(64)]);
  const record={capturedAt:new Date(Date.now()-5000).toISOString(),weight:125.4,unit:'lb'};
  await db.query("insert into remote_reporting.submissions(submission_id,program_id,window_id,club_id,athlete_id,operator_id,evidence_id,record,payload_hash) values('capture','program','week',$1,$2::text,$2::text::uuid,'photo',$3,$4)",[row.clubId,row.athleteId,record,'a'.repeat(64)]);
  const accepted=await read({...club,status:'submitted'});assert.equal(accepted.total,1);assert.equal(accepted.rows[0].submission.weight,125.4);assert.equal(accepted.counts.missing,99);assert.doesNotMatch(JSON.stringify(accepted),/operator_id|evidence_id|private\/photo|profile_id/);
  await db.exec("update remote_reporting.evidence set revoked=true where id='photo'");
  await assert.rejects(read({...club,status:'submitted',revision:accepted.revision}),/Report changed/);assert.equal((await read({...club,status:'submitted'})).total,0);
  await db.query('update remote_reporting.roster set remote_consent=false where athlete_id=$1',[row.athleteId]);assert.equal((await read(club)).total,99);
  await db.query('update public.seasons set active=false where team_id=$1',[row.clubId]);assert.equal((await read(club)).total,0);
 }finally{await db.close();}
});
