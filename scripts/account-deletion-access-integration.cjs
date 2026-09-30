'use strict';
// Import-only, isolated-database integration. No production connection or migration runner.
const scope = require('./account-deletion-access-scope.json');
const POLICY = 'account_deletion_authenticated_access';
const quote = value => {
  if (!/^[a-z_][a-z0-9_]*$/.test(value)) throw Error('Invalid reviewed identifier');
  return '"' + value + '"';
};
const targets = [
  ...scope.publicTables.map(name => ['public', name]),
  ...scope.storageTables.map(name => ['storage', name]),
  ...scope.realtimeTables.map(name => ['realtime', name]),
];
const relation = ([schema, name]) => quote(schema) + '.' + quote(name);
const sorted = values => [...values].sort();
function same(actual, expected, label) {
  if (JSON.stringify(sorted(actual)) !== JSON.stringify(sorted(expected))) {
    throw Error('Access scope changed: ' + label + '. Review the catalog before integration.');
  }
}

async function inspect(db) {
  if ((await db.query("select current_setting('wm.deletion_access_fixture',true) value")).rows[0].value !== 'isolated-test') {
    throw Error('Deletion access integration is restricted to an isolated test database.');
  }
  const rows = (await db.query(`select n.nspname as schema,c.relname as name,c.relkind as kind,
    c.relrowsecurity as rls,to_json(c.reloptions) as options,
    (has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')
      or has_any_column_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE')) as accessible
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','storage','realtime') and c.relkind in ('r','p','v','m')`)).rows;
  const exposed = rows.filter(r => r.schema === 'public' && r.accessible);
  same(exposed.filter(r => ['r','p'].includes(r.kind)).map(r => r.name), scope.publicTables, 'public tables');
  same(exposed.filter(r => r.kind === 'v').map(r => r.name), scope.publicInvokerViews, 'public views');
  if (exposed.some(r => r.kind === 'm')) throw Error('An accessible materialized view requires separate review.');
  for (const name of scope.publicInvokerViews) {
    const view = exposed.find(r => r.name === name);
    if (!view.options?.includes('security_invoker=true')) throw Error('Owner-executed view requires review: ' + name);
  }
  for (const [schema, name] of targets) {
    const row = rows.find(r => r.schema === schema && r.name === name);
    if (!row || !row.rls || !['r','p'].includes(row.kind)) throw Error('Missing RLS target: ' + schema + '.' + name);
    const existing = (await db.query(`select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
      join pg_namespace n on n.oid=c.relnamespace where n.nspname=$1 and c.relname=$2 and p.polname=$3`, [schema,name,POLICY])).rows;
    if (existing.length) throw Error('Reserved guard policy already exists; verify the prior install before retrying.');
  }
  for (const name of ['private.account_deletion_access_allowed()', 'public.account_deletion_pre_request()']) {
    if (!(await db.query('select to_regprocedure($1)::text value',[name])).rows[0].value) throw Error('Missing prerequisite: ' + name);
  }
  if ((await db.query("select to_regprocedure('public.account_deletion_check_access()')::text value")).rows[0].value) {
    throw Error('Reserved access RPC already exists; review before integration.');
  }
  const configs = (await db.query(`select s.setdatabase as database,to_json(s.setconfig) as settings
    from pg_db_role_setting s join pg_roles r on r.oid=s.setrole where r.rolname='authenticator'`)).rows;
  const hooks = configs.flatMap(row => (row.settings || []).filter(s => s.startsWith('pgrst.db_pre_request=')).map(setting => ({database:row.database,setting})));
  if (hooks.length !== 1 || hooks[0].database !== 0 || hooks[0].setting !== 'pgrst.db_pre_request=public.enforce_team_login_request') {
    throw Error('Existing PostgREST hook configuration changed; do not replace it automatically.');
  }
}

async function installIsolatedAccessIntegration(db) {
  // This marker is an accident-prevention guard, not an authorization boundary.
  // The caller must supply a disposable DB and MUST NOT pass a production client.
  await db.exec('begin');
  try {
    await inspect(db);
    for (const target of targets) {
      // Existing ownership/role policies remain required. This policy grants nothing.
      await db.exec(`create policy ${quote(POLICY)} on ${relation(target)} as restrictive for all to authenticated
        using ((select private.account_deletion_access_allowed()))
        with check ((select private.account_deletion_access_allowed()))`);
    }
    await db.exec(`create function public.account_deletion_check_access()
      returns boolean language sql stable security invoker set search_path='' as
      $$select private.account_deletion_access_allowed()$$;
      revoke all on function public.account_deletion_check_access() from public,anon,authenticated;
      grant execute on function public.account_deletion_check_access() to authenticated;
      alter role authenticator set pgrst.db_pre_request='public.account_deletion_pre_request';
      notify pgrst, 'reload config';`);
    await db.exec('commit');
    return {policyCount:targets.length,postgrestHook:'public.account_deletion_pre_request',globalRevocationProven:false};
  } catch (error) {
    await db.exec('rollback');
    throw error;
  }
}

module.exports = {installIsolatedAccessIntegration, scope, POLICY};
