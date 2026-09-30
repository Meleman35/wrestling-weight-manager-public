'use strict';
// Offline metadata review aid. Deliberately has no DB client, account ID,
// credentials, network calls, SQL generator or execution mode.
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const ACTIONS = new Set(['NO ACTION', 'RESTRICT', 'CASCADE', 'SET NULL', 'SET DEFAULT']);
const sorted = values => [...values].sort();
const array = (v, name) => { if (!Array.isArray(v)) throw Error(name + ' must be an array'); return v; };
const string = (v, name) => { if (typeof v !== 'string' || !v.length) throw Error(name + ' must be nonempty text'); return v; };
const strings = (v, name) => array(v, name).map(x => string(x, name));

function buildPlan(input, roots = ['auth.users', 'public.profiles']) {
  if (input?.format_version !== 1) throw Error('Unsupported inventory format');
  const scope = sorted(strings(input.scope, 'scope'));
  const seenTables = new Set(), seenKeys = new Set();
  const tables = array(input.tables, 'tables').map(t => {
    const key = string(t.key, 'table key');
    if (seenTables.has(key)) throw Error('Duplicate table: ' + key);
    seenTables.add(key);
    const columns = sorted(strings(t.columns, 'columns'));
    if (new Set(columns).size !== columns.length) throw Error('Duplicate columns: ' + key);
    const jsonColumns = sorted(strings(t.json_columns, 'json columns'));
    if (jsonColumns.some(c => !columns.includes(c))) throw Error('Unknown JSON column: ' + key);
    const schema = string(t.schema_name, 'schema');
    if (!scope.includes(schema)) throw Error('Table outside inventory scope: ' + key);
    return { key, schema_name: schema, table_name: string(t.table_name, 'table name'), columns, json_columns: jsonColumns };
  }).sort((a, b) => a.key.localeCompare(b.key, 'en'));
  const byTable = new Map(tables.map(t => [t.key, t]));
  roots = sorted(new Set(strings(roots, 'roots')));
  if (!roots.length || roots.some(r => !byTable.has(r))) throw Error('Missing account root table');
  const foreignKeys = array(input.foreign_keys, 'foreign keys').map(f => {
    const key = string(f.key, 'foreign key');
    if (seenKeys.has(key)) throw Error('Duplicate foreign key: ' + key);
    seenKeys.add(key);
    const from = byTable.get(f.from_table), to = byTable.get(f.to_table);
    if (!from || !to) throw Error('Foreign key references a missing table: ' + key);
    const fromCols = strings(f.from_columns, 'from columns'), toCols = strings(f.to_columns, 'to columns');
    if (!fromCols.length || fromCols.length !== toCols.length ||
        new Set(fromCols).size !== fromCols.length || new Set(toCols).size !== toCols.length ||
        fromCols.some(c => !from.columns.includes(c)) || toCols.some(c => !to.columns.includes(c))) {
      throw Error('Invalid foreign key column mapping: ' + key);
    }
    if (!ACTIONS.has(f.on_delete)) throw Error('Unknown delete action: ' + key);
    if (typeof f.deferrable !== 'boolean' || typeof f.validated !== 'boolean') throw Error('Missing constraint state: ' + key);
    return { key, from_table: f.from_table, to_table: f.to_table, from_columns: fromCols,
      to_columns: toCols, on_delete: f.on_delete, deferrable: f.deferrable, validated: f.validated };
  }).sort((a, b) => a.key.localeCompare(b.key, 'en'));
  const incoming = new Map(tables.map(t => [t.key, []]));
  for (const f of foreignKeys) incoming.get(f.to_table).push(f);
  function closure(onlyCascades) {
    const reached = new Map(roots.map(r => [r, []])), queue = [...roots];
    for (let i = 0; i < queue.length; i++) {
      const current = queue[i];
      for (const f of incoming.get(current)) {
        if (onlyCascades && f.on_delete !== 'CASCADE') continue;
        if (!reached.has(f.from_table)) {
          reached.set(f.from_table, [...reached.get(current), f.key]); queue.push(f.from_table);
        }
      }
    }
    return reached;
  }
  const related = closure(false), cascade = closure(true);
  const edges = foreignKeys.filter(f => related.has(f.to_table));
  const canonical = JSON.stringify({ format_version: 1, scope, tables, foreign_keys: foreignKeys, roots });
  const hash = createHash('sha256').update(canonical).digest('hex');
  const actionCounts = Object.fromEntries([...ACTIONS].map(a => [a, edges.filter(f => f.on_delete === a).length]));
  const review = tables.filter(t => related.has(t.key)).map(t => ({
    table: t.key,
    role: roots.includes(t.key) ? 'account_root' : 'dependent_table',
    dependency_path: related.get(t.key),
    possible_cascade_from_roots: cascade.has(t.key) && !roots.includes(t.key),
    cascade_path: cascade.get(t.key) ?? null,
    incoming_dependencies: edges.filter(f => f.to_table === t.key).map(f => f.key),
    outgoing_dependencies: edges.filter(f => f.from_table === t.key).map(f => f.key),
    shared_context_columns: t.columns.filter(c => /(^|_)(team|organization|athlete|parent|guardian|child|room|event)(_id|_ids)$/.test(c)),
    embedded_data_columns: t.json_columns,
    disposition: 'UNREVIEWED',
    reason: 'Foreign keys describe dependencies, not data ownership or permission to erase.'
  }));
  return {
    format_version: 1, inventory_sha256: hash, mode: 'metadata_review_only',
    execution_ready: false, roots, scope,
    summary: { tables_in_scope: tables.length, foreign_keys_in_scope: foreignKeys.length,
      directly_referencing_root: foreignKeys.filter(f => roots.includes(f.to_table)).length,
      related_tables: review.length, related_foreign_keys: edges.length,
      possible_cascade_tables_excluding_roots: review.filter(t => t.possible_cascade_from_roots).length,
      delete_actions: actionCounts },
    table_review: review, foreign_key_review: edges,
    outside_dependency_graph: tables.filter(t => !related.has(t.key)).map(t => ({
      table: t.key, disposition: 'UNREVIEWED',
      reason: 'No dependent-table path from these account roots is not evidence of no personal data. Review parent/athlete associations through link tables too.'
    })),
    unresolved_gaps: [
      'All row ownership, guardian authority, shared-record handling and retention decisions remain unreviewed.',
      'This metadata graph does not count affected rows and is not an erasure order or permission grant.',
      'CASCADE means possible database propagation, not that a shared record is safe to delete.',
      'SET NULL and SET DEFAULT may leave identifying content; neither proves erasure.',
      'JSON/text references, tables without foreign keys, other schemas, views, triggers and functions need separate review.',
      'Storage bytes, video providers, exports, email/log/analytics systems, devices and backups need a separate data map.',
      'Authentication/session revocation, stale JWT handling, retries and completion evidence are not implemented.'
    ]
  };
}

module.exports = { buildPlan };
if (require.main === module) {
  try {
    if (process.argv.length !== 3 || process.argv[2].startsWith('--')) {
      throw Error('Usage: node scripts/account-deletion-plan.cjs <catalogue-inventory.json> (read only; no execute mode)');
    }
    const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    process.stdout.write(JSON.stringify(buildPlan(input), null, 2) + '\n');
  } catch (error) { process.stderr.write(error.message + '\n'); process.exitCode = 1; }
}
