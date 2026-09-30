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
 create table public.organizations(id uuid primary key,name text);
 create table public.athlete_profiles(id uuid primary key);
 create table public.athletes(id uuid primary key,organization_id uuid constraint athletes_organization_id_fkey references public.organizations(id) on delete cascade,profile_id uuid references public.athlete_profiles(id) on delete restrict);
 create table public.teams(id uuid primary key,organization_id uuid constraint teams_organization_id_fkey references public.organizations(id) on delete cascade,name text);
 create table public.team_athletes(team_id uuid references public.teams(id) on delete cascade,athlete_id uuid references public.athletes(id) on delete cascade);
 create table public.team_memberships(team_id uuid references public.teams(id) on delete cascade,user_id uuid,active boolean,role text,permissions jsonb);
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
 await db.query('insert into public.organizations values($1,$2)',[o,'Fixture organization']);
 await db.query('insert into public.teams values($1,$2,$3)',[t,o,'Fixture team']);
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
 await db.exec('reset role;alter table public.unavailable_messages rename to communication_messages');
 const scopesMigration=fs.readdirSync(path.join(root,'supabase/migrations')).filter(x=>x.endsWith('_account_deletion_scope_preflight.sql'));assert.equal(scopesMigration.length,1);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',scopesMigration[0]),'utf8'));
 const scopeCall=async()=>(await db.query('select public.account_deletion_scope_preflight() r')).rows[0].r;
 await as({},'anon');await assert.rejects(scopeCall,/permission denied/);
 await as(claims(b,sb));assert.deepEqual(await scopeCall(),{enabled:false});
 await as();await assert.rejects(()=>db.query('select public.account_deletion_scope_preflight($1)',[b]),/does not exist/);
 let scopes=(await scopeCall()).scopes;
 assert.equal(scopes.teams.length,1);assert.equal(scopes.teams[0].id,t);assert.equal(scopes.teams[0].direct_admin,true);assert.equal(scopes.teams[0].inherited_admin,false);assert.equal(scopes.teams[0].needs_handoff,true);assert.deepEqual(scopes.organizations,[]);
 for(const v of [claims(a,sb),{...claims(),exp:0},{...claims(),role:'anon'}]){await as(v);assert.deepEqual(await scopeCall(),{enabled:false});}
 pass('Scope preview inherits live-session enrollment, rejects supplied target IDs, and reveals only current administrator workspaces');
 await db.exec('reset role');
 const [otherOrg,otherTeam,athlete,profile]=Array.from({length:4},randomUUID);
 await db.query('insert into public.organizations values($1,$2)',[otherOrg,'Other organization']);
 await db.query('insert into public.teams values($1,$2,$3)',[otherTeam,otherOrg,'Other team']);
 await db.query("insert into public.organization_memberships values($1,$2,'organization_admin'),($3,$4,'organization_admin')",[o,a,otherOrg,b]);
 await db.query('insert into public.athlete_profiles values($1)',[profile]);
 await db.query('insert into public.athletes values($1,$2,$3)',[athlete,o,profile]);
 await db.query('insert into public.team_athletes values($1,$2),($3,$2)',[t,athlete,otherTeam]);
 await as();out=await scopeCall();scopes=out.scopes;
 assert.equal(out.scope_version,1);assert.equal(out.deletion_enabled,false);assert.equal(scopes.teams.length,1);assert.equal(scopes.teams[0].inherited_admin,true);
 assert.deepEqual(scopes.organizations,[{id:o,name:'Fixture organization',team_count:1,athlete_count:1,needs_handoff:true}]);
 assert.ok(!JSON.stringify(out).includes(otherOrg));assert.ok(!JSON.stringify(out).includes(otherTeam));assert.ok(!JSON.stringify(out).includes(profile));
 pass('Direct/inherited administration is distinguished; organizations show linked counts without leaking unrelated workspaces or member identities');
 await db.exec('reset role');await db.query("update auth.users set banned_until=null where id=$1",[c]);
 await as();assert.equal((await scopeCall()).scopes.organizations[0].needs_handoff,false);
 await db.exec('reset role');await db.query('insert into private.team_logins values($1)',[c]);
 await as();assert.equal((await scopeCall()).scopes.organizations[0].needs_handoff,true);
 await db.exec('reset role');await db.query('delete from private.team_logins where user_id=$1',[c]);await db.query('update auth.users set email_confirmed_at=null where id=$1',[c]);
 await as();assert.equal((await scopeCall()).scopes.teams[0].needs_handoff,true);
 pass('Managed and unconfirmed alternate administrators cannot silently satisfy a handoff');
 await db.exec('reset role');
 const adminMigration=fs.readdirSync(path.join(root,'supabase/migrations')).filter(x=>x.endsWith('_account_deletion_admin_execution.sql'));assert.equal(adminMigration.length,1);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',adminMigration[0]),'utf8'));
 const removeAdmin=async(kind='team',id=t,word='delete',request=randomUUID())=>(await db.query('select public.account_remove_my_admin_access($1,$2,$3,$4) r',[kind,id,word,request])).rows[0].r;
 const rows=async()=>(await db.query(`select jsonb_build_object('users',(select jsonb_agg(id order by id) from auth.users x),'profiles',(select jsonb_agg(x order by id) from public.profiles x),'athletes',(select jsonb_agg(x order by id) from public.athletes x),'athlete_profiles',(select jsonb_agg(x order by id) from public.athlete_profiles x),'teams',(select jsonb_agg(x order by id) from public.teams x),'organizations',(select jsonb_agg(x order by id) from public.organizations x),'messages',(select jsonb_agg(x order by sender_user_id) from public.communication_messages x),'objects',(select jsonb_agg(x order by owner_id) from storage.objects x)) r`)).rows[0].r;
 await db.exec(`alter table public.team_memberships add column athlete_id uuid,add column id uuid default gen_random_uuid();
 alter table public.organization_memberships add column id uuid default gen_random_uuid();
 create unique index team_memberships_unique_role on public.team_memberships(team_id,user_id,role,athlete_id) nulls not distinct;
 create table private.wrestling_role_approvals(source text,membership_id uuid,snapshot jsonb);
 create table private.wrestling_role_review_log(source text,membership_id uuid,snapshot jsonb,reviewer_id uuid,action text);`);
 await db.exec(fs.readFileSync(path.join(root,'tests/fixtures/account-admin-role-functions.sql'),'utf8'));
 const preserved=await rows();
 await as({},'anon');await assert.rejects(()=>removeAdmin(),/permission denied/);
 await as(claims(b,sb));await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_SIGN_IN_REQUIRED/);
 await as();assert.deepEqual((await scopeCall()).actions,{administrator:true,personal:false,team:false,organization:false,all:false});
 await assert.rejects(()=>db.query('select * from private.account_admin_removal_receipts'),/permission denied/);
 for(const phrase of ['DELETE',' delete','delete ','',null])await assert.rejects(()=>removeAdmin('team',t,phrase),/ADMIN_REMOVAL_INVALID_CONFIRMATION/);
 for(const kind of ['personal','all','bad',null])await assert.rejects(()=>removeAdmin(kind),/ADMIN_REMOVAL_INVALID_CONFIRMATION/);
 await assert.rejects(()=>removeAdmin('team',otherTeam),/ADMIN_REMOVAL_ROLE_CHANGED/);
 await assert.rejects(()=>removeAdmin('organization',otherOrg),/ADMIN_REMOVAL_ROLE_CHANGED/);
 await assert.rejects(()=>removeAdmin('team',null),/ADMIN_REMOVAL_INVALID_CONFIRMATION/);
 await assert.rejects(()=>removeAdmin('team',t,'delete',null),/ADMIN_REMOVAL_INVALID_CONFIRMATION/);
 pass('Role mutation is enrolled caller-only, rejects other workspaces and erasure scopes, requires exact confirmation and keeps receipts private');
 await assert.rejects(()=>removeAdmin('organization',o),/ADMIN_REMOVAL_HANDOFF_REQUIRED/);
 await db.exec('reset role');await db.query('delete from public.organization_memberships where organization_id=$1 and user_id=$2',[o,a]);
 await as();await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_HANDOFF_REQUIRED/);
 await db.exec('reset role');await db.query('update public.team_memberships set active=true where user_id=$1',[b]);
 for(const [change,undo] of [
  ["update auth.users set banned_until=now()+interval '1 day' where id=$1","update auth.users set banned_until=null where id=$1"],
  ["update auth.users set email_confirmed_at=null where id=$1","update auth.users set email_confirmed_at=now() where id=$1"],
  ["update auth.users set deleted_at=now() where id=$1","update auth.users set deleted_at=null where id=$1"],
  ['insert into private.team_logins values($1)','delete from private.team_logins where user_id=$1']
 ]){await db.query(change,[b]);await as();await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_HANDOFF_REQUIRED/);await db.exec('reset role');await db.query(undo,[b]);}
 await db.query('update public.team_memberships set active=false where user_id=$1',[b]);
 await as();await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_HANDOFF_REQUIRED/);
 pass('The server blocks sole-admin removal and excludes inactive, banned, deleted, unconfirmed and managed replacements');
 await db.exec('reset role');await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$2,'organization_admin')",[o,a]);
 await db.query("update public.team_memberships set permissions='{"+'"team_admin":true,"record_matches":true'+"}' where team_id=$1 and user_id=$2",[t,a]);
 const request=randomUUID();await as();const result=await removeAdmin('team',t,'delete',request);
 assert.equal(result.status,'removed');assert.equal(result.inherited_admin_remaining,true);assert.equal(result.personal_account_preserved,true);assert.equal(result.participation_role,'assistant_coach');
 assert.deepEqual(await removeAdmin('team',t,'delete',request),result);
 await assert.rejects(()=>removeAdmin('organization',o,'delete',request),/ADMIN_REMOVAL_REQUEST_MISMATCH/);
 await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_ROLE_CHANGED/);
 await db.exec('reset role');assert.deepEqual((await db.query('select role,permissions,active from public.team_memberships where team_id=$1 and user_id=$2',[t,a])).rows,[{role:'assistant_coach',permissions:{record_matches:true},active:true}]);
 assert.deepEqual(await rows(),preserved);
 pass('Direct role removal preserves coaching participation, unrelated permissions and all identities/content; inherited access is explicit and duplicate requests are idempotent');
 // Regranting later must not be undone by a retry of the old successful request.
 await db.query("update public.team_memberships set role='head_coach' where team_id=$1 and user_id=$2",[t,a]);
 await as();assert.deepEqual(await removeAdmin('team',t,'delete',request),result);
 await db.exec('reset role');assert.equal((await db.query('select role from public.team_memberships where team_id=$1 and user_id=$2',[t,a])).rows[0].role,'head_coach');
 await db.query('update auth.users set email_confirmed_at=now() where id=$1',[c]);
 await as();const orgResult=await removeAdmin('organization',o);assert.equal(orgResult.status,'removed');assert.equal(orgResult.personal_account_preserved,true);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from public.organization_memberships where organization_id=$1 and user_id=$2',[o,a])).rows[0].n,0);
 assert.equal((await db.query('select role from public.team_memberships where team_id=$1 and user_id=$2',[t,a])).rows[0].role,'head_coach');
 // Restore only the fixture's changed eligibility field before preservation comparison.
 await db.query('update auth.users set email_confirmed_at=null where id=$1',[c]);
 // Timestamp changes for b were deliberate test setup, so compare identities/content excluding mutable Auth status.
 const finalPreserved=await rows();delete finalPreserved.users;const withoutUsers={...preserved};delete withoutUsers.users;assert.deepEqual(finalPreserved,withoutUsers);
 pass('A retry cannot undo a later regrant; organization removal preserves direct team roles, other accounts, workspaces, media and profiles');
 // An insertion failure must roll back the role change and must not report completion.
 await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$2,'organization_admin')",[o,a]);
 await db.exec("create function private.fail_receipt() returns trigger language plpgsql as $$begin raise exception 'receipt unavailable';end$$;create trigger fail_receipt before insert on private.account_admin_removal_receipts for each row execute function private.fail_receipt();");
 await as();await assert.rejects(()=>removeAdmin(),/receipt unavailable/);
 await db.exec('reset role');assert.equal((await db.query('select role from public.team_memberships where team_id=$1 and user_id=$2',[t,a])).rows[0].role,'head_coach');
 await db.exec('drop trigger fail_receipt on private.account_admin_removal_receipts;drop function private.fail_receipt();');
 for(const bad of [claims(a,sb),{...claims(),exp:0}]){await as(bad);await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_SIGN_IN_REQUIRED/);}
 await db.exec('reset role');
 const removalDefs=(await db.query("select n.nspname,p.prosecdef,p.provolatile,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='account_remove_my_admin_access' order by n.nspname")).rows;
 assert.deepEqual(removalDefs.map(x=>x.prosecdef),[true,false]);assert.ok(removalDefs.every(x=>x.provolatile==='v'&&x.proconfig.includes('search_path=\"\"')));
 pass('Role and receipt commit together; failed receipts roll back changes, expired/wrong sessions fail, and the public function stays invoker-only');
 await db.query('delete from public.organization_memberships where organization_id=$1 and user_id=$2',[o,a]);
 await db.query('update public.team_memberships set active=true where user_id=$1',[b]);
 await db.query(`insert into public.team_memberships(team_id,user_id,active,role,permissions,athlete_id) values
   ($1,$2,true,'assistant_coach','{"team_admin":true,"schedule":true}',null),
   ($1,$2,true,'manager','{"team_admin":true,"equipment":true}',null),
   ($1,$2,true,'parent_guardian','{"unchanged":true}',$3),
   ($1,$2,false,'athlete','{"unchanged":true}',$3)`,[t,a,athlete]);
 await db.query("insert into private.wrestling_role_approvals select 'team',id,'{}'::jsonb from public.team_memberships where team_id=$1 and user_id=$2 and role='head_coach'",[t,a]);
 await as();assert.equal((await db.query('select public.is_team_admin($1) r',[t])).rows[0].r,true);
 await removeAdmin();assert.equal((await db.query('select public.is_team_admin($1) r',[t])).rows[0].r,false);
 await db.exec('reset role');
 const roleRows=(await db.query('select role,active,permissions from public.team_memberships where team_id=$1 and user_id=$2 order by role',[t,a])).rows;
 assert.deepEqual(roleRows,[{role:'assistant_coach',active:true,permissions:{schedule:true}},{role:'athlete',active:false,permissions:{unchanged:true}},{role:'manager',active:true,permissions:{equipment:true}},{role:'parent_guardian',active:true,permissions:{unchanged:true}}]);
 assert.equal((await db.query('select count(*)::int n from private.wrestling_role_approvals')).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from private.wrestling_role_review_log where action='assignment_changed'")).rows[0].n,1);
 pass('Actual permission helpers deny removed administration; multiple roles avoid unique-index collisions, preserve guardian/athlete participation and invalidate old role approvals');
 await db.query("update public.team_memberships set active=false where team_id=$1 and user_id=$2 and role='assistant_coach'",[t,a]);
 await db.query("insert into public.team_memberships(team_id,user_id,active,role,permissions) values($1,$2,true,'head_coach','{}')",[t,a]);
 await as();await assert.rejects(()=>removeAdmin(),/ADMIN_REMOVAL_MEMBERSHIP_REVIEW/);
 await db.exec('reset role');assert.deepEqual((await db.query("select role,active from public.team_memberships where team_id=$1 and user_id=$2 and role in ('head_coach','assistant_coach') order by role",[t,a])).rows,[{role:'assistant_coach',active:false},{role:'head_coach',active:true}]);
 await db.query("delete from public.team_memberships where team_id=$1 and user_id=$2 and role='head_coach'",[t,a]);
 await db.query("update public.team_memberships set active=true where team_id=$1 and user_id=$2 and role='assistant_coach'",[t,a]);
 pass('An inactive assistant-coach conflict blocks atomically without reactivating an old membership or removing the current head coach');
 // Restore the original fixture shape for the independent preservation guards below.
 await db.query("delete from public.team_memberships where team_id=$1 and user_id=$2 and role in ('athlete','manager','parent_guardian')",[t,a]);
 await db.query("update public.team_memberships set role='head_coach' where team_id=$1 and user_id=$2",[t,a]);
 await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$2,'organization_admin')",[o,a]);
 await db.exec('reset role');
 const beforeScope=(await db.query('select (select count(*) from auth.users) users,(select count(*) from public.profiles) profiles,(select count(*) from public.athlete_profiles) athlete_profiles,(select count(*) from public.athletes) athletes,(select count(*) from public.teams) teams')).rows;
 await as();await scopeCall();await db.exec('reset role');
 assert.deepEqual((await db.query('select (select count(*) from auth.users) users,(select count(*) from public.profiles) profiles,(select count(*) from public.athlete_profiles) athlete_profiles,(select count(*) from public.athletes) athletes,(select count(*) from public.teams) teams')).rows,beforeScope);
 await assert.rejects(()=>db.query('delete from public.organizations where id=$1',[o]),/foreign key constraint/);
 await assert.rejects(()=>db.query('delete from public.organizations where id=$1',[otherOrg]),/foreign key constraint/);
 assert.deepEqual((await db.query('select (select count(*) from auth.users) users,(select count(*) from public.profiles) profiles,(select count(*) from public.athlete_profiles) athlete_profiles,(select count(*) from public.athletes) athletes,(select count(*) from public.teams) teams')).rows,beforeScope);
 assert.equal((await db.query('select count(*)::int n from public.team_athletes where athlete_id=$1',[athlete])).rows[0].n,2);
 pass('Organization deletion is blocked before it can cascade into teams, shared athletes or personal profiles');
 await db.query('delete from public.teams where id=$1',[t]);
 await assert.rejects(()=>db.query('delete from public.organizations where id=$1',[o]),/foreign key constraint/);
 assert.equal((await db.query('select count(*)::int n from public.team_athletes where athlete_id=$1 and team_id=$2',[athlete,otherTeam])).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from public.athlete_profiles where id=$1',[profile])).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from public.profiles')).rows[0].n,2);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,3);
 pass('Synthetic team removal preserves personal identities, athlete profiles and the same athlete’s other team link; athlete guard independently blocks organization cascade');
 await db.query('delete from public.organization_memberships where user_id=$1',[a]);
 await as();out=await scopeCall();assert.equal(out.enabled,true);assert.deepEqual(out.scopes,{teams:[],organizations:[]});assert.equal(out.subject_id,a);assert.equal(out.deletion_enabled,false);
 pass('A personal-only account retains its personal deletion preview without any administrator targets');
 await db.exec('reset role');
 const scopeDefs=(await db.query("select p.prosecdef,p.provolatile,p.proconfig,p.pronargs from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='account_deletion_scope_preflight' order by n.nspname")).rows;
 assert.deepEqual(scopeDefs.map(x=>x.prosecdef),[true,false]);assert.ok(scopeDefs.every(x=>x.provolatile==='s'&&x.pronargs===0&&x.proconfig.includes('search_path=""')));
 pass('New scope functions are stable, argument-free and fixed-search-path, with an invoker public wrapper');
 fs.writeFileSync(path.join(root,'validation/account-deletion-phone-db.json'),JSON.stringify({passed,engine:'PGlite with actual preflight migration and minimal catalog-shaped synthetic tables including actual preservation constraints; not full erasure acceptance',productionDataChanged:false},null,2));await db.close();
})().catch(e=>{console.error(e);process.exit(1);});
