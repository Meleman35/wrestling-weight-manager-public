import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import assert from 'node:assert/strict';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
const db=new PGlite(),owner=uuid(),linked=uuid(),other=uuid(),sid=uuid(),lsid=uuid(),osid=uuid();
await db.exec(`create schema private;create schema auth;create role anon;create role authenticated;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id) on delete cascade,not_after timestamptz);
 create table private.team_logins(user_id uuid primary key);
 create table private.scoped_deletion_jobs(subject_hash text,personal boolean,sealed_at timestamptz);
 create function private.scoped_deletion_access_ok() returns boolean language sql as $$select not exists(select 1 from private.scoped_deletion_jobs where personal and sealed_at is not null and subject_hash=encode(sha256(convert_to(auth.uid()::text,'UTF8')),'hex'))$$;
 create function private.scoped_deletion_freeze() returns trigger language plpgsql as $$begin return coalesce(new,old);end$$;
 grant usage on schema public,private,auth to authenticated,anon;`);
await db.exec(await readFile('supabase/creator-offers.sql','utf8'));
const migration=await readFile('supabase/creator-linked-access.sql','utf8');
await db.exec(migration.split('-- BEGIN LINKED CREATOR CORE')[1].split('-- END LINKED CREATOR CORE')[0]);
await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'owner@example.test',now()),($2,'linked@example.test',now()),($3,'other@example.test',now())",[owner,linked,other]);
await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4),($5,$6)',[sid,owner,lsid,linked,osid,other]);
const admin=()=>db.exec('reset role');
const as=async(u,s,extra={})=>{await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,session_id:s,role:'authenticated',...extra})]);await db.exec('set role authenticated')};
const rpc=async(a,d={},modern=true)=>(await db.query('select public.creator_offers_request($1,$2) r',[a,modern?{...d,client:'creator-linked-v1'}:d])).rows[0].r;
const no=f=>assert.rejects(f);const pass=s=>console.log('PASS',s);
await as(linked,lsid);assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
await admin();await db.query('insert into private.creator_accounts(user_id) values($1)',[owner]);
await as(linked,lsid);assert.equal((await rpc('access')).creator,false);await no(()=>rpc('link',{user_id:linked}));
await admin();await db.query('update private.creator_accounts set linked_user_id=$1',[linked]);
await no(()=>db.query('update private.creator_accounts set linked_user_id=user_id'));
await as(owner,sid);assert.equal((await rpc('access',{},false)).home_mode,'dedicated');
await as(linked,lsid);assert.equal((await rpc('access',{},false)).creator,false);await no(()=>rpc('dashboard',{},false));
assert.equal((await rpc('access')).home_mode,'team');pass('Only the private reviewed link grants access; old clients do not hijack the personal team home');
for(const t of ['creator_accounts','creator_offer_drafts','creator_offer_events','creator_trial_policy']){await no(()=>db.query('select * from private.'+t));await no(()=>db.query('update private.'+t+' set '+(t==='creator_accounts'?'linked_user_id=null':t==='creator_trial_policy'?'requested=true':t==='creator_offer_events'?"action='trial'":"status='draft'")))}
await no(()=>db.query('select private.creator_access()'));pass('Linked login cannot read tables, change grants or invoke the private helper directly');
const offer={id:uuid(),code:'LINKTEST20',product:'team_pro_year',discount_percent:20,billing_periods:1,redemption_limit:25,expires_at:new Date(Date.now()+86400000*20).toISOString()};
const created=await rpc('create',offer);assert.deepEqual(await rpc('create',offer),created);
let d=await rpc('dashboard');assert.equal(d.events[0].actor_label,'This login');assert.equal(d.offers.length,1);
await admin();let row=(await db.query('select created_by from private.creator_offer_drafts where id=$1',[offer.id])).rows[0];assert.equal(row.created_by,owner);
row=(await db.query('select actor_id from private.creator_offer_events where offer_id=$1',[offer.id])).rows[0];assert.equal(row.actor_id,linked);
await as(owner,sid);d=await rpc('dashboard',{},false);assert.equal(d.offers.length,1);assert.equal(d.events[0].actor_label,'Linked personal login');
await rpc('update',{...offer,discount_percent:30,revision:1},false);
await as(linked,lsid);await no(()=>rpc('update',{...offer,revision:1}));d=await rpc('dashboard');assert.equal(d.offers[0].discount_percent,30);assert.equal(d.events[0].actor_label,'Creator owner');
await rpc('update',{...offer,code:'LINKTEST40',discount_percent:40,revision:2});
await no(()=>rpc('create',{...offer,id:uuid(),workspace_owner:linked}));await no(()=>rpc('update',{...offer,revision:3,created_by:linked}));
await rpc('trial',{requested:false,revision:1});await as(owner,sid);assert.equal((await rpc('dashboard')).trial.requested,false);
for(const a of ['publish','redeem','start_trial','grant','activate','link','unlink'])await no(()=>rpc(a));
pass('Both logins share the owner drafts and trial policy, record the actual actor and reject stale edits or privilege fields');
await as(other,osid,{email:'owner@example.test',user_metadata:{creator:true},app_metadata:{role:'creator'}});assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
await as(linked,uuid());assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
for(const [sql,undo,target] of [
 ['update auth.users set email_confirmed_at=null where id=$1','update auth.users set email_confirmed_at=now() where id=$1',linked],
 ["update auth.users set banned_until=now()+interval '1 day' where id=$1",'update auth.users set banned_until=null where id=$1',linked],
 ["update auth.users set banned_until=now()+interval '1 day' where id=$1",'update auth.users set banned_until=null where id=$1',owner],
 ['update auth.users set deleted_at=now() where id=$1','update auth.users set deleted_at=null where id=$1',owner],
 ['insert into private.team_logins values($1)','delete from private.team_logins where user_id=$1',linked],
 ['insert into private.team_logins values($1)','delete from private.team_logins where user_id=$1',owner],
 ["update auth.sessions set not_after=now()-interval '1 minute' where user_id=$1",'update auth.sessions set not_after=null where user_id=$1',linked],
 ["insert into private.scoped_deletion_jobs values(encode(sha256(convert_to($1::text,'UTF8')),'hex'),true,now())","delete from private.scoped_deletion_jobs where subject_hash=encode(sha256(convert_to($1::text,'UTF8')),'hex')",owner],
 ["insert into private.scoped_deletion_jobs values(encode(sha256(convert_to($1::text,'UTF8')),'hex'),true,now())","delete from private.scoped_deletion_jobs where subject_hash=encode(sha256(convert_to($1::text,'UTF8')),'hex')",linked]
]){await admin();await db.query(sql,[target]);await as(linked,lsid);assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));await admin();await db.query(undo,[target])}
pass('Current sessions, owner health of account, managed-login exclusions and both deletion freezes remain required');
await admin();await db.exec('update private.creator_accounts set linked_user_id=null');await as(linked,lsid);await no(()=>rpc('dashboard'));
await as(owner,sid);assert.equal((await rpc('dashboard')).offers.length,1);
await admin();await db.query('update private.creator_accounts set linked_user_id=$1',[linked]);await db.query('delete from auth.users where id=$1',[linked]);
assert.equal((await db.query('select linked_user_id from private.creator_accounts')).rows[0].linked_user_id,null);
assert.equal((await db.query('select count(*)::int n from private.creator_offer_drafts')).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[owner])).rows[0].n,1);
await as(owner,sid);assert.equal((await rpc('dashboard')).offers.length,1);pass('Revoking or deleting the linked login preserves the Creator owner and shared drafts');
await admin();await db.query('update private.creator_accounts set linked_user_id=$1',[other]);await db.query('delete from auth.users where id=$1',[owner]);
assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[other])).rows[0].n,1);
await as(other,osid);assert.equal((await rpc('access')).creator,false);await no(()=>rpc('dashboard'));
await admin();await db.exec('set role anon');await no(()=>rpc('access'));pass('Owner removal ends shared access without deleting the linked personal identity; anonymous access stays denied');
await admin();await db.close();
