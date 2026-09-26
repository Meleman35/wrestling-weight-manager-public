/* Device-only media and append-only scoring snapshots. No uploads or broadcasting. */
(function (root) {
  'use strict';
  const copy = value => structuredClone(value);
  function stateAt(events, atMs) {
    let event = null;
    for (const next of events) { if (next.atMs > atMs) break; event = next; }
    if (!event) return null;
    const s = copy(event.state);
    s.remainingMs = Math.max(0, s.remainingMs - (s.running ? Math.max(0, atMs - event.atMs) : 0));
    s.scores = {red: 0, other: 0};
    for (const award of s.ledger) if (!award.voided && award.corner in s.scores) s.scores[award.corner] += Number(award.points) || 0;
    return s;
  }
  class Timeline {
    constructor(startedAt, clock = () => performance.now()) { this.startedAt = startedAt; this.clock = clock; this.events = []; this.token = null; }
    append(snapshot, label) {
      if (!snapshot || snapshot.token === this.token) return null;
      this.token = snapshot.token;
      const state = copy(snapshot); delete state.token;
      const previous = this.events.at(-1)?.state;
      const changedLedger = !previous || JSON.stringify(previous.ledger) !== JSON.stringify(state.ledger);
      const inferredLabel = !previous ? 'Recording started' : changedLedger ? state.ledger.at(-1)?.label || 'Scoring history changed' :
        previous.running !== state.running ? state.running ? 'Clock started' : 'Clock paused' : 'Match state updated';
      const event = {seq: this.events.length, atMs: this.events.length ? Math.max(this.events.at(-1).atMs, this.clock() - this.startedAt) : 0,
        label: label || inferredLabel, state};
      this.events.push(event); return copy(event);
    }
  }
  class DeviceStore {
    async init() {
      if (!navigator.storage?.getDirectory || !globalThis.indexedDB) throw Error('This device cannot save the video pilot safely. Use a supported browser for this test.');
      this.root = await (await navigator.storage.getDirectory()).getDirectoryHandle('wm-video-pilot-v1', {create: true});
      this.db = await new Promise((resolve, reject) => {
        const r = indexedDB.open('wm-video-pilot-v1', 1);
        r.onupgradeneeded = () => { const s = r.result.createObjectStore('takes', {keyPath: 'id'}); s.createIndex('scope', 'scope'); };
        r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
        r.onblocked = () => reject(Error('Close other app windows and retry device storage.'));
      });
      // Test an actual closed write before asking for the camera.
      const probe = await this.root.getFileHandle('probe-' + crypto.randomUUID(), {create: true});
      const writer = await probe.createWritable(); await writer.write('ok'); await writer.close(); await this.root.removeEntry(probe.name);
      return this;
    }
    transaction(mode, action) {
      return new Promise((resolve, reject) => {
        const tx = this.db.transaction('takes', mode); let result;
        const r = action(tx.objectStore('takes')); r.onsuccess = () => { result = r.result; };
        tx.oncomplete = () => resolve(result); tx.onerror = tx.onabort = () => reject(tx.error || Error('Device save interrupted.'));
      });
    }
    put(take) { return this.transaction('readwrite', s => s.put(copy(take))); }
    get(id) { return this.transaction('readonly', s => s.get(id)); }
    list(scope) { return this.transaction('readonly', s => s.index('scope').getAll(scope)); }
    async directory(id) {
      if (!/^[a-f0-9-]{36}$/.test(id)) throw Error('Invalid recording identifier.');
      return this.root.getDirectoryHandle(id, {create: true});
    }
    async chunk(id, seq, blob) {
      const dir = await this.directory(id), name = String(seq).padStart(6, '0') + '.part';
      const handle = await dir.getFileHandle(name, {create: true}), w = await handle.createWritable();
      try { await w.write(blob); await w.close(); } catch (e) { try { await w.abort(); } catch {} throw e; }
      const file = await handle.getFile();
      if (file.size !== blob.size) throw Error('The video segment did not finish saving.');
      return file.size;
    }
    async assemble(take) {
      const dir = await this.directory(take.id), output = await dir.getFileHandle('replay', {create: true});
      const w = await output.createWritable(); let bytes = 0;
      try {
        for (let seq = 0; seq < take.chunks; seq++) {
          const file = await (await dir.getFileHandle(String(seq).padStart(6, '0') + '.part')).getFile();
          const reader = file.stream().getReader();
          try { while (true) { const part = await reader.read(); if (part.done) break; await w.write(part.value); bytes += part.value.byteLength; } }
          finally { reader.releaseLock(); }
        }
        await w.close();
      } catch (e) { try { await w.abort(); } catch {} throw e; }
      if (!bytes || bytes !== take.bytes) throw Error('Recording is incomplete. Saved segments have been kept.');
      return this.file(take);
    }
    async file(take) {
      const file = await (await (await this.directory(take.id)).getFileHandle('replay')).getFile();
      if (!file.size || file.size !== take.bytes) throw Error('Replay file is missing or incomplete.');
      return file.slice(0, file.size, take.mime);
    }
    async remove(take) {
      await this.root.removeEntry(take.id, {recursive: true}).catch(e => { if (e.name !== 'NotFoundError') throw e; });
      await this.transaction('readwrite', s => s.delete(take.id));
    }
  }
  function mimeType() {
    return ['video/mp4', 'video/webm;codecs=vp8,opus', 'video/webm'].find(t => globalThis.MediaRecorder?.isTypeSupported(t));
  }
  async function playable(blob) {
    const url = URL.createObjectURL(blob), video = document.createElement('video');
    video.muted = true; video.playsInline = true; video.preload = 'auto';
    try {
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => finish(Error('Playback could not be verified. Saved segments have been kept.')), 15000);
        function finish(error) { clearTimeout(timeout); video.onloadeddata = video.onerror = null; error ? reject(error) : resolve(); }
        video.onloadeddata = () => finish(); video.onerror = () => finish(Error('This recording could not be played. Saved segments have been kept.'));
        video.src = url; video.load();
      });
    } finally { video.removeAttribute('src'); video.load(); URL.revokeObjectURL(url); }
  }
  root.WMVideoCore = {Timeline, stateAt, DeviceStore, mimeType, playable};
  if (typeof module !== 'undefined') module.exports = root.WMVideoCore;
})(typeof window === 'undefined' ? globalThis : window);
