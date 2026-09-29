// Simulated DOM regression for the draft intake component; no real API calls.
const { JSDOM } = require('jsdom');
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..'), checks = [];
const dom = new JSDOM('<main id="host" hidden></main>', { runScripts: 'outside-only', url: 'https://wm.test/' });
const w = dom.window, host = w.document.getElementById('host');
w.eval(fs.readFileSync(path.join(root, 'src/account-deletion.js'), 'utf8'));
let owner = 'coach', allowed = true, mode = 'disabled', request = null, calls = 0, release;
const rpc = async action => {
  if (mode === 'delayed') return new Promise(resolve => { release = resolve; });
  if (action === 'request') {
    calls++;
    request ||= { id: '11111111-1111-4111-8111-111111111111', status: 'requested',
      requested_at: '2026-09-29T05:00:00Z', deadline_at: '2026-10-29T05:00:00Z', completed_at: null };
    if (mode === 'lost') { mode = 'enabled'; throw Error('Connection interrupted; request not confirmed.'); }
    if (mode === 'invalid') return { enabled: true, completion_days: 30, request: { status: 'requested' } };
  }
  return { enabled: mode !== 'disabled', completion_days: 30, request };
};
const ui = w.WMAccountDeletion.create({ host, rpc, currentUser: () => owner, allowed: () => allowed });
const wait = async fn => { for (let i = 0; i < 100; i++) { if (fn()) return; await new Promise(r => setTimeout(r, 5)); } throw Error('UI condition timed out'); };
const confirm = text => { const input = host.querySelector('input'); input.value = text; input.dispatchEvent(new w.Event('input')); };
const submit = () => host.querySelector('[data-deletion-submit]').click();
const pass = s => { checks.push(s); console.log('PASS', s); };
(async () => {
  await ui.open();
  assert(host.textContent.includes('not enabled'));
  assert.equal(host.querySelector('form'), null);
  assert.equal(calls, 0);
  pass('Disabled intake presents no request control and performs no request');
  mode = 'enabled'; await ui.open();
  assert(host.querySelector('[data-deletion-submit]').disabled);
  confirm('delete'); assert(host.querySelector('[data-deletion-submit]').disabled);
  confirm('DELETE'); assert(!host.querySelector('[data-deletion-submit]').disabled);
  assert.equal(host.querySelector('a').href, 'https://apps.apple.com/account/subscriptions');
  pass('Explicit confirmation is required and Apple subscription management is available');
  mode = 'lost'; submit();
  await wait(() => host.textContent.includes('Connection interrupted'));
  assert.equal(host.querySelector('input').value, 'DELETE');
  assert(!host.querySelector('[data-deletion-submit]').disabled);
  assert.equal(host.querySelector('[data-deletion-receipt]'), null);
  pass('An interrupted response preserves confirmation, allows retry and does not claim receipt');
  submit(); await wait(() => host.querySelector('[data-deletion-receipt]'));
  assert.equal(calls, 2); assert(host.textContent.includes('has not been deleted yet'));
  assert(![...host.querySelectorAll('p')].some(p => p.textContent === 'Your account deletion is complete.'));
  await ui.open(); assert(host.querySelector('[data-deletion-receipt]'));
  assert.equal(calls, 2);
  pass('Retry and reopening recover the durable pending receipt without claiming completed deletion');
  request = null; mode = 'invalid'; await ui.open(); confirm('DELETE'); submit();
  await wait(() => host.textContent.includes('No receipt was confirmed'));
  assert.equal(host.querySelector('[data-deletion-receipt]'), null);
  pass('An incomplete server result never produces a success receipt');
  request = null; mode = 'enabled'; await ui.open(); confirm('DELETE');
  mode = 'delayed'; submit(); submit();
  await wait(() => release);
  owner = 'other'; ui.invalidate();
  release({ enabled: true, completion_days: 30, request: {
    id: '11111111-1111-4111-8111-111111111111', status: 'requested',
    requested_at: '2026-09-29T05:00:00Z', deadline_at: '2026-10-29T05:00:00Z'
  } });
  await new Promise(r => setTimeout(r, 20));
  assert(host.hidden); assert.equal(host.textContent, '');
  pass('A late response cannot reveal the previous account’s receipt after invalidation');
  allowed = false; await ui.open(); assert(host.hidden); assert.equal(host.textContent, '');
  pass('Locked or managed-account adapters can prevent entry');
  fs.writeFileSync(path.join(root, 'validation/account-deletion-ui.json'), JSON.stringify({ environment: 'jsdom 26.0.0, synthetic RPC only', checks }, null, 2) + '\n');
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => w.close());
