'use strict';
// Uses real browser IndexedDB and the unchanged production offline-store implementation.
async function browserCases() {
  const passed = [], S = window.WMOfflineStore, D = window.WMAccountDeletionDevice;
  const DB = 'wm-coach-offline-v1';
  const check = (value, message) => { if (!value) throw Error(message); };
  const same = (a, b, message) => check(JSON.stringify(a) === JSON.stringify(b), message);
  const scope = subjectId => ({subjectId, requestId: crypto.randomUUID()});
  const seed = async () => {
    const id = crypto.randomUUID();
    await S.update(id, body => {
      body.packs = {'team/season': {athletes: [{name: 'Synthetic athlete'}]}};
      body.queue = [{request: {body: 'Synthetic unsent message'}}];
      body.drafts = {event: {title: 'Synthetic event'}};
      body.chatDrafts = {thread: {body: 'Synthetic draft'}};
      body.chatDraftCopies = {thread: {copy: {body: 'Synthetic alternative'}}};
    });
    return id;
  };
  const expectFailure = async (work, code) => {
    try { await work(); } catch (error) {
      if (code) check(error.code === code, 'Unexpected failure code: ' + error.code);
      return;
    }
    throw Error('Operation unexpectedly succeeded');
  };
  const connect = () => new Promise((resolve, reject) => {
    const r = indexedDB.open(DB); r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  });
  const rows = async id => {
    const db = await connect();
    try {
      return await new Promise((resolve, reject) => {
        const t = db.transaction(['keys', 'records'], 'readonly'), result = {};
        for (const name of ['keys', 'records']) {
          const r = t.objectStore(name).get(id); r.onsuccess = () => { result[name] = r.result; };
        }
        t.oncomplete = () => resolve(result); t.onabort = () => reject(t.error);
      });
    } finally { db.close(); }
  };
  const fingerprint = row => JSON.stringify({...row, iv: [...row.iv], data: [...new Uint8Array(row.data)]});
  const tombstones = async id => {
    const value = await rows(id);
    same(value.keys, {version: 0, accountDeletion: true}, 'CryptoKey was not replaced');
    same(value.records, {version: 0, accountDeletion: true, revision: 'account-deletion-v1'}, 'Ciphertext remains');
  };
  const defer = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return {promise, resolve}; };

  check((await indexedDB.databases()).length === 0, 'Import must not initialize any device storage');
  passed.push('unmounted import has no storage side effects');
  for (const value of [null, {}, scope(''), scope('../other'), {subjectId: crypto.randomUUID(), requestId: 'bad'}]) {
    await expectFailure(() => D.clearOfflineAccount(value), 'device_scope_invalid');
  }
  check((await indexedDB.databases()).length === 0, 'Invalid scope must not open storage');
  passed.push('invalid account/request scope fails before storage access');

  const a = await seed(), b = await seed(), beforeB = await S.get(b), rawB = fingerprint((await rows(b)).records);
  localStorage.setItem('other-account', 'keep'); sessionStorage.setItem('other-account', 'keep');
  const shell = await caches.open('synthetic-shell'); await shell.put('/keep', new Response('keep'));
  const video = await new Promise((resolve, reject) => {
    const r = indexedDB.open('synthetic-local-video', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('originals');
    r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  });
  await new Promise((resolve, reject) => {
    const t = video.transaction('originals', 'readwrite'); t.objectStore('originals').put('keep', 'clip');
    t.oncomplete = resolve; t.onabort = reject;
  });
  const request = scope(a), result = await D.clearOfflineAccount(request);
  same(result, {scope: DB, requestId: request.requestId, offlineWorkspaceCleared: true}, 'Overbroad evidence');
  await tombstones(a); same(await S.get(b), beforeB, 'Other account data changed');
  check(fingerprint((await rows(b)).records) === rawB, 'Other account ciphertext changed');
  passed.push('atomic account-scoped ciphertext and key removal preserves another account');
  check(localStorage.getItem('other-account') === 'keep' && sessionStorage.getItem('other-account') === 'keep', 'Unscoped Web Storage changed');
  check(await (await shell.match('/keep')).text() === 'keep', 'Shared shell cache changed');
  const clip = await new Promise((resolve, reject) => {
    const t = video.transaction('originals'), r = t.objectStore('originals').get('clip');
    r.onsuccess = () => resolve(r.result); r.onerror = reject;
  }); video.close(); check(clip === 'keep', 'Local original was removed');
  passed.push('unrelated databases, local video sentinel, Web Storage and shell cache preserved');

  await expectFailure(() => S.get(a));
  await expectFailure(() => S.update(a, body => { body.drafts = {bad: true}; }));
  await S.update(b, body => { body.drafts.more = 'still writable'; });
  await tombstones(a); check((await S.get(b)).drafts.more === 'still writable', 'Other account cannot save');
  passed.push('unchanged legacy store rejects purged reads and writes while other accounts work');
  await Promise.all([D.clearOfflineAccount(request), D.clearOfflineAccount(request), D.clearOfflineAccount(scope(a))]);
  await tombstones(a);
  passed.push('retries and concurrent cleanup calls remain idempotent');

  const frame = document.createElement('iframe'); document.body.append(frame);
  frame.contentWindow.eval(await (await fetch('/src/offline-store.js')).text());
  await expectFailure(() => frame.contentWindow.WMOfflineStore.get(a));
  check((await frame.contentWindow.WMOfflineStore.get(b)).drafts.more === 'still writable', 'Second window lost other account');
  frame.remove(); passed.push('new browsing context respects durable account fence');

  const c = await seed(), encrypted = defer(), resumeEncrypt = defer(), encrypt = crypto.subtle.encrypt;
  crypto.subtle.encrypt = async function (...args) {
    const bytes = await encrypt.apply(this, args); encrypted.resolve(); await resumeEncrypt.promise; return bytes;
  };
  let lateWrite;
  try {
    lateWrite = S.update(c, body => { body.drafts.late = 'must not return'; }).then(() => true, () => false);
    await encrypted.promise; await D.clearOfflineAccount(scope(c)); resumeEncrypt.resolve();
    check(await lateWrite === false, 'In-flight old writer recreated deleted records');
  } finally { resumeEncrypt.resolve(); crypto.subtle.encrypt = encrypt; }
  await tombstones(c); passed.push('in-flight encrypted legacy write cannot resurrect account data');

  const d = crypto.randomUUID(), generated = defer(), resumeKey = defer(), generateKey = crypto.subtle.generateKey;
  crypto.subtle.generateKey = async function (...args) {
    const key = await generateKey.apply(this, args); generated.resolve(); await resumeKey.promise; return key;
  };
  try {
    lateWrite = S.update(d, body => { body.drafts.late = 'must not return'; }).then(() => true, () => false);
    await generated.promise; await D.clearOfflineAccount(scope(d)); resumeKey.resolve();
    check(await lateWrite === false, 'In-flight key generation recreated an encryption key');
  } finally { resumeKey.resolve(); crypto.subtle.generateKey = generateKey; }
  await tombstones(d); passed.push('in-flight first-key creation cannot bypass the deletion marker');

  const e = await seed(), beforeE = await S.get(e), put = IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put = function (value, key) {
    if (this.name === 'records' && key === e && value?.accountDeletion) throw Error('SYNTHETIC PRIVATE ERROR');
    return put.call(this, value, key);
  };
  try { await expectFailure(() => D.clearOfflineAccount(scope(e)), 'device_storage_unavailable'); }
  finally { IDBObjectStore.prototype.put = put; }
  same(await S.get(e), beforeE, 'Failed multi-store transaction did not roll back');
  passed.push('second-write failure rolls back both stores and returns only sanitized errors');

  const abortBefore = new AbortController(); abortBefore.abort();
  await expectFailure(() => D.clearOfflineAccount(scope(e), {signal: abortBefore.signal}), 'device_cleanup_aborted');
  same(await S.get(e), beforeE, 'Pre-aborted cleanup changed data');
  const abortDuring = new AbortController();
  IDBObjectStore.prototype.put = function (value, key) {
    const output = put.call(this, value, key);
    if (this.name === 'records' && key === e && value?.accountDeletion) abortDuring.abort();
    return output;
  };
  try { await expectFailure(() => D.clearOfflineAccount(scope(e), {signal: abortDuring.signal}), 'device_cleanup_aborted'); }
  finally { IDBObjectStore.prototype.put = put; }
  same(await S.get(e), beforeE, 'Aborted multi-store transaction left partial cleanup');
  passed.push('cancellation before and during cleanup preserves atomicity');

  const get = IDBObjectStore.prototype.get;
  IDBObjectStore.prototype.get = function (key) {
    const r = get.call(this, key);
    if (this.name === 'records' && key === e) r.addEventListener('success', () => {
      if (r.result?.accountDeletion) r.result.unverified = true;
    });
    return r;
  };
  try { await expectFailure(() => D.clearOfflineAccount(scope(e)), 'device_cleanup_unverified'); }
  finally { IDBObjectStore.prototype.get = get; }
  await tombstones(e); await D.clearOfflineAccount(scope(e));
  passed.push('independent verification failure never reports success and can be retried');

  const open = IDBFactory.prototype.open;
  IDBFactory.prototype.open = function () { throw new DOMException('SYNTHETIC PRIVATE ERROR', 'SecurityError'); };
  try { await expectFailure(() => D.clearOfflineAccount(scope(b)), 'device_storage_unavailable'); }
  finally { IDBFactory.prototype.open = open; }
  check((await S.get(b)).drafts.more === 'still writable', 'Storage-denied request changed data');
  passed.push('storage denial fails closed without erasing another account');

  const beforeFuture = fingerprint((await rows(b)).records);
  const future = await new Promise((resolve, reject) => {
    const r = indexedDB.open(DB, 2); r.onupgradeneeded = () => r.result.createObjectStore('future');
    r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  }); future.close();
  await expectFailure(() => D.clearOfflineAccount(scope(b)), 'device_scope_unreviewed');
  check(fingerprint((await rows(b)).records) === beforeFuture, 'Unknown schema was modified');
  passed.push('unknown future database schema blocks cleanup without a destructive fallback');
  return {passed, count: passed.length, scope: 'offline-workspace-v1 only',
    limitations: ['Unmounted draft; no server deletion or session revocation',
      'No physical Apple device, native video, in-memory view or complete device cleanup acceptance']};
}

