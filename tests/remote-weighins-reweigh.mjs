import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {createCanonicalRemoteReportReader} from '../src/remote-weighins-report-postgres.mjs';
import {createRemotePostgresAdapters} from '../src/remote-weighins-postgres.mjs';
import {summarizeWindow,reportCsv} from '../src/remote-weighins.mjs';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');

test('allowed tournament reweighs select the lowest complete attempt without duplicate report rows',async()=>{
 const db=new PGlite();
 try {
  await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
   create table auth.users(id uuid primary key,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
   create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
   create function private.board_personal(uuid) returns boolean language sql as $$select true$$;
   create table private.scoped_deletion_jobs(actor_id uuid,state text,personal boolean,sealed_at timestamptz,subject_hash text);
   create table public.teams(id uuid primary key,organization_id uuid,name text);
   create table public.athletes(id uuid primary key,profile_id uuid,organization_id uuid,first_name text,last_name text);
   create table public.seasons(id uuid primary key,team_id uuid,active boolean);
   create table public.roster_memberships(season_id uuid,athlete_id uuid,active boolean);
   create table private.athlete_membership_identifiers(profile_id uuid,usaw_id text,aau_number text);`);
  await db.exec(await readFile('supabase/drafts/remote-weighins.sql','utf8'));
  const user=randomUUID(),session=randomUUID(),club=randomUUID(),athlete=randomUUID(),org=randomUUID();
  await db.query('insert into auth.users values($1,now(),null,null)',[user]);
  await db.query('insert into auth.sessions values($1,$2,null)',[session,user]);
  await db.query("insert into public.teams values($1,$2,'Test Club')",[club,org]);
  await db.query("insert into public.athletes values($1,$1,$2,'Test','Athlete')",[athlete,org]);
  await db.query('insert into public.seasons values($1,$1,true)',[club]);
  await db.query('insert into public.roster_memberships values($1,$2,true)',[club,athlete]);
  await db.exec(`insert into remote_reporting.programs values('event','tournament','tournament',true,now()+interval '10 days',false);
   insert into remote_reporting.windows(id,program_id,event_id,opens_at,closes_at,time_zone,active,event_date,allow_reweigh)
    values('window','event','tournament',(current_date-1)::timestamp at time zone 'UTC',(current_date+1)::timestamp at time zone 'UTC','UTC',true,current_date,true);`);
  await db.query("insert into remote_reporting.club_enrollments values('event',$1,true)",[club]);
  await db.query("insert into remote_reporting.roster values('event','window',$1,$2,true,true)",[club,athlete]);
  await db.query("insert into remote_reporting.assignments values('event',$1,$2,'operator',true)",[user,club]);
  await assert.rejects(db.exec('update remote_reporting.windows set allow_reweigh=false'),/locked/);
  const origin=Date.now()-10000;
  async function attempt(id,weight,offset,method='nfc'){
   const binding={captureId:'capture-'+id,programId:'event',windowId:'window',clubId:club,athleteId:athlete,
    operatorId:user,generation:'generation',weight,unit:'lb',capturedAt:new Date(origin+offset).toISOString(),
    photoCapturedAt:new Date(origin+offset+50).toISOString(),method};
   await db.query('insert into remote_reporting.evidence(id,program_id,binding,private_object_key,digest,verified,expires_at,notice_accepted,settled,source,byte_count) values($1,$2,$3,$4,$5,true,$6,true,true,\'camera\',1000)',
    ['photo-'+id,'event',binding,'private/'+id,'digest-'+id,new Date(origin+offset+240*3600000).toISOString()]);
   return {submissionId:id,evidenceId:'photo-'+id,...binding,kind:'tournament',eventId:'tournament',evidenceDigest:'digest-'+id};
  }
  const accept=r=>db.query('select remote_reporting.accept($1,$2,$3,$4) as receipt',[user,session,r,createHash('sha256').update(JSON.stringify(r)).digest('hex')]);
  const first=await attempt('first',126.2,0),lighter=await attempt('lighter',125.8,1000),heavier=await attempt('heavier',127,2000),equal=await attempt('equal',125.8,3000,'qr');
  const receipt=(await accept(first)).rows[0].receipt;
  const read=createCanonicalRemoteReportReader({db}),query={programId:'event',windowId:'window'};
  const before=await read(query);assert.equal(before.total,1);assert.equal(before.rows[0].submission.weight,126.2);
  await Promise.all([accept(heavier),accept(lighter),accept(equal)]);
  const result=await read(query);
  assert.equal(result.total,1);assert.equal(result.counts.expected,1);assert.equal(result.counts.submitted,1);
  assert.equal(result.rows[0].submission.submissionId,'lighter');assert.equal(result.rows[0].submission.weight,125.8);
  assert.equal(result.rows[0].submission.capturedAt,lighter.capturedAt);
  assert.equal(reportCsv(result.rows).split('\r\n').length,2);
  await assert.rejects(read({...query,revision:before.revision}),/Report changed/);
  assert.deepEqual((await accept(first)).rows[0].receipt,receipt,'Retry returns its original receipt even after replacement');
  await assert.rejects(accept({...first,weight:124}),/Idempotency/);
  assert.equal((await db.query('select count(*)::int n from remote_reporting.submissions')).rows[0].n,4);
  await assert.rejects(db.exec("update remote_reporting.submissions set record=jsonb_set(record,'{weight}','124')"),/immutable/);
  const adapters=createRemotePostgresAdapters({db,verifyPersonalSession:async()=>null,resolveRosterNames:async()=>[]});
  const selected=await adapters.store.list({...query,clubId:club});
  assert.equal(selected.length,1);assert.equal(selected[0].evidenceId,lighter.evidenceId);
  const window={id:'window',programId:'event',timeZone:'UTC',opensAt:new Date(origin-1000).toISOString(),closesAt:new Date(origin+20000).toISOString(),allowReweigh:true};
  const rows=[heavier,equal,first,lighter].map(r=>({...r,receiptId:'receipt-'+r.submissionId,status:'submitted',receivedAt:new Date(origin+5000).toISOString()}));
  const summary=summarizeWindow({window,expected:[{clubId:club,athleteId:athlete}],submissions:rows});
  assert.equal(summary.rows[0].submission.evidenceId,lighter.evidenceId);
  assert.throws(()=>summarizeWindow({window:{...window,allowReweigh:false},expected:[{clubId:club,athleteId:athlete}],submissions:rows}),/Conflicting/);
  const outside=await attempt('outside',124,2000);outside.capturedAt='2000-01-01T00:00:00.000Z';
  await assert.rejects(accept(outside),/retention expired/);
  // Revoked/expired evidence cannot remain the selected result or be exported.
  await db.exec("update remote_reporting.evidence set revoked=true where id='photo-lighter'");
  assert.equal((await read(query)).rows[0].submission.submissionId,'equal');
  await db.exec("update remote_reporting.evidence set expires_at=now()-interval '1 second' where id='photo-equal'");
  assert.equal((await read(query)).rows[0].submission.submissionId,'first');
  for(const role of ['anon','authenticated']){
   await db.exec(`set role ${role}`);await assert.rejects(db.exec('select * from remote_reporting.submissions'),/permission denied/);await db.exec('reset role');
  }
 }finally{await db.close();}
});
