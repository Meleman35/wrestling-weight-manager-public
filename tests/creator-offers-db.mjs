import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import assert from 'node:assert/strict';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
const db=new PGlite(),owner=uuid(),other=uuid(),sid=uuid(),otherSid=uuid();
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
await db.exec(await readFile('supabase/creator-offers.sql','utf8'));
await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'creator@example.test',now()),($2,'staff@example.test',now())",[owner,other]);
await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4)',[sid,owner,otherSid,other]);
const admin=()=>db.exec('reset role');
const as=async(u,s,extra={})=>{await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,session_id:s,role:'authenticated',...extra})]);await db.exec('set role authenticated')};
const rpc=async(a,d={})=>(await db.query('select public.creator_offers_request($1,$2) r',[a,d])).rows[0].r;
const no=async f=>assert.rejects(f);const pass=s=>console.log('PASS',s);
await as(owner,sid);assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
await as(other,otherSid,{email:'creator@example.test',user_metadata:{creator:true},app_metadata:{role:'creator'}});assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
pass('No account is auto-enrolled; an email or claimed creator role never grants access');
await admin();await db.query('insert into private.creator_accounts(user_id) values($1)',[owner]);
await as(owner,sid);assert.equal((await rpc('access')).creator,true);let dashboard=await rpc('dashboard');assert.equal(dashboard.trial.days,7);assert.equal(dashboard.trial.status,'awaiting_billing');assert.equal(dashboard.billing_connected,false);assert.equal(dashboard.redemption_available,false);
for(const table of ['creator_accounts','creator_offer_drafts','creator_trial_policy','creator_offer_events']){
 await no(()=>db.query('select * from private.'+table));await no(()=>db.query('delete from private.'+table));
}
await no(()=>db.query('select private.creator_access()'));pass('Server-only tables and helper access stay denied, including for the Creator');
const offer={id:uuid(),code:' sample20 ',product:'team_pro_year',discount_percent:20,billing_periods:1,redemption_limit:100,expires_at:new Date(Date.now()+86400000*30).toISOString()};
let saved=await rpc('create',offer);assert.equal(saved.status,'draft');assert.deepEqual(await rpc('create',offer),saved);
dashboard=await rpc('dashboard');assert.equal(dashboard.offers.length,1);assert.equal(dashboard.offers[0].code,'SAMPLE20');assert.equal(dashboard.events.length,1);
await no(()=>rpc('create',{...offer,discount_percent:21}));await no(()=>rpc('create',{...offer,id:uuid()}));
for(const diff of [{discount_percent:0},{discount_percent:101},{billing_periods:0},{billing_periods:13},{redemption_limit:0},{redemption_limit:25001},{expires_at:'2000-01-01'},{expires_at:'infinity'},{expires_at:'2030-01-01'},{code:'<script>'},{product:'admin'},{status:'active'},{discount_percent:null}])await no(()=>rpc('create',{...offer,id:uuid(),...diff}));
pass('Drafts normalize codes, reject unsafe terms and duplicate codes, and retry without duplicate history');
saved=await rpc('update',{...offer,code:'SAMPLE25',discount_percent:25,revision:1});assert.equal(saved.revision,2);await no(()=>rpc('update',{...offer,revision:1}));
await rpc('archive',{id:offer.id,revision:2});await no(()=>rpc('update',{...offer,revision:3}));
await rpc('trial',{requested:false,revision:1});await no(()=>rpc('trial',{requested:true,revision:1}));await no(()=>rpc('trial',{requested:true,revision:2,days:30}));
assert.equal((await rpc('dashboard')).trial.requested,false);await rpc('trial',{requested:true,revision:2});
for(const action of ['publish','redeem','start_trial','grant','activate'])await no(()=>rpc(action));
pass('Stale edits and archived drafts cannot overwrite current records; no action can activate billing or entitlements');
await as(other,otherSid);await no(()=>rpc('dashboard'));await no(()=>rpc('archive',{id:offer.id,revision:3}));await no(()=>rpc('trial',{requested:false,revision:3}));
await as(owner,uuid());assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
for(const change of [
 ['update auth.users set email_confirmed_at=null where id=$1','update auth.users set email_confirmed_at=now() where id=$1'],
 ['update auth.users set deleted_at=now() where id=$1','update auth.users set deleted_at=null where id=$1'],
 ["update auth.users set banned_until=now()+interval '1 day' where id=$1",'update auth.users set banned_until=null where id=$1'],
 ['insert into private.team_logins values($1)','delete from private.team_logins where user_id=$1'],
 ['insert into private.deletion_test_block values($1)','delete from private.deletion_test_block where user_id=$1'],
 ["update auth.sessions set not_after=now()-interval '1 minute' where user_id=$1",'update auth.sessions set not_after=null where user_id=$1']
 ]){await admin();await db.query(change[0],[owner]);await as(owner,sid);assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));await admin();await db.query(change[1],[owner])}
pass('Other users, revoked sessions, unconfirmed/banned/deleted accounts, managed logins and deletion-frozen users are denied');
await as(owner,sid);assert.equal((await rpc('access')).creator,true);await admin();await db.exec('delete from private.creator_accounts');await as(owner,sid);await no(()=>rpc('dashboard'));
await admin();await db.query('insert into private.creator_accounts(user_id) values($1)',[owner]);await db.query('delete from auth.users where id=$1',[owner]);
for(const table of ['creator_accounts','creator_offer_drafts','creator_offer_events'])assert.equal((await db.query('select count(*)::integer n from private.'+table)).rows[0].n,0);
assert.equal((await db.query('select count(*)::integer n from private.creator_trial_policy')).rows[0].n,1);
await db.exec('set role anon');await no(()=>rpc('access'));pass('Revocation takes effect immediately; personal deletion erases owner drafts/history and anonymous RPCs are denied');
await db.close();
