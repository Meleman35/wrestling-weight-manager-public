// Local PostgreSQL regression. Requires @electric-sql/pglite@0.5.8.
const { PGlite } = require('@electric-sql/pglite');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..'), checks = [];
const pass = s => { checks.push(s); console.log('PASS', s); };
const db = new PGlite();
const a = '11111111-1111-4111-8111-111111111111', b = '22222222-2222-4222-8222-222222222222';
const call = async (action = 'status', confirmation = null) =>
  (await db.query('select public.account_deletion_request($1, $2) value', [action, confirmation])).rows[0].value;
const asUser = async id => {
  await db.exec('reset role; set role authenticated;');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id || '']);
};
(async () => {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema private;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth, public to authenticated, anon;
    grant execute on function auth.uid() to authenticated;
  `);
  await db.query('insert into auth.users values ($1), ($2)', [a, b]);
  await db.exec(fs.readFileSync(path.join(root, 'supabase/migrations/20260929052714_account_deletion_intake_draft.sql'), 'utf8'));
  await db.exec('set role anon;');
  await assert.rejects(call(), e => e.code === '42501');
  await asUser(null);
  await assert.rejects(call(), e => e.code === '42501');
  pass('Anonymous and missing-identity calls are denied');

  await asUser(a);
  assert.equal((await call()).enabled, false);
  await assert.rejects(call('request', 'DELETE'), e => e.code === '55000');
  await assert.rejects(db.query('insert into public.account_deletion_requests(user_id) values ($1)', [a]), e => e.code === '42501');
  pass('Intake is disabled by default and direct inserts cannot bypass that switch');

  await db.exec('reset role; update public.account_deletion_settings set enabled = true;');
  await asUser(a);
  await assert.rejects(call('request', 'delete'), e => e.code === '22023');
  await assert.rejects(call('erase_everything', 'DELETE'), e => e.code === '22023');
  await assert.rejects(db.query('insert into public.account_deletion_requests(user_id) values ($1)', [b]), e => e.code === '42501');
  pass('Confirmation/action checks and owner-only RLS reject invalid requests');

  const first = (await call('request', 'DELETE')).request;
  assert.equal(first.status, 'requested');
  assert.equal(Date.parse(first.deadline_at) - Date.parse(first.requested_at), 30 * 864e5);
  const replay = (await call('request', 'DELETE')).request;
  assert.deepEqual(replay, first);
  assert.equal((await db.query('select * from public.account_deletion_requests')).rows.length, 1);
  pass('A durable receipt survives a lost acknowledgement without duplicate requests or deadline reset');

  await assert.rejects(db.query("update public.account_deletion_requests set status='completed', completed_at=now()"), e => e.code === '42501');
  await assert.rejects(db.query('delete from public.account_deletion_requests'), e => e.code === '42501');
  await assert.rejects(db.query('update public.account_deletion_settings set enabled=false'), e => e.code === '42501');
  await asUser(b);
  await assert.rejects(db.query("insert into public.account_deletion_requests(user_id, status, completed_at, deadline_at) values ($1,'completed',now(),now())", [b]), e => e.code === '42501');
  pass('Clients cannot forge completion, deadlines, configuration or remove request history');
  assert.equal((await call()).request, null);
  assert.equal((await db.query('select * from public.account_deletion_requests')).rows.length, 0);
  const second = (await call('request', 'DELETE')).request;
  assert.notEqual(second.id, first.id);
  pass('A different account sees only its own separate receipt');

  await db.exec('reset role; update public.account_deletion_settings set enabled=false, completion_days=7;');
  await asUser(a);
  assert.deepEqual((await call('request', 'DELETE')).request, first);
  pass('Pausing intake or changing the policy does not lose existing receipts or alter promised deadlines');

  await db.exec('reset role;');
  assert.equal((await db.query('select count(*)::int count from auth.users')).rows[0].count, 2);
  assert.equal((await db.query("select count(*)::int count from public.account_deletion_requests where status='requested'")).rows[0].count, 2);
  const flags = (await db.query("select prosecdef from pg_proc where oid='public.account_deletion_request(text,text)'::regprocedure")).rows[0];
  assert.equal(flags.prosecdef, false);
  pass('Intake does not delete or deactivate accounts and the public RPC does not bypass RLS');
  fs.writeFileSync(path.join(root, 'validation/account-deletion-intake.json'), JSON.stringify({
    environment: 'Local PGlite PostgreSQL with synthetic auth schema; no production migration or deletion', checks
  }, null, 2) + '\n');
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => db.close());
