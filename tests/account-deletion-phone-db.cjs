'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID}=require('node:crypto');
const {PGlite}=require('@electric-sql/pglite'),root=path.resolve(__dirname,'..');
(async()=>{
 const db=new PGlite(),passed=[],pass=s=>{passed.push(s);console.log('PASS',s);};
 const [a,b,c,sa,sb,t,o]=Array.from({length:7},randomUUID);
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema auth;create schema private;create schema storage;
 grant usage on schema auth,private,public to authenticated;grant usage on schema public to anon;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid primary key,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create table private.team_logins(user_id uuid);
 create table public.profiles(id uuid,photo_path text);
 create table private.wrestling_profiles(user_id uuid,photo_path text);
 create table public.communication_messages(sender_user_id uuid);
 create table public.communication_attachments(uploader_user_id uuid);
 create table public.team_posts(id uuid primary key,author_user_id uuid);
 create table public.team_post_attachments(post_id uuid);
 create table public.teams(id uuid primary key,organization_id uuid);
 create table public.team_memberships(team_id uuid,user_id uuid,active boolean,role text,permissions jsonb);
 create table public.organization_memberships(organization_id uuid,user_id uuid,role text);
 create table public.athlete_guardians(guardian_user_id uuid);
 create table storage.objects(owner uuid,owner_id text);
 `);
 const migration=fs.readdirSync(path.join(root,'supabase/migrations')).filter(x=>x.endsWith('_account_deletion_phone_preflight.sql'));assert.equal(migration.length,1);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',migration[0]),'utf8'));
 for(const u of [a,b,c])await db.query('insert into auth.users values($1,now(),null,null)',[u]);
 await db.query('insert into auth.sessions values($1,$2,null),($3,$4,null)',[sa,a,sb,b]);
 const claims=(u=a,s=sa)=>({role:'authenticated',sub:u,session_id:s,exp:Math.floor(Date.now()/1000)+3600});
 async function as(v=claims(),role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(v)]);await db.exec('set role '+role);}
 const call=async()=>(await db.query('select public.account_deletion_phone_preflight() r')).rows[0].r;
 await as();assert.deepEqual(await call(),{enabled:false});
 await assert.rejects(()=>db.query('select * from private.account_deletion_phone_testers'),/permission denied/);
 await assert.rejects(()=>db.query('insert into private.account_deletion_phone_testers values($1,now(),now())',[a]),/permission denied/);
 await assert.rejects(()=>db.query('select public.account_deletion_phone_preflight($1)',[b]),/does not exist/);
 await as({},'anon');await assert.rejects(call,/permission denied/);
 pass('Default-off enrollment is private; anonymous, self-enrollment and target-account arguments are denied');
 await db.exec('reset role');await db.query("insert into private.account_deletion_phone_testers(user_id,expires_at) values($1,now()+interval '1 day')",[a]);
 await db.query('insert into public.profiles values($1,$2),($3,$4)',[a,'own.jpg',b,'other.jpg']);
 await db.query('insert into private.wrestling_profiles values($1,$2)',[a,'own.jpg']);
 await db.query('insert into public.communication_messages values($1),($1),($2)',[a,b]);
 await db.query('insert into public.communication_attachments values($1),($2)',[a,b]);
 await db.query('insert into public.team_posts values($1,$2)',[randomUUID(),a]);
 await db.exec('insert into public.team_post_attachments select id from public.team_posts');
 await db.query('insert into storage.objects values($1,$2),(null,$2),($3,$4)',[a,a,b,b]);
 await db.query('insert into public.teams values($1,$2)',[t,o]);
 await db.query("insert into public.team_memberships values($1,$2,true,'head_coach','{}')",[t,a]);
 await db.query('insert into public.athlete_guardians values($1)',[a]);
 await as();let out=await call();assert.equal(out.subject_id,a);assert.equal(out.deletion_enabled,false);
 assert.deepEqual(out.counts,{account_photos:1,wrestling_profile_photos:1,messages:2,message_attachments:1,team_posts:1,post_attachments:1,teams:1,teams_needing_handoff:1,guardian_links:1,organization_roles:0,uploaded_objects:2});
 assert.deepEqual(Object.keys(out).sort(),['checked_at','counts','deletion_enabled','enabled','subject_id']);
 pass('Admitted account sees only its aggregate counts, with overlapping upload owners counted once and deletion always disabled');
 await as(claims(b,sb));assert.deepEqual(await call(),{enabled:false});
 for(const v of [claims(a,sb),{...claims(),role:'anon'},{...claims(),session_id:'wrong'},{...claims(),exp:'bad'},{...claims(),exp:'NaN'},{...claims(),exp:'Infinity'},{...claims(),exp:0},{...claims(),exp:null}]){await as(v);assert.deepEqual(await call(),{enabled:false});}
 pass('Other users, mismatched sessions and malformed or expired claims reveal no counts');
 for(const [change,undo] of [
  ["update auth.users set email_confirmed_at=null where id=$1","update auth.users set email_confirmed_at=now() where id=$1"],
  ["update auth.users set banned_until=now()+interval '1 day' where id=$1","update auth.users set banned_until=null where id=$1"],
  ["update auth.users set deleted_at=now() where id=$1","update auth.users set deleted_at=null where id=$1"],
  ["update auth.sessions set not_after=now()-interval '1 day' where user_id=$1","update auth.sessions set not_after=null where user_id=$1"],
  ["update private.account_deletion_phone_testers set expires_at=now()-interval '1 day' where user_id=$1","update private.account_deletion_phone_testers set expires_at=now()+interval '1 day' where user_id=$1"],
  ['insert into private.team_logins values($1)','delete from private.team_logins where user_id=$1']
 ]){await db.exec('reset role');await db.query(change,[a]);await as();assert.deepEqual(await call(),{enabled:false});await db.exec('reset role');await db.query(undo,[a]);}
 pass('Unconfirmed, banned, deleted, expired-session, expired-enrollment and managed identities are excluded');
 await db.query("insert into public.team_memberships values($1,$2,true,'manager','{\"team_admin\":true}')",[t,b]);await as();assert.equal((await call()).counts.teams_needing_handoff,0);
 await db.exec('reset role');await db.query('update public.team_memberships set active=false where user_id=$1',[b]);await as();assert.equal((await call()).counts.teams_needing_handoff,1);
 await db.exec('reset role');await db.query("insert into public.organization_memberships values($1,$2,'organization_admin')",[o,c]);await as();assert.equal((await call()).counts.teams_needing_handoff,0);
 await db.exec('reset role');await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[c]);await as();assert.equal((await call()).counts.teams_needing_handoff,1);
 pass('Administrator warning includes delegated team admins and organization admins, excluding inactive/banned alternatives');
 await db.exec('reset role');const before=(await db.query('select (select count(*) from public.communication_messages) messages,(select count(*) from auth.users) users,(select count(*) from storage.objects) objects')).rows;
 const defs=(await db.query("select p.proname,p.prosecdef,p.provolatile,p.proconfig,p.pronargs from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='account_deletion_phone_preflight' order by n.nspname")).rows;
 assert.equal(defs.length,2);assert.deepEqual(defs.map(x=>x.prosecdef),[true,false]);assert.ok(defs.every(x=>x.provolatile==='s'&&x.pronargs===0&&x.proconfig.includes('search_path=""')));
 await as();await call();await db.exec('reset role');assert.deepEqual((await db.query('select (select count(*) from public.communication_messages) messages,(select count(*) from auth.users) users,(select count(*) from storage.objects) objects')).rows,before);
 await db.exec('alter table public.communication_messages rename to unavailable_messages');await as();await assert.rejects(call,/does not exist/);
 pass('Functions are argument-free, stable and fixed-search-path; no data is removed and missing backend data fails visibly');
 fs.writeFileSync(path.join(root,'validation/account-deletion-phone-db.json'),JSON.stringify({passed,engine:'PGlite with actual preflight migration and minimal catalog-shaped synthetic tables; not full erasure acceptance',productionDataChanged:false},null,2));await db.close();
})().catch(e=>{console.error(e);process.exit(1);});
