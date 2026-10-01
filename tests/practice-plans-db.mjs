import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import assert from 'node:assert/strict';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
const db=new PGlite(),owner=uuid(),other=uuid(),sid=uuid(),otherSid=uuid(),team=uuid(),otherTeam=uuid(),event=uuid();
await db.exec(`create schema private;create schema auth;create role anon;create role authenticated;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id) on delete cascade,not_after timestamptz);
 create table private.team_logins(user_id uuid primary key);
 create table private.deletion_test_block(user_id uuid);
 create function private.scoped_deletion_access_ok() returns boolean language sql as $$select not exists(select 1 from private.deletion_test_block where user_id=auth.uid())$$;
 create function private.scoped_deletion_freeze() returns trigger language plpgsql as $$begin return coalesce(new,old);end$$;
 grant usage on schema public,private,auth to authenticated,anon;`);
await db.exec(`create table public.teams(id uuid primary key,name text,timezone text,organization_id uuid);
 create table public.team_events(id uuid primary key,team_id uuid references public.teams(id),title text,event_type text,starts_at timestamptz,ends_at timestamptz);
 create table public.team_memberships(team_id uuid,user_id uuid,role text,active boolean default true,permissions jsonb default '{}');
 create table public.organization_memberships(organization_id uuid,user_id uuid,role text);
 create function public.is_team_staff(check_team_id uuid) returns boolean language sql stable security definer set search_path='public' as $$
 select exists(select 1 from public.team_memberships tm where tm.team_id=check_team_id and tm.user_id=auth.uid() and tm.active=true
 and (tm.role in ('head_coach','assistant_coach') or (tm.role='manager' and coalesce((tm.permissions->>'team_admin')::boolean,false))))
 or exists(select 1 from public.teams t join public.organization_memberships om on om.organization_id=t.organization_id where t.id=check_team_id and om.user_id=auth.uid() and om.role='organization_admin')$$;
 create table private.fixture_coverage(team_id uuid primary key,starts_at timestamptz,ends_at timestamptz,revoked boolean default false,kind text);
 create function private.wrestler_statistics_covered(t uuid) returns boolean language sql stable set search_path='' as $$select exists(select 1 from private.fixture_coverage where team_id=t and starts_at<=now() and ends_at>now() and not revoked and kind in ('paid','trial'))$$;
 revoke all on private.fixture_coverage from public,anon,authenticated;`);
