'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { buildPlan } = require('../scripts/account-deletion-plan.cjs');
const { PGlite } = require('@electric-sql/pglite');
const root = path.resolve(__dirname, '..');
const checks = [];
const pass = name => { checks.push(name); console.log('PASS', name); };
const table = (key, columns = ['id'], json_columns = []) => ({key, schema_name: key.split('.')[0], table_name: key.split('.')[1], columns, json_columns});
const fk = (key, from_table, to_table, on_delete = 'CASCADE', from_columns = ['owner_id'], to_columns = ['id']) => ({key, from_table, to_table, from_columns, to_columns, on_delete, deferrable: false, validated: true});
const fixture = () => ({format_version: 1, scope: ['auth', 'private', 'public', 'storage'], tables: [
  table('auth.users'), table('public.profiles', ['id', 'name']),
  table('public.teams', ['id', 'owner_id', 'name']),
  table('public.roster', ['id', 'team_id', 'athlete_id']),
  table('public.notes', ['id', 'owner_id', 'body', 'payload'], ['payload']),
  table('public.restricted', ['id', 'owner_id']),
  table('public.restricted_child', ['id', 'owner_id']),
  table('public.audit_default', ['id', 'owner_id']),
  table('private.unlinked', ['id', 'email', 'payload'], ['payload'])
], foreign_keys: [
  fk('profiles_owner', 'public.profiles', 'auth.users', 'CASCADE', ['id']),
  fk('teams_owner', 'public.teams', 'public.profiles'),
  fk('roster_team', 'public.roster', 'public.teams', 'CASCADE', ['team_id']),
  fk('notes_owner', 'public.notes', 'public.profiles', 'SET NULL'),
  fk('restricted_owner', 'public.restricted', 'auth.users', 'RESTRICT'),
  fk('restricted_child', 'public.restricted_child', 'public.restricted'),
  fk('audit_default', 'public.audit_default', 'auth.users', 'SET DEFAULT')
]});
async function main() {
  const sample = fixture(), before = JSON.stringify(sample), p = buildPlan(sample);
  assert.equal(p.execution_ready, false);
  assert.equal(p.table_review.find(t => t.table === 'public.roster').possible_cascade_from_roots, true);
  assert.deepEqual(p.table_review.find(t => t.table === 'public.roster').cascade_path, ['teams_owner', 'roster_team']);
  assert(p.table_review.every(t => t.disposition === 'UNREVIEWED'));
  assert.deepEqual(p.table_review.find(t => t.table === 'public.roster').shared_context_columns, ['athlete_id', 'team_id']);
  assert.equal(JSON.stringify(sample), before);
  pass('Shared team/roster cascades are surfaced for review, never authorized for erasure; input is unchanged');

  assert.equal(p.table_review.find(t => t.table === 'public.restricted_child').possible_cascade_from_roots, false);
  assert.equal(p.summary.delete_actions.RESTRICT, 1);
  assert.equal(p.summary.delete_actions['SET NULL'], 1);
  assert.equal(p.summary.delete_actions['SET DEFAULT'], 1);
  assert.deepEqual(p.table_review.find(t => t.table === 'public.notes').embedded_data_columns, ['payload']);
  assert(p.unresolved_gaps.some(g => g.startsWith('SET NULL')));
  pass('A restrictive link stops cascade propagation; null/default actions and embedded data remain explicit review gaps');

  assert.deepEqual(p.outside_dependency_graph.map(t => t.table), ['private.unlinked']);
  assert.equal(p.outside_dependency_graph[0].disposition, 'UNREVIEWED');
  pass('Tables without foreign keys are retained in the review inventory rather than treated as safe');

  const reverse = structuredClone(sample);
  reverse.tables.reverse(); reverse.foreign_keys.reverse(); reverse.scope.reverse();
  reverse.tables.forEach(t => t.columns.reverse());
  assert.deepEqual(buildPlan(reverse), p);
  const drift = structuredClone(sample); drift.foreign_keys[1].on_delete = 'NO ACTION';
  assert.notEqual(buildPlan(drift).inventory_sha256, p.inventory_sha256);
  drift.tables[0].columns.push('new_personal_field');
  assert.notEqual(buildPlan(drift).inventory_sha256, buildPlan(sample).inventory_sha256);
  pass('Input ordering is irrelevant and schema/constraint drift changes the inventory fingerprint');

  const cyc = fixture();
  cyc.tables.find(t => t.key === 'public.teams').columns.push('roster_id');
  cyc.foreign_keys.push(fk('teams_roster', 'public.teams', 'public.roster', 'CASCADE', ['roster_id']));
  assert.equal(buildPlan(cyc).table_review.length, p.table_review.length);
  assert.equal(buildPlan(cyc).foreign_key_review.length, p.foreign_key_review.length + 1);
  pass('Cyclic relationships terminate without duplicate tables or an invented erasure order');

  const composite = fixture();
  composite.tables[0].columns.push('tenant_id');
  composite.tables.find(t => t.key === 'public.notes').columns.push('tenant_id');
  composite.foreign_keys.push(fk('notes_compound', 'public.notes', 'auth.users', 'NO ACTION', ['owner_id', 'tenant_id'], ['id', 'tenant_id']));
  const comp = buildPlan(composite).foreign_key_review.find(f => f.key === 'notes_compound');
  assert.deepEqual(comp.from_columns, ['owner_id', 'tenant_id']);
  assert.deepEqual(comp.to_columns, ['id', 'tenant_id']);
  assert.equal(buildPlan(composite).table_review.filter(t => t.table === 'public.notes').length, 1);
  pass('Composite keys retain paired column order and multiple references do not duplicate a table');

  for (const mutate of [
    s => { s.format_version = 2; },
    s => { s.tables.push(s.tables[0]); },
    s => { s.foreign_keys.push(s.foreign_keys[0]); },
    s => { s.foreign_keys[0].to_table = 'auth.missing'; },
    s => { s.foreign_keys[0].on_delete = 'DROP EVERYTHING'; },
    s => { s.foreign_keys[0].from_columns = ['missing']; },
    s => { s.foreign_keys[0].from_columns = ['id', 'id']; },
    s => { delete s.foreign_keys[0].validated; },
    s => { s.tables = s.tables.filter(t => t.key !== 'auth.users'); }
  ]) { const bad = fixture(); mutate(bad); assert.throws(() => buildPlan(bad)); }
  assert.throws(() => buildPlan(fixture(), []));
  pass('Incomplete, ambiguous or unsupported metadata fails explicitly instead of producing an executable-looking plan');

  const cli = spawnSync(process.execPath, [path.join(root, 'scripts/account-deletion-plan.cjs'), '--execute'], {encoding:'utf8'});
  assert.notEqual(cli.status, 0); assert.match(cli.stderr, /no execute mode/); assert.equal(cli.stdout, '');
  pass('The command line has no execution mode or account target');

  const db = new PGlite();
  try {
    await db.exec(`create schema auth; create schema private; create schema storage;
      create table auth.users(id uuid primary key);
      create table public.profiles(id uuid primary key references auth.users on delete cascade, display_name text);
      create table public.teams(id uuid primary key, owner_id uuid references public.profiles on delete restrict);
      create table public.roster(id uuid primary key, team_id uuid references public.teams on delete cascade, payload jsonb);
      create table private.unlinked(id uuid primary key, email text);
      insert into auth.users values ('00000000-0000-4000-8000-000000000001');
      insert into public.profiles values ('00000000-0000-4000-8000-000000000001','SYNTHETIC_PRIVATE_VALUE');
      insert into private.unlinked values ('00000000-0000-4000-8000-000000000002','synthetic@example.invalid');`);
    const beforeRows = await db.query('select * from public.profiles');
    await db.exec('begin read only');
    const result = await db.query(fs.readFileSync(path.join(root, 'scripts/account-deletion-inventory.sql'), 'utf8'));
    await db.exec('rollback');
    const live = buildPlan(result.rows[0].inventory);
    assert.equal(live.summary.tables_in_scope, 5);
    assert.equal(live.summary.foreign_keys_in_scope, 3);
    assert.equal(live.summary.directly_referencing_root, 2);
    assert.equal(live.table_review.find(t => t.table === 'public.roster').possible_cascade_from_roots, false);
    assert.deepEqual(live.table_review.find(t => t.table === 'public.roster').embedded_data_columns, ['payload']);
    assert(!JSON.stringify(result).includes('SYNTHETIC_PRIVATE_VALUE'));
    assert(!JSON.stringify(result).includes('synthetic@example.invalid'));
    assert.deepEqual((await db.query('select * from public.profiles')).rows, beforeRows.rows);
    pass('Actual PostgreSQL catalogue query runs in a read-only transaction, preserves rows and returns metadata without account values');
  } finally { await db.close(); }
  fs.writeFileSync(path.join(root, 'validation/account-deletion-plan.json'), JSON.stringify({status:'passed', checks, scope:'Synthetic schema and actual SQL in PGlite; no production row access or writes'}, null, 2)+'\n');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
