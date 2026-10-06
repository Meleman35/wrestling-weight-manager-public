import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=createRequire(import.meta.url)('@electric-sql/pglite');
const migration=await readFile(new URL('../supabase/migrations/20261005011326_billing_runtime_identity.sql',import.meta.url),'utf8');
// Minimal synthetic Vault/entropy stubs exercise migration atomicity and role
// permissions. They are never deployed and do not claim to test Vault crypto.
async function fixture({fail=false}={}){
 const db=new PGlite();
 await db.exec(`create schema extensions;create schema vault;
 create role anon;create role authenticated;
 create function extensions.gen_random_bytes(n integer) returns bytea language sql as $$select decode(repeat('ab',n),'hex')$$;
 create table vault.secrets(id uuid default gen_random_uuid(),name text unique,secret text,description text);
 revoke all on schema vault from public;
 create function vault.create_secret(s text,n text,d text) returns uuid language plpgsql as $$declare result uuid;begin
 ${fail?"raise exception 'synthetic provider error containing private data';":"insert into vault.secrets(name,secret,description) values(n,s,d) returning id into result;return result;"}
 end$$;`);
 return db;
}
let db;
try {
 db=await fixture({fail:true});
 await assert.rejects(db.exec(migration),e=>e.message==='WM_BILLING_IDENTITY_SETUP_FAILED');
 await db.exec('rollback');
 assert.equal((await db.query("select count(*)::int as n from pg_roles where rolname like 'wm_billing_%'")).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int as n from vault.secrets')).rows[0].n,0);
 await db.close();db=await fixture();
 await db.exec(migration);
 const roles=(await db.query("select rolname,rolcanlogin,rolinherit,rolsuper,rolbypassrls,rolcreatedb,rolcreaterole,rolreplication,rolconnlimit from pg_roles where rolname like 'wm_billing_%' order by rolname")).rows;
 assert.equal(roles.length,2);
 for(const r of roles){for(const key of ['rolinherit','rolsuper','rolbypassrls','rolcreatedb','rolcreaterole','rolreplication'])assert.equal(r[key],false);assert.equal(r.rolcanlogin,r.rolname==='wm_billing_service');}
 assert.equal(roles.find(r=>r.rolcanlogin).rolconnlimit,8);
 const membership=(await db.query("select m.admin_option,m.inherit_option,m.set_option from pg_auth_members m join pg_roles r on r.oid=m.roleid join pg_roles u on u.oid=m.member where r.rolname='wm_billing_runtime' and u.rolname='wm_billing_service'")).rows[0];
 assert.deepEqual(membership,{admin_option:false,inherit_option:false,set_option:true});
 assert.equal((await db.query("select count(*)::int as n from vault.secrets where name='wm-billing-database-url' and secret like 'postgresql://wm_billing_service.vfocpoyexnjsjpxhhyqr:%@aws-0-us-west-2.pooler.supabase.com:5432/postgres'")).rows[0].n,1);
 for(const role of ['anon','authenticated','wm_billing_service','wm_billing_runtime']){
  await db.exec('set role '+role);await assert.rejects(db.query('select secret from vault.secrets'),/permission/);await db.exec('reset role');
 }
 await assert.rejects(db.exec(migration),e=>e.message==='WM_BILLING_IDENTITY_ALREADY_EXISTS');await db.exec('rollback');
 assert.equal((await db.query('select count(*)::int as n from vault.secrets')).rows[0].n,1);
 console.log('Billing identity PostgreSQL checks passed: restricted roles, explicit membership, private credential store, atomic failure and refusal to overwrite an existing identity.');
}catch(error){console.error(error.message,error.code??'');process.exitCode=1;}finally{await db?.close();}