// Node runner: CI has a pinned Playwright dependency; importing this file does not launch a browser.
async function main() {
  const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
  const {chromium} = require('playwright'), root = path.resolve(__dirname, '..');
  const paths = new Set(['/src/offline-store.js', '/src/account-deletion-device.js']);
  const server = http.createServer((request, response) => {
    if (request.url === '/') {
      response.writeHead(200, {'Content-Type': 'text/html'});
      response.end('<!doctype html><title>Synthetic deletion device checks</title><script src="/src/offline-store.js"></script><script src="/src/account-deletion-device.js"></script>');
    } else if (paths.has(request.url)) {
      response.writeHead(200, {'Content-Type': 'text/javascript'}); response.end(fs.readFileSync(path.join(root, request.url)));
    } else { response.writeHead(404); response.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless: true, ...(process.env.CHROMIUM_EXECUTABLE_PATH ? {executablePath: process.env.CHROMIUM_EXECUTABLE_PATH} : {})});
    const page = await browser.newPage(); await page.goto('http://127.0.0.1:' + server.address().port);
    const result = await Promise.race([page.evaluate(browserCases), new Promise((_, reject) => {
      const timer = setTimeout(() => reject(Error('Device regression deadline exceeded')), 60000); timer.unref();
    })]);
    fs.mkdirSync(path.join(root, 'validation'), {recursive: true});
    fs.writeFileSync(path.join(root, 'validation/account-deletion-device.json'), JSON.stringify({browser: await browser.version(), ...result}, null, 2) + '\n');
    console.log('PASS ' + result.count + ' account-deletion device regression groups');
  } finally { await browser?.close(); await new Promise(resolve => server.close(resolve)); }
}
module.exports = {browserCases};
if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
