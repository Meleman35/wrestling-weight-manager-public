/* Local offline-workspace cleanup after a matched completed server receipt. Native files remain a separate gate. */
window.WMAccountDeletionDevice = (() => {
  'use strict';
  const DB = 'wm-coach-offline-v1';
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const KEY_MARKER = Object.freeze({version: 0, accountDeletion: true});
  const RECORD_MARKER = Object.freeze({...KEY_MARKER, revision: 'account-deletion-v1'});
  const failure = code => Object.assign(new Error(code), {code});
  function aborted(signal) {
    if (signal?.aborted) throw failure('device_cleanup_aborted');
  }
  function marker(value, record) {
    const expected = record ? RECORD_MARKER : KEY_MARKER;
    return !!value && Object.keys(value).length === Object.keys(expected).length &&
      Object.entries(expected).every(([key, entry]) => value[key] === entry);
  }
  function open(signal) {
    return new Promise((resolve, reject) => {
      let settled = false, request;
      const finish = (error, database) => {
        if (settled) { database?.close(); return; }
        settled = true; clearTimeout(timer); signal?.removeEventListener('abort', cancel);
        if (error) { database?.close(); reject(error); } else resolve(database);
      };
      const cancel = () => finish(failure('device_cleanup_aborted'));
      const timer = setTimeout(() => finish(failure('device_storage_unavailable')), 5000);
      signal?.addEventListener('abort', cancel, {once: true});
      try {
        aborted(signal);
        request = indexedDB.open(DB);
        request.onupgradeneeded = event => {
          if (settled || signal?.aborted || event.oldVersion !== 0) {
            request.transaction.abort(); return;
          }
          request.result.createObjectStore('keys');
          request.result.createObjectStore('records');
        };
        request.onblocked = () => finish(failure('device_storage_unavailable'));
        request.onerror = () => finish(failure('device_storage_unavailable'));
        request.onsuccess = () => {
          const database = request.result;
          if (settled) { database.close(); return; }
          if (database.version !== 1 || [...database.objectStoreNames].join(',') !== 'keys,records') {
            finish(failure('device_scope_unreviewed'), database); return;
          }
          database.onversionchange = () => database.close();
          finish(null, database);
        };
      } catch (error) {
        finish(failure(error?.code === 'device_cleanup_aborted' ? error.code : 'device_storage_unavailable'));
      }
    });
  }
  function transaction(database, subjectId, mode, signal) {
    return new Promise((resolve, reject) => {
      let tx, settled = false, verified = false;
      const finish = error => {
        if (settled) return;
        settled = true; clearTimeout(timer); signal?.removeEventListener('abort', cancel);
        if (error) reject(error); else resolve(verified);
      };
      const cancel = () => {
        try { tx?.abort(); } catch (_) { /* Commit may already have completed. Verification still required. */ }
        finish(failure('device_cleanup_aborted'));
      };
      const timer = setTimeout(() => {
        try { tx?.abort(); } catch (_) { /* Never report success after a timed-out operation. */ }
        finish(failure('device_storage_unavailable'));
      }, 5000);
      signal?.addEventListener('abort', cancel, {once: true});
      try {
        aborted(signal);
        // Both account slots change atomically. Never clear a store or delete a database.
        tx = database.transaction(['keys', 'records'], mode, {durability: 'strict'});
        tx.onabort = () => finish(failure('device_storage_unavailable'));
        tx.onerror = () => { /* The abort event is authoritative; do not suppress rollback. */ };
        tx.oncomplete = () => finish();
        const keys = tx.objectStore('keys'), records = tx.objectStore('records');
        if (mode === 'readwrite') {
          keys.put(KEY_MARKER, subjectId);
          records.put(RECORD_MARKER, subjectId);
        } else {
          let keyValue, recordValue, completed = 0;
          const complete = () => {
            if (++completed === 2) verified = marker(keyValue, false) && marker(recordValue, true);
          };
          const keyRead = keys.get(subjectId), recordRead = records.get(subjectId);
          keyRead.onsuccess = () => { keyValue = keyRead.result; complete(); };
          recordRead.onsuccess = () => { recordValue = recordRead.result; complete(); };
        }
      } catch (error) {
        try { tx?.abort(); } catch (_) { /* Preserve the original sanitized failure. */ }
        finish(failure(error?.code === 'device_cleanup_aborted' ? error.code : 'device_storage_unavailable'));
      }
    });
  }
  async function clearOfflineAccount(scope, {signal} = {}) {
    // The future lifecycle controller must derive this scope from verified server state,
    // stop network/outbox work, and dispose in-memory views. UUID checks are NOT authorization.
    if (!scope || typeof scope.subjectId !== 'string' || typeof scope.requestId !== 'string' ||
        !UUID.test(scope.subjectId) || !UUID.test(scope.requestId)) {
      throw failure('device_scope_invalid');
    }
    const subjectId = scope.subjectId, requestId = scope.requestId;
    aborted(signal);
    const database = await open(signal);
    try {
      await transaction(database, subjectId, 'readwrite', signal);
      // A separate read transaction verifies ciphertext and CryptoKey were replaced, not merely queued.
      if (!await transaction(database, subjectId, 'readonly', signal)) {
        throw failure('device_cleanup_unverified');
      }
      aborted(signal);
      return Object.freeze({scope: DB, requestId, offlineWorkspaceCleared: true});
    } finally { database.close(); }
  }
  return Object.freeze({clearOfflineAccount});
})();
