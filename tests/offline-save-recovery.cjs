// Local-only fixture. Install jsdom@26.0.0 and fake-indexeddb@6.0.0 to run.
// Runs the production workspace and encrypted store with simulated browser APIs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { webcrypto } = require('node:crypto');
const { JSDOM } = require('jsdom');
const { indexedDB, IDBObjectStore } = require('fake-indexeddb');
const root = path.resolve(__dirname, '..');
const checks = [];
const pass = text => { checks.push(text); console.log('PASS', text); };
const dom = new JSDOM('<body><div id="appLockOverlay" class="hidden"></div><button id="securityBtn"></button></body>', {
  url: 'https://wm.test/', runScripts: 'outside-only'
});
const w = dom.window, document = w.document;
const byId = id => document.getElementById(id);
const wait = async condition => {
  for (let n = 0; n < 100; n++) {
    if (await condition()) return;
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  throw Error('Fixture condition timed out');
};
const click = selector => document.querySelector(selector).click();
Object.defineProperties(w, {
  crypto: { value: webcrypto }, indexedDB: { value: indexedDB },
  isSecureContext: { value: true }, TextEncoder: { value: TextEncoder },
  TextDecoder: { value: TextDecoder }
});
Object.defineProperties(w.navigator, {
  onLine: { value: false, configurable: true },
  serviceWorker: { value: { register: async () => ({}) } }
});
Object.assign(w, {
  caches: {}, session: { user: { id: 'coach' } }, managedLogin: null,
  WMProfilePIN: { verify: async () => {} },
  client: { auth: { onAuthStateChange() {} }, rpc() { throw Error('Unexpected network request'); } }
});
const workspaceSource = fs.readFileSync(path.join(root, 'src/offline-workspace.js'), 'utf8');
const bundle = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
assert(bundle.includes(workspaceSource.trim()), 'Published bundle must contain the exact workspace source');
w.eval(fs.readFileSync(path.join(root, 'src/offline-store.js'), 'utf8'));
w.eval(workspaceSource);
const S = w.WMOfflineStore;
const fill = (name, value) => { document.querySelector('#ofEventForm [name="' + name + '"]').value = value; };
const value = name => document.querySelector('#ofEventForm [name="' + name + '"]').value;
const originalPut = IDBObjectStore.prototype.put;
(async () => {
  await S.update('coach', body => {
    body.packs['team/season'] = {
      team: { id: 'team', name: 'Test Wrestling' }, season: { id: 'season', name: '2026–27' },
      downloaded_at: new Date().toISOString(), expires_at: new Date(Date.now() + 864e5).toISOString(),
      roster: [], attendance: [], threads: [], messages: {},
      events: [{ id: 'event', title: 'Practice', starts_at: '2026-10-02T20:00:00Z',
        ends_at: '2026-10-02T21:30:00Z', description: '', updated_at: '2026-09-01T00:00:00Z' }]
    };
  });
  await w.WMOffline.open();
  byId('ofPIN').value = '1234';
  click('#ofUnlockForm button');
  await wait(() => document.querySelector('[data-pack]'));
  click('[data-pack]');
  await wait(() => document.querySelector('[data-view="schedule"]'));
  click('[data-view="schedule"]');
  await wait(() => document.querySelector('[data-edit]'));
  click('[data-edit]');
  await wait(() => byId('ofEventForm'));

  fill('title', 'Keep my revised practice');
  fill('description', 'Bus leaves at 4:15. Bring both uniforms.');
  IDBObjectStore.prototype.put = function (...args) {
    if (this.name === 'records') throw new DOMException('Storage full', 'QuotaExceededError');
    return originalPut.apply(this, args);
  };
  click('#ofEventForm button');
  await wait(() => byId('ofStatus').classList.contains('of-error'));
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal((await S.get('coach')).queue.length, 0);
  assert.equal(value('title'), 'Keep my revised practice');
  assert.equal(value('description'), 'Bus leaves at 4:15. Bring both uniforms.');
  assert.equal(document.querySelector('#ofEventForm button').disabled, false);
  pass('Rejected storage commit retains unsaved event fields and permits retry without claiming success');

  IDBObjectStore.prototype.put = originalPut;
  click('#ofEventForm button');
  await wait(async () => (await S.get('coach')).queue.length === 1);
  await wait(() => !document.querySelector('#ofEventForm button').disabled);
  const saved = (await S.get('coach')).queue[0];
  assert.equal(saved.request.values.title, 'Keep my revised practice');
  assert.equal(saved.request.values.description, 'Bus leaves at 4:15. Bring both uniforms.');
  assert.equal(saved.request.expected, '2026-09-01T00:00:00Z');
  pass('Retry persists the edited event once with the original server revision');

  fill('title', 'Second edit awaiting review');
  fill('description', 'Keep this second attempt visible.');
  click('#ofEventForm button');
  await wait(() => byId('ofStatus').textContent.includes('already has a saved change'));
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(value('title'), 'Second edit awaiting review');
  assert.equal(value('description'), 'Keep this second attempt visible.');
  assert.equal(document.querySelector('#ofEventForm button').disabled, false);
  assert.equal((await S.get('coach')).queue.length, 1);
  assert.equal((await S.get('coach')).queue[0].id, saved.id);
  pass('Duplicate-edit rejection preserves the existing operation and keeps the new input available');

  click('#ofLock');
  await wait(() => byId('offlineWorkspace').hidden);
  assert.equal(byId('ofEventForm'), null);
  assert.equal((await S.get('coach')).queue[0].id, saved.id);
  pass('Lock clears unsaved fields from the screen and retains the encrypted outbox');
  await w.WMOffline.open();
  byId('ofPIN').value = '1234';
  click('#ofUnlockForm button');
  await wait(() => document.querySelector('[data-pack]'));
  click('[data-pack]');
  await wait(() => document.querySelector('[data-view="schedule"]'));
  click('[data-view="schedule"]');
  await wait(() => document.querySelector('[data-edit]'));
  click('[data-edit]');
  await wait(() => byId('ofEventForm'));
  const update = S.update;
  let rejectSave;
  S.update = () => new Promise((_, reject) => { rejectSave = reject; });
  click('#ofEventForm button');
  await wait(() => rejectSave);
  w.session = { user: { id: 'other' } };
  await w.WMOffline.open();
  rejectSave(Error('Old profile save failed'));
  await new Promise(resolve => setTimeout(resolve, 20));
  S.update = update;
  assert.equal(byId('ofStatus').textContent, '');
  assert.equal(byId('ofEventForm'), null);
  assert(byId('ofPIN'));
  assert.equal((await S.get('coach')).queue[0].id, saved.id);
  pass('Late failure after a profile change cannot replace the new profile screen or show the old error');
  fs.writeFileSync(path.join(root, 'validation/offline-save-recovery.json'), JSON.stringify({
    environment: 'Node with jsdom 26.0.0, fake-indexeddb 6.0.0 and Web Crypto; no browser/device or server execution',
    checks
  }, null, 2) + '\n');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  IDBObjectStore.prototype.put = originalPut;
  w.close();
});
