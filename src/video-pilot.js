/* Free, allowlisted browser capture pilot. Server grants never create paid rights. */
window.WMVideoPilot = (() => {
  'use strict';
  if (window.webkit?.messageHandlers?.wmVideoPilot) return null;
  const $ = id => document.getElementById(id), C = WMVideoCore;
  const MAX_MS = 20 * 60000, RESERVE = 256 * 1024 * 1024;
  let generation = 0, grant = null, store = null, stream = null, recorder = null, take = null, timeline = null;
  let writing = Promise.resolve(), pendingBytes = 0, writeError = null, stopping = null, stopResolve = null;
  let opening = false, captureStarted = false, interrupted = false, monitor = null, refreshBusy = false, wake = null;
  let previewKey = '', replay = null, replayURL = null, listTicket = 0, statusText = '', accessRequest = 0;
  const context = () => ({user: session?.user?.id, team: activeTeam?.id,
    allowed: !!session?.user?.id && !!activeTeam?.id && !managedLogin &&
      !document.body.classList.contains('kiosk-locked') && !document.querySelector('#appLockOverlay:not(.hidden)')});
  const key = c => c.user + ':' + c.team;
  const valid = () => { const c = context(); return c.allowed && grant?.scope === key(c) && performance.now() < grant.until; };
  const snapshot = () => window.WMMatch?.videoSnapshot();
  const currentMatch = () => snapshot()?.id;
  const active = () => !!recorder || opening || !!stopping;
  function ensure() { if (!valid()) throw Error('Video test access ended. Reconnect and reopen Match Book.'); }
  function note(text, bad = false) {
    statusText = text;
    for (const id of ['vpStatus', 'vpLibraryStatus']) if ($(id)) { $(id).textContent = text; $(id).classList.toggle('vp-error', bad); }
  }
  const format = ms => { const s = Math.max(0, Math.ceil(ms / 1000)); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); };
  function overlay(el, s) {
    if (!el || !s) return;
    const sc = s.scores || C.stateAt([{atMs: 0, state: s}], 0).scores;
    el.innerHTML = `<span>${esc(s.red_name)}<b>${sc.red}</b></span><span class="vp-time">${esc(s.phaseLabel)}<b>${format(s.remainingMs)}</b></span><span class="${s.style === 'folkstyle' ? 'vp-green' : ''}">${esc(s.other_name)}<b>${sc.other}</b></span>`;
  }
  function supported() { return isSecureContext && !!navigator.mediaDevices?.getUserMedia && !!C.mimeType() && !!navigator.storage?.getDirectory; }
  async function storage() { if (!store) store = await new C.DeviceStore().init(); return store; }
  async function authorize(force = false) {
    const c = context(), g = generation;
    if (!c.allowed) return false;
    if (!force && valid()) return true;
    const request = ++accessRequest;
    const requestedAt = performance.now();
    const {data, error} = await client.rpc('video_pilot_context', {p_team_id: c.team});
    if (request !== accessRequest || g !== generation || key(c) !== key(context()) || !context().allowed) return false;
    if (error) throw Error('Video pilot access could not be checked. Reconnect and try again.');
    if (!data?.allowed || data.user_id !== c.user || data.team_id !== c.team || !(data.lease_seconds > 0)) {
      grant = null; if (active()) stop('Test access was disabled.'); closeCamera(); closeReplay(); return false;
    }
    grant = {scope: key(c), user: c.user, team: c.team, until: requestedAt + Math.min(data.lease_seconds, 7200) * 1000,
      athletes: data.athlete_ids || []};
    return true;
  }
  function shell() {
    if ($('vpPanel')) return;
    const panel = document.createElement('section'); panel.id = 'vpPanel'; panel.className = 'vp-panel'; panel.hidden = true;
    panel.innerHTML = `<span class="vp-badge">VIDEO PILOT · TEST ACCESS</span><h3>Record &amp; score</h3><p>Private recording on this device. Browser test · iPhone app recording still needs device verification.</p>
      <label class="vp-check"><input id="vpPermission" type="checkbox">I have permission to record these participants at this event.</label>
      <div class="vp-stage" id="vpStage" hidden><video id="vpCamera" muted playsinline autoplay></video><div id="vpOverlay" class="vp-overlay"></div></div>
      <div class="vp-actions"><button id="vpPreview" type="button" class="secondary">Open camera</button><button id="vpStart" type="button" class="vp-record" disabled>Record privately</button><button id="vpStop" type="button" disabled>Stop &amp; save video</button><button id="vpClock" type="button" class="secondary" hidden>Start clock</button><button id="vpCameraClose" type="button" class="secondary" hidden>Close camera</button></div>
      <p id="vpStatus" class="vp-status" role="status"></p><p>Keep this screen open while recording. Up to 20 minutes per take. Tournament videos upload when service returns while the app is open. Go Live is not connected yet. Export copies before clearing app data; your browser can remove device storage.</p>
      <details><summary>Saved videos on this device</summary><div id="vpTakes"></div></details>`;
    $('matchScoreSheet').insertBefore(panel, $('matchPeriodLabel'));
    $('vpPreview').onclick = () => preview().catch(report);
    $('vpStart').onclick = () => start().catch(report);
    $('vpStop').onclick = () => stop().catch(report);
    $('vpClock').onclick = () => { if (valid() && recorder && !stopping) $('matchToggle').click(); };
    $('vpCameraClose').onclick = () => closeCamera();
    const library = document.createElement('section'); library.id = 'vpLibrary'; library.className = 'vp-panel'; library.hidden = true;
    library.innerHTML = '<span class="vp-badge">VIDEO PILOT · TEST ACCESS</span><h3>Saved match videos</h3><p>Saved inside Wrestling Manager on this device, for this account and team. Test videos stay here. Use replay and export to save a copy outside the app.</p><p id="vpLibraryStatus" role="status"></p><div id="vpAllTakes"></div>';
    $('matchListSheet').append(library);
    WMVideoUI.mount();
  }
  function controls() {
    window.WMMatchVideo?.recorderControls(!!recorder && captureStarted);
    if (!$('vpPanel')) return;
    const ready = valid(), snap = snapshot();
    $('vpPanel').hidden = !ready || !snap;
    $('vpPanel').classList.toggle('vp-capturing', !!recorder);
    $('vpLibrary').hidden = !ready;
    $('vpPreview').disabled = !ready || active() || !!stream || !supported();
    $('vpStart').disabled = !ready || active() || !stream || previewKey !== snap?.id || snap?.status === 'complete';
    $('vpStop').disabled = !recorder || !!stopping || recorder.state === 'inactive';
    $('vpClock').hidden = !recorder;
    $('vpClock').disabled = !!stopping || snap?.status === 'complete';
    $('vpCameraClose').hidden = !stream || active();
    $('vpPermission').disabled = active();
    WMVideoUI.camera(ready && !!stream && !stopping);
    if ($('vpCameraWorkspace')) $('vpCameraWorkspace').classList.toggle('vp-is-recording', !!recorder);
    if ($('vpSavedVideos')) $('vpSavedVideos').disabled = active();
  }
  function report(e) { note(e?.name === 'NotAllowedError' ? 'Camera or microphone permission was denied. Allow access in browser settings and try again.' : e?.message || 'Video action failed.', true); controls(); }
  async function sync() {
    shell(); const g = generation;
    if (!context().allowed) { reset(); return; }
    try {
      if (!await authorize() || g !== generation) { controls(); return; }
      controls();
      await storage(); if (g !== generation || !valid()) return;
      controls(); if (!supported()) note('This browser cannot capture and save this pilot. Native iPhone capture is not connected yet.', true);
      else if (!statusText) note('Test access ready. Open the camera to record this match.');
      await list();
    } catch (e) { if (g === generation && valid()) report(e); }
  }
  async function preview() {
    ensure(); if (active() || stream) return;
    if (!$('vpPermission').checked) throw Error('Confirm recording permission before opening the camera.');
    const snap = snapshot(); if (!snap || snap.status === 'complete') throw Error('Open an unfinished match to record.');
    if (!supported()) throw Error('Recording is unsupported in this browser.');
    const g = generation, scope = grant.scope;
    opening = true; controls(); let acquired;
    try {
      await storage(); const estimate = await navigator.storage.estimate();
      if (!Number.isFinite(estimate.quota) || estimate.quota - (estimate.usage || 0) < RESERVE) throw Error('Not enough device storage for this test. Export and remove older takes or free space first.');
      if (navigator.storage.persist) await navigator.storage.persist().catch(() => false);
      acquired = await navigator.mediaDevices.getUserMedia({video: {facingMode: {ideal: 'environment'}, width: {ideal: 1280}, height: {ideal: 720}, frameRate: {ideal: 30, max: 30}}, audio: true});
      if (g !== generation || !valid() || grant.scope !== scope || currentMatch() !== snap.id || document.hidden) throw Error('Screen changed before the camera opened.');
      stream = acquired; previewKey = snap.id;
      for (const track of stream.getTracks()) {
        track.addEventListener('ended', () => interrupt('Camera or microphone stopped.'));
        track.addEventListener('mute', () => interrupt('Camera or microphone was interrupted.'));
      }
      $('vpCamera').srcObject = stream; $('vpStage').hidden = false; await $('vpCamera').play();
      note('Camera ready · nothing is recording yet.');
    } catch (e) { acquired?.getTracks().forEach(t => t.stop()); stream = null; throw e; }
    finally { opening = false; controls(); }
  }
  function closeCamera() {
    if (recorder) return;
    stream?.getTracks().forEach(t => t.stop()); stream = null; previewKey = '';
    if ($('vpCamera')) { $('vpCamera').srcObject = null; $('vpStage').hidden = true; }
    controls();
  }
  function enqueue(fn) {
    writing = writing.then(fn).catch(e => { if (!writeError) { writeError = e; interrupted = true; note('Device save failed. Recording stopped; partial segments were kept.', true); if (recorder?.state !== 'inactive') stop('Device storage failed.'); } });
    return writing;
  }
  function onScore(snap) {
    if (!captureStarted || !timeline || !recorder || stopping || snap?.id !== take?.matchId) return;
    const event = timeline.append(snap);
    if (event) enqueue(async () => { if (writeError) return; take.events.push(event); await store.put(take); });
    overlay($('vpOverlay'), snap);
  }
  async function start() {
    ensure(); if (active()) return;
    const snap = snapshot(), g = generation;
    if (!stream || previewKey !== snap?.id || snap.status === 'complete' || !$('vpPermission').checked) throw Error('Open the camera for this unfinished match first.');
    const athleteIds = [snap.red_id, snap.other_id].filter(Boolean);
    if (athleteIds.some(id => !grant.athletes.includes(id))) throw Error('An athlete is no longer on the approved team roster. Reopen the match.');
    if (snap.book_type !== 'test' && !athleteIds.length) throw Error('Select at least one team athlete in Match Book, or use a Test scorebook.');
    opening = true; controls();
    try {
      const estimate = await navigator.storage.estimate();
      if (estimate.quota - (estimate.usage || 0) < RESERVE) throw Error('Not enough free device storage to start.');
      if (g !== generation || !valid() || !stream || currentMatch() !== snap.id || document.hidden) throw Error('Screen changed before recording started.');
      const mime = C.mimeType();
      take = {id: crypto.randomUUID(), scope: grant.scope, teamId: grant.team, userId: grant.user, matchId: snap.id,
        boutId: snap.bout_id || null, athleteIds, label: snap.red_name + ' vs ' + snap.other_name, demo: snap.book_type === 'test', mime,
        createdAt: new Date().toISOString(), status: 'recording', chunks: 0, bytes: 0, durationMs: 0, events: [], reason: ''};
      writing = Promise.resolve(); writeError = null; pendingBytes = 0; interrupted = false; stopping = null; captureStarted = false;
      await store.put(take);
      if (g !== generation || !valid() || !stream || currentMatch() !== snap.id || document.hidden) throw Error('Screen changed before recording started.');
      recorder = new MediaRecorder(stream, {mimeType: mime, videoBitsPerSecond: 2500000, audioBitsPerSecond: 96000});
      recorder.onstart = () => {
        const source = snapshot();
        if (g !== generation || !valid() || source?.id !== take.matchId || document.hidden) { stop('Screen changed during start.'); return; }
        timeline = new C.Timeline(performance.now()); captureStarted = true;
        onScore(source); note('Recording privately · segments saving on this device.'); controls();
      };
      recorder.ondataavailable = e => {
        if (!e.data.size || writeError) return;
        pendingBytes += e.data.size;
        enqueue(async () => {
          try {
            if (writeError) return;
            const bytes = await store.chunk(take.id, take.chunks, e.data);
            take.chunks++; take.bytes += bytes;
            take.durationMs = timeline ? performance.now() - timeline.startedAt : 0;
            await store.put(take);
          } finally { pendingBytes -= e.data.size; }
        });
        if (pendingBytes > 32 * 1024 * 1024) stop('Device storage could not keep up.');
      };
      recorder.onerror = () => { interrupted = true; take.reason = 'Camera recording error.'; stop(take.reason); };
      recorder.onstop = () => { if (!stopping) { interrupted = true; take.reason ||= 'Capture ended unexpectedly.'; } finalize().catch(report); };
      recorder.start(2000);
      if (navigator.wakeLock?.request) navigator.wakeLock.request('screen').then(lock => { if (recorder && g === generation) wake = lock; else lock.release(); }).catch(() => {});
    } catch (e) {
      if (take && !captureStarted) { take.status = 'failed'; take.reason = e.message; await store.put(take).catch(() => {}); }
      recorder = null; closeCamera(); throw e;
    } finally { opening = false; controls(); }
  }
  function stop(reason = '') {
    if (stopping) return stopping;
    if (!recorder) { closeCamera(); return Promise.resolve(); }
    if (reason) { interrupted = true; take.reason = reason; }
    if (captureStarted && timeline) {
      const snap = snapshot(); if (snap?.id === take.matchId) onScore(snap);
      take.durationMs = performance.now() - timeline.startedAt;
    }
    stopping = new Promise(resolve => { stopResolve = resolve; });
    note('Saving video on this device…'); controls();
    if (recorder.state !== 'inactive') recorder.stop();
    return stopping;
  }
  async function finalize() {
    if (!stopping) stopping = new Promise(resolve => { stopResolve = resolve; });
    const saved = take;
    captureStarted = false;
    const finishedAt = timeline ? performance.now() - timeline.startedAt : 0;
    await writing;
    saved.durationMs = finishedAt; saved.status = 'saving';
    recorder = null; closeCamera(); controls();
    await wake?.release().catch(() => {}); wake = null;
    try {
      if (writeError) throw writeError;
      await store.put(saved);
      const file = await store.assemble(saved); await C.playable(file);
      saved.status = interrupted ? 'partial' : 'ready'; await store.put(saved);
      if (valid() && grant.scope === saved.scope) note(interrupted ? 'Partial video saved on this device. ' + saved.reason : 'Saved on this device · video playback checked. Upload status is shown below.');
    } catch (e) {
      saved.status = 'interrupted'; saved.reason ||= e.message; await store.put(saved).catch(() => {});
      if (valid() && grant.scope === saved.scope) note('Recording is incomplete. Saved segments were kept for recovery; no complete video was confirmed.', true);
    } finally {
      take = timeline = null; stopping = null; const resolve = stopResolve; stopResolve = null; resolve?.(); controls();
      if (valid()) list().then(() => {if(grant?.scope===saved.scope)WMVideoUI.saved(['ready','partial'].includes(saved.status));}).catch(report);
    }
  }
  function interrupt(reason) { if (recorder) stop(reason); else closeCamera(); }
  function leaving() { if (active()) interrupt('Recording stopped when leaving the match.'); else closeCamera(); }
  async function list() {
    if (!valid() || !store) return;
    const ticket = ++listTicket, scope = grant.scope, matchId = currentMatch();
    const rows = (await store.list(scope)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    if (ticket !== listTicket || !valid() || grant.scope !== scope) return;
    WMVideoUI.count(rows.length);
    for (const [id, subset] of [['vpTakes', rows.filter(r => r.matchId === matchId)], ['vpAllTakes', rows]]) {
      const el = $(id); if (!el) continue;
      el.innerHTML = subset.length ? subset.map(r => {
        const ongoing = take?.id === r.id;
        const ready = ['ready', 'partial'].includes(r.status);
        const label = ongoing ? 'Recording / saving' : r.status === 'ready' ? 'Saved on this device' : r.status === 'partial' ? 'Partial recording · saved on this device' : 'Interrupted · recovery needed';
        return `<article class="vp-take"><b>${r.demo ? 'TEST · ' : ''}${esc(r.label)}</b><p>${esc(new Date(r.createdAt).toLocaleString())} · ${format(r.durationMs)} · ${(r.bytes / 1048576).toFixed(1)} MB<br>${label}${r.boutId?' · '+(r.upload?.status==='ready'?'Uploaded · available to athlete & family':r.upload?.status==='uploading'?'Uploading '+(r.upload.progress||0)+'%':'Waiting to upload') : ''}</p><div class="vp-actions">${!ongoing ? `<button type="button" class="secondary" data-vp-${ready ? 'play' : 'recover'}="${r.id}">${ready ? 'Watch & review score' : 'Try partial recovery'}</button><button type="button" class="secondary" data-vp-delete="${r.id}">Delete device copy</button>` : ''}</div></article>`;
      }).join('') : '<p>No saved videos here yet.</p>';
      el.querySelectorAll('[data-vp-play]').forEach(b => b.onclick = () => watch(b.dataset.vpPlay).catch(report));
      el.querySelectorAll('[data-vp-recover]').forEach(b => b.onclick = () => recover(b.dataset.vpRecover).catch(report));
      el.querySelectorAll('[data-vp-delete]').forEach(b => b.onclick = () => remove(b.dataset.vpDelete).catch(report));
    }
  }
  async function owned(id) {
    ensure(); const scope = grant.scope, row = await (await storage()).get(id);
    ensure(); if (scope !== grant.scope || row?.scope !== scope) throw Error('This recording belongs to another account or team.');
    if (take?.id === id) throw Error('Wait until this recording finishes saving.');
    return row;
  }
  async function recover(id) {
    const row = await owned(id); note('Checking saved segments…');
    // Only committed segment counts are assembled. An orphan last segment is kept untouched.
    const file = await store.assemble(row); await C.playable(file);
    ensure(); if (row.scope !== grant.scope) return;
    row.status = 'partial'; row.reason = 'Recovered after an interruption. The ending may be missing.'; await store.put(row);
    note('Partial recording recovered. Check the ending before relying on it.'); await list();
  }
  async function remove(id) {
    const row = await owned(id);
    if(row.boutId){if(row.upload?.status!=='ready')throw Error('Wait for the verified upload before removing this device copy.');await WMMatchVideo.verifyCloud(row.id);}
    if (prompt('Type DELETE to permanently remove this video and score timeline from this device. Export it first if you need a copy.') !== 'DELETE') return;
    ensure(); if (row.scope !== grant.scope) return;
    await store.remove(row); note('Device video deleted.'); await list();
  }
  function closeReplay() {
    if (replay) { replay.querySelector('video')?.pause(); replay.remove(); replay = null; }
    if (replayURL) URL.revokeObjectURL(replayURL); replayURL = null;
  }
  async function watch(id) {
    if (active()) throw Error('Stop and save your recording before opening a replay.');
    closeCamera(); const row = await owned(id), file = await store.file(row);
    ensure(); if (row.scope !== grant.scope) return;
    closeReplay(); replayURL = URL.createObjectURL(file);
    replay = document.createElement('section'); replay.className = 'vp-replay'; replay.setAttribute('role', 'dialog'); replay.setAttribute('aria-modal', 'true'); replay.setAttribute('aria-label', 'Video replay');
    replay.innerHTML = `<div><div class="vp-head"><h2>${row.demo ? 'Test · ' : ''}${esc(row.label)}</h2><button id="vpReplayClose" type="button">Close</button></div><p>${row.status === 'partial' ? 'Partial recording · ' + esc(row.reason) : 'Saved on this device'} · ${row.boutId ? (row.upload?.status === 'ready' ? 'Uploaded · available to athlete & family' : 'Waiting to upload') : 'Device copy only'}</p><div class="vp-stage"><video id="vpPlayer" controls playsinline preload="auto"></video><div id="vpReplayOverlay" class="vp-overlay"></div></div><p id="vpReplayNote" role="status"></p><div class="vp-actions"><a id="vpExport" class="button" download="Match-video.${row.mime.includes('mp4') ? 'mp4' : 'webm'}">Export original video</a><button id="vpExportTimeline" type="button" class="secondary">Export score timeline</button></div><p>The scoreboard is shown in this player. Exported video does not have the scoreboard embedded.</p><h3>Jump to a scoring event</h3><div id="vpEvents" class="vp-events"></div></div>`;
    document.body.append(replay); const player = $('vpPlayer'); player.src = replayURL;
    $('vpExport').href = replayURL;
    const paint = () => overlay($('vpReplayOverlay'), C.stateAt(row.events, player.currentTime * 1000));
    player.ontimeupdate = player.onseeked = player.onloadeddata = paint; paint();
    player.onerror = () => { $('vpReplayNote').textContent = 'This browser cannot play this saved file. Export the original for recovery.'; };
    // Some WebM files report Infinity. Force a duration probe, then restore the start.
    player.onloadedmetadata = () => { if (!Number.isFinite(player.duration)) { player.currentTime = 1e10; player.addEventListener('seeked', () => { player.currentTime = 0; }, {once: true}); } };
    $('vpEvents').innerHTML = row.events.map((e, i) => `<button type="button" class="secondary" data-vp-seek="${i}">${format(e.atMs)} · ${esc(e.label)}</button>`).join('');
    $('vpEvents').querySelectorAll('button').forEach(b => b.onclick = () => {
      // Media seek times may round down; land just after the exact snapshot boundary.
      const seconds = row.events[Number(b.dataset.vpSeek)].atMs / 1000 + .001;
      player.currentTime = Math.min(seconds, Number.isFinite(player.duration) ? Math.max(0, player.duration - .05) : seconds); paint();
    });
    $('vpReplayClose').onclick = closeReplay;
    $('vpExportTimeline').onclick = () => {
      const url = URL.createObjectURL(new Blob([JSON.stringify({schema: 1, matchId: row.matchId, mime: row.mime, durationMs: row.durationMs, events: row.events}, null, 2)], {type: 'application/json'}));
      const a = document.createElement('a'); a.href = url; a.download = 'Match-score-timeline.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 3000);
    };
    $('vpReplayClose').focus();
  }
  function reset() { WMVideoUI.reset(); generation++; grant = null; listTicket++; leaving(); closeReplay(); if ($('vpPanel')) { $('vpPanel').hidden = $('vpLibrary').hidden = true; $('vpTakes').replaceChildren(); $('vpAllTakes').replaceChildren(); $('vpPermission').checked = false; } statusText = ''; }
  function monitorState() {
    if (grant && !valid()) { reset(); return; }
    if (stream && (document.hidden || currentMatch() !== previewKey)) { interrupt('Recording interrupted by a screen change.'); return; }
    if (recorder && timeline) {
      if (performance.now() - timeline.startedAt > MAX_MS) stop('The 20-minute test limit was reached.');
      else { const s = snapshot(); overlay($('vpOverlay'), s); if ($('vpClock')) $('vpClock').textContent = s?.running ? 'Stop clock' : 'Start clock'; }
    }
  }
  setInterval(monitorState, 200);
  setInterval(async () => {
    if (!grant || !context().allowed || refreshBusy || !navigator.onLine) return;
    refreshBusy = true;
    try { await authorize(true); controls(); } catch { /* Existing bounded in-memory lease supports an offline arena. */ }
    finally { refreshBusy = false; }
  }, 60000);
  monitor = setInterval(async () => {
    if (!recorder) return;
    try { const q = await navigator.storage.estimate(); if (q.quota - q.usage < 64 * 1024 * 1024) stop('Device storage is almost full.'); }
    catch { stop('Device storage could not be checked.'); }
  }, 5000);
  document.addEventListener('visibilitychange', () => { if (document.hidden) interrupt('Recording stopped when the app moved to the background.'); });
  window.addEventListener('pagehide', () => interrupt('Page closed during recording.'));
  window.addEventListener('beforeunload', e => { if (active()) { e.preventDefault(); e.returnValue = ''; } });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && replay) closeReplay(); });
  async function uploadQueue(){if(!valid()||active()||!store)return;await WMVideoUpload.queue(store,grant.scope);if(valid())await list();}
  window.addEventListener('online',()=>uploadQueue().catch(()=>{}));
  setInterval(()=>uploadQueue().catch(()=>{}),30000);
  async function quickStart(){await sync();ensure();if(!snapshot()?.bout_id)throw Error('Open an assigned tournament bout.');$('vpPermission').checked=true;await preview();await start();}
  async function openLibrary(){if(active())throw Error('Stop and save your recording first.');await sync();ensure();closeCamera();WMVideoUI.openLibrary();await list();}
  return {sync, onScore, leaving, reset, active,quickStart,openLibrary};
})();