await db.exec(await readFile('supabase/practice-plans.sql','utf8'));
await db.query("insert into auth.users(id,email_confirmed_at) values($1,now()),($2,now())",[owner,other]);
await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4)',[sid,owner,otherSid,other]);
await db.query("insert into public.teams(id,name,timezone) values($1,'School','America/Denver'),($2,'Other','UTC')",[team,otherTeam]);
await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$2,'head_coach'),($3,$4,'head_coach')",[team,owner,otherTeam,other]);
await db.query("insert into public.team_events values($1,$2,'Evening practice','practice','2026-10-02T00:00Z','2026-10-02T01:30Z')",[event,team]);
const admin=()=>db.exec('reset role');
const as=async(u=owner,s=sid,extra={})=>{await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,session_id:s,role:'authenticated',...extra})]);await db.exec('set role authenticated')};
const rpc=async(a,d={})=>(await db.query('select public.practice_plans_request($1,$2) r',[a,{team_id:team,...d}])).rows[0].r;
const no=async(f,pattern)=>assert.rejects(f,pattern);const pass=s=>console.log('PASS',s);
const block={id:uuid(),category:'technique',label:'Single leg',minutes:20,notes:'Two finishes'};
const payload={id:uuid(),event_id:event,revision:0,request_id:uuid(),plan_date:'2026-10-01',start_time:'18:00',target_minutes:90,title:'Evening plan',focus:'Finishes',notes:'Bring bands',blocks:[block]};
await as();assert.equal((await rpc('context')).covered,false);
for(const [a,d] of [['list',{month:'2026-10'}],['event',{event_id:event}],['read',{id:payload.id}],['save',payload],['delete',{id:payload.id,revision:1}]])await no(()=>rpc(a,d),/Team Pro/);
await no(()=>rpc('context',{covered:true}));pass('Unpaid teams cannot read, create, update or delete plans; client coverage claims are rejected');
await admin();await db.query("insert into private.fixture_coverage values($1,now()-interval '1 day',now()+interval '7 days',false,'trial')",[team]);await as();assert.equal((await rpc('context')).covered,true);
const e=await rpc('event',{event_id:event});assert.equal(e.plan,null);assert.equal(e.event.plan_date,'2026-10-01');assert.equal(e.event.start_time,'18:00');assert.equal(e.event.target_minutes,90);
let saved=await rpc('save',payload);assert.equal(saved.plan.revision,1);assert.equal(saved.plan.blocks[0].minutes,20);assert.equal((await rpc('save',payload)).plan.revision,1);
let list=await rpc('list',{month:'2026-10'});assert.equal(list.plans.length,1);assert.equal(list.plans[0].total_minutes,20);assert.equal((await rpc('list',{month:'2026-11'})).plans.length,0);
assert.equal((await rpc('event',{event_id:event})).plan.id,payload.id);assert.equal((await rpc('read',{id:payload.id})).plan.title,payload.title);
pass('Verified synthetic trial coverage permits plans; event dates and times use the team timezone and list totals are accurate');
await no(()=>rpc('save',{...payload,title:'Reused request'}),/different details/);
const update={...payload,revision:1,request_id:uuid(),title:'Updated practice',blocks:[{...block,minutes:30}]};saved=await rpc('save',update);assert.equal(saved.plan.revision,2);assert.equal((await rpc('save',update)).plan.revision,2);
await no(()=>rpc('save',{...update,request_id:uuid()}),/Another coach/);await no(()=>rpc('save',payload),/Another coach/);
await no(()=>rpc('delete',{id:payload.id,revision:1}),/Another coach/);
await no(()=>rpc('save',{...payload,id:uuid(),request_id:uuid()}),/already exists/);
pass('Lost-response retries are idempotent; stale edits, stale deletes and duplicate event plans cannot overwrite another coach');
for(const change of [{blocks:[{...block,minutes:0}]},{blocks:[{...block,minutes:1.5}]},{blocks:[{...block,category:'admin'}]},{blocks:[block,block]},{blocks:[{...block,label:''}]},{blocks:[{...block,notes:'x'.repeat(1501)}]},{blocks:[{...block,athlete_id:uuid()}]},{blocks:Array.from({length:41},()=>({...block,id:uuid()}))},{blocks:Array.from({length:4},()=>({...block,id:uuid(),minutes:240}))},{blocks:null},{title:''},{focus:'x'.repeat(2001)},{notes:'x'.repeat(4001)},{revision:null},{start_time:'24:00'},{target_minutes:721},{target_minutes:'90'},{plan_date:'infinity'},{plan_date:'2026-02-30'},{plan_date:'2026-10-02',event_id:event}])await no(()=>rpc('save',{...payload,id:uuid(),event_id:null,request_id:uuid(),...change}));
const copy={...update,id:uuid(),revision:0,request_id:uuid(),event_id:null,plan_date:'2026-10-02',blocks:[{...block,id:uuid()}]};await rpc('save',copy);assert.equal((await rpc('read',{id:payload.id})).plan.plan_date,'2026-10-01');
pass('Block bounds, types, dates and event ownership are validated; copying creates an independent plan');
await no(()=>db.query('select * from private.practice_plans'));await no(()=>db.query('delete from private.practice_plans'));await no(()=>db.query('select private.practice_plans_covered($1)',[team]));
await as(other,otherSid,{user_metadata:{paid:true,team_admin:true}});await no(()=>rpc('context'));await no(()=>rpc('read',{id:payload.id}));
await no(()=>rpc('save',{...payload,team_id:otherTeam}));
await admin();await db.query("insert into private.fixture_coverage values($1,now()-interval '1 day',now()+interval '1 day',false,'paid')",[otherTeam]);await as(other,otherSid);
await no(()=>rpc('read',{id:payload.id,team_id:otherTeam}));await no(()=>rpc('save',{...payload,team_id:otherTeam,request_id:uuid()}));await no(()=>rpc('event',{team_id:otherTeam,event_id:event}));
pass('Direct private-table access, spoofed metadata and cross-team records are denied, even for another paid coach');
for(const role of ['athlete','parent','team_trainer','team_mom','manager']){await admin();await db.query('update public.team_memberships set role=$1 where user_id=$2',[role,owner]);await as();await no(()=>rpc('context'))}
for(const role of ['head_coach','assistant_coach']){await admin();await db.query('update public.team_memberships set role=$1 where user_id=$2',[role,owner]);await as();assert.equal((await rpc('context')).covered,true)}
await admin();await db.query("update public.team_memberships set role='manager',permissions='{\"team_admin\":true}' where user_id=$1",[owner]);await as();assert.equal((await rpc('context')).covered,true);
await admin();await db.query('update public.team_memberships set active=false where user_id=$1',[owner]);await as();await no(()=>rpc('context'));await admin();await db.query("update public.team_memberships set active=true,role='head_coach' where user_id=$1",[owner]);
pass('Only active coaches and delegated team administrators receive team plan access');
for(const [a,b] of [
 ["update private.fixture_coverage set revoked=true where team_id=$1","update private.fixture_coverage set revoked=false where team_id=$1"],
 ["update private.fixture_coverage set ends_at=now()-interval '1 day' where team_id=$1","update private.fixture_coverage set ends_at=now()+interval '1 day' where team_id=$1"],
 ["update private.fixture_coverage set starts_at=now()+interval '1 day' where team_id=$1","update private.fixture_coverage set starts_at=now()-interval '1 day' where team_id=$1"],
 ["update private.fixture_coverage set kind='family_video' where team_id=$1","update private.fixture_coverage set kind='paid' where team_id=$1"]
]){await admin();await db.query(a,[team]);await as();assert.equal((await rpc('context')).covered,false);await no(()=>rpc('read',{id:payload.id}),/Team Pro/);await no(()=>rpc('save',{...update,revision:2,request_id:uuid()}),/Team Pro/);await admin();await db.query(b,[team])}
pass('Expired, revoked, future or Family Video-only coverage fails closed on each request');
for(const [a,b] of [
 ['update auth.users set email_confirmed_at=null where id=$1','update auth.users set email_confirmed_at=now() where id=$1'],
 ['update auth.users set deleted_at=now() where id=$1','update auth.users set deleted_at=null where id=$1'],
 ["update auth.users set banned_until=now()+interval '1 day' where id=$1",'update auth.users set banned_until=null where id=$1'],
 ['insert into private.team_logins values($1)','delete from private.team_logins where user_id=$1'],
 ['insert into private.deletion_test_block values($1)','delete from private.deletion_test_block where user_id=$1'],
 ["update auth.sessions set not_after=now()-interval '1 minute' where user_id=$1",'update auth.sessions set not_after=null where user_id=$1']
]){await admin();await db.query(a,[owner]);await as();await no(()=>rpc('context'));await admin();await db.query(b,[owner])}
await as(owner,uuid());await no(()=>rpc('context'));await admin();await db.exec('set role anon');await no(()=>rpc('context'));
pass('Anonymous, managed, unconfirmed, banned, deleted, expired-session and deletion-frozen users are denied');
await as();await rpc('delete',{id:copy.id,revision:1});assert.equal((await rpc('delete',{id:copy.id,revision:1})).deleted,true);
await admin();assert.equal((await db.query('select count(*)::int n from public.team_events')).rows[0].n,1);
await db.query('delete from public.team_events where id=$1',[event]);assert.equal((await db.query('select event_id from private.practice_plans where id=$1',[payload.id])).rows[0].event_id,null);
await db.query('delete from auth.users where id=$1',[owner]);const kept=(await db.query('select * from private.practice_plans where id=$1',[payload.id])).rows[0];assert.equal(kept.created_by,null);assert.equal(kept.updated_by,null);assert.equal(kept.title,update.title);
await db.query('delete from public.teams where id=$1',[team]);assert.equal((await db.query('select count(*)::int n from private.practice_plans')).rows[0].n,0);
pass('Plan deletion leaves the event; deleting an event unlinks its plan; coach deletion preserves shared work and team deletion removes it');
await db.close();
