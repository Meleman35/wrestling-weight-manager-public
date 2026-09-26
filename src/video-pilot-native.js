/* Native AVFoundation adapter. Uses the same Match Book hooks and scorer snapshots. */
(() => {
  'use strict';
  const bridge = window.webkit?.messageHandlers?.wmVideoPilot;
  if (!bridge) return;
  const $ = id => document.getElementById(id), pending = new Map();
  let generation = 0, grant = null, phase = 'idle', previewMatch = '', refreshing = false, authorization = null;
  let lastToken = '', previousState = null, statusText = '', listTicket = 0;
  const context = () => ({user: session?.user?.id, team: activeTeam?.id,
    allowed: !!session?.user?.id && !!activeTeam?.id && !managedLogin &&
      !document.body.classList.contains('kiosk-locked') && !document.querySelector('#appLockOverlay:not(.hidden)')});
  const scope = c => c.user + ':' + c.team;
  const valid = () => context().allowed && grant?.scope === scope(context()) && performance.now() < grant.until;
  const snapshot = () => window.WMMatch?.videoSnapshot();
  const active = () => ['opening', 'starting', 'recording', 'stopping'].includes(phase);
  function post(command, fields = {}) { bridge.postMessage({command, ...fields}); }
  function request(command, fields = {}) {
    return new Promise((resolve, reject) => {
      const requestId = crypto.randomUUID();
      const timer = setTimeout(() => {
        pending.delete(requestId);
        reset();
        reject(Error('The iPhone video action did not finish. Reopen Match Book and check saved videos before recording again.'));
      }, command === 'preview' ? 60000 : 30000);
      pending.set(requestId, {resolve, reject, timer});
      try { post(command, {requestId, ...fields}); }
      catch (e) { clearTimeout(timer); pending.delete(requestId); reject(e); }
    });
  }
  function note(text, bad = false) {
    statusText = text;
    for (const id of ['vpStatus', 'vpLibraryStatus']) if ($(id)) { $(id).textContent = text; $(id).classList.toggle('vp-error', bad); }
  }
  function report(error) { note(error?.message || 'The native video action failed.', true); controls(); }
  window.wrestlingManagerVideoPilotMessage = message => {
    if (message.requestId) {
      const task = pending.get(message.requestId); if (!task) return;
      clearTimeout(task.timer); pending.delete(message.requestId);
      message.ok ? task.resolve(message.value) : task.reject(Error(message.error || 'Video action failed.'));
      return;
    }
    if (message.scope && message.scope !== scope(context())) return;
    const value = message.value || {};
    switch (message.event) {
      case 'recording':
        if (phase === 'starting') phase = 'recording';
        onScore(snapshot()); note('Recording privately · saving on this iPhone or iPad.'); break;
      case 'stopping': phase = 'stopping'; note(value.reason || 'Finishing the device recording…'); break;
      case 'saved':
        phase = 'idle'; previewMatch = '';
        note(value.take?.status === 'ready' ? 'Saved on this device · upload status is shown below.' :
          value.take?.status === 'partial' ? 'Partial recording saved on this device. ' + (value.take.reason || '') :
            'Playback was not verified. Original files were kept; use Check recovery.', value.take?.status === 'failed');
        const savedGeneration = generation;
        controls(); if (valid()) list().then(() => {if(savedGeneration===generation&&valid())WMVideoUI.saved(['ready','partial'].includes(value.take?.status));}).catch(report); break;
      case 'uploadChanged': if(valid())list().catch(report); break;
      case 'failed': phase = 'idle'; previewMatch = ''; note(value.reason || 'The device save could not be confirmed.', true); break;
      case 'closed':
        if (!['starting', 'recording', 'stopping'].includes(phase)) { phase = 'idle'; previewMatch = ''; }
        break;
      case 'revoked': reset(); return;
      default: return;
    }
    controls(); layout();
  };
  async function authorize(force = false) {
    if (!context().allowed) return false;
    if (!force && valid()) return true;
    if (authorization) return authorization;
    const c = context(), g = generation, requestedAt = performance.now();
    const operation = (async () => {
      const result = await request('authorize', {teamId: c.team, userId: c.user, accessToken: session.access_token, apiKey: SUPABASE_KEY});
      if (g !== generation || scope(c) !== scope(context()) || !context().allowed) return false;
      if (!result?.allowed || result.user_id !== c.user || result.team_id !== c.team || !(result.lease_seconds > 0)) { reset(); return false; }
      // Conservative: transport time is subtracted again rather than extending the native lease.
      grant = {scope: scope(c), overlay: result.camera_overlay === true, until: requestedAt + Math.min(7200, result.lease_seconds) * 1000};
      return valid();
    })();
    authorization = operation;
    try { return await operation; } finally { if (authorization === operation) authorization = null; }
  }
  function shell() {
    if ($('vpPanel') || !$('matchScoreSheet') || !$('matchListSheet')) return;
    const panel = document.createElement('section'); panel.id = 'vpPanel'; panel.className = 'vp-panel'; panel.hidden = true;
    panel.innerHTML = `<span class="vp-badge">VIDEO PILOT · TEST ACCESS</span><h3>Record &amp; score</h3>
      <p>Private recording on this iPhone or iPad. Turn your device sideways for landscape. Choose the orientation before tapping Record; it stays fixed for that take.</p>
      <label class="vp-check"><input id="vpPermission" type="checkbox">I have permission to record these participants at this event.</label>
      <div class="vp-stage" id="vpStage" hidden aria-label="Native match camera preview"></div>
      <div class="vp-actions"><button id="vpPreview" type="button" class="secondary">Open camera</button><button id="vpStart" type="button" class="vp-record" disabled>Record privately</button><button id="vpStop" type="button" disabled>Stop &amp; save video</button><button id="vpClock" type="button" class="secondary" hidden>Start clock</button><button id="vpCameraClose" type="button" class="secondary" hidden>Close camera</button></div>
      <p id="vpStatus" class="vp-status" role="status"></p><p>Keep the app open. Recording stops in the background. Up to 20 minutes per take. Tournament videos upload when service returns while the app is open. Keep device copies until upload is verified. Go live is not connected.</p>
      <details><summary>Saved videos on this device</summary><div id="vpTakes"></div></details>`;
    $('matchScoreSheet').insertBefore(panel, $('matchPeriodLabel'));
    $('vpPreview').onclick = () => preview().catch(report);
    $('vpStart').onclick = () => start().catch(report);
    $('vpStop').onclick = () => stop().catch(report);
    $('vpClock').onclick = () => { if (valid() && phase === 'recording') $('matchToggle').click(); };
    $('vpCameraClose').onclick = () => { post('close'); phase = 'idle'; previewMatch = ''; controls(); };
    const library = document.createElement('section'); library.id = 'vpLibrary'; library.className = 'vp-panel'; library.hidden = true;
    library.innerHTML = '<span class="vp-badge">VIDEO PILOT · TEST ACCESS</span><h3>Saved match videos</h3><p>Saved inside Wrestling Manager on this device, for this account and team. Test videos stay here. Use replay and export to save a copy outside the app.</p><p id="vpLibraryStatus" role="status"></p><div id="vpAllTakes"></div>';
    $('matchListSheet').append(library);
    WMVideoUI.mount();
  }
  function controls() {
    window.WMMatchVideo?.recorderControls(phase === 'recording');
    if (!$('vpPanel')) return;
    const ready = valid(), snap = snapshot(), recording = ['starting', 'recording', 'stopping'].includes(phase);
    $('vpPanel').hidden = !ready || !snap; $('vpLibrary').hidden = !ready;
    $('vpPanel').classList.toggle('vp-capturing', recording);
    $('vpStage').hidden = !ready || !['preview', 'starting', 'recording'].includes(phase);
    $('vpPreview').disabled = !ready || phase !== 'idle';
    $('vpStart').disabled = !ready || phase !== 'preview' || previewMatch !== snap?.id || snap?.status === 'complete';
    $('vpStop').disabled = !ready || !['starting', 'recording'].includes(phase);
    $('vpClock').hidden = !recording; $('vpClock').disabled = phase !== 'recording' || snap?.status === 'complete';
    $('vpClock').textContent = snap?.running ? 'Stop clock' : 'Start clock';
    $('vpCameraClose').hidden = phase !== 'preview'; $('vpPermission').disabled = active();
    WMVideoUI.camera(ready && !!grant?.overlay && ['preview','starting','recording'].includes(phase), true);
    if ($('vpCameraWorkspace')) $('vpCameraWorkspace').classList.toggle('vp-is-recording', recording);
    if ($('vpSavedVideos')) $('vpSavedVideos').disabled = active();
  }
  async function sync() {
    shell(); const g = generation;
    if (!context().allowed) { reset(); return; }
    try {
      if (!await authorize() || g !== generation) { controls(); return; }
      controls();
      if (!statusText) note('Test access ready. Open the camera to record this match.');
      await list();
    } catch (e) { if (g === generation && valid()) report(e); }
  }
  function ensure() { if (!valid()) throw Error('Video test access ended. Reconnect and reopen Match Book.'); }
  async function preview() {
    ensure(); if (phase !== 'idle') return;
    if (!$('vpPermission').checked) throw Error('Confirm recording permission before opening the camera.');
    const state = snapshot(), g = generation;
    if (!state || state.status === 'complete') throw Error('Open an unfinished match to record.');
    phase = 'opening'; controls();
    try {
      await request('preview', {state, permissionConfirmed: true});
      if (g !== generation || !valid() || snapshot()?.id !== state.id || document.hidden) { post('close'); if (g === generation) { phase = 'idle'; previewMatch = ''; } return; }
      previewMatch = state.id; phase = 'preview'; note('Camera ready · nothing is recording yet.');
    } catch (e) { if (g === generation) phase = 'idle'; throw e; }
    finally { controls(); layout(); }
  }
  async function start() {
    ensure(); if (phase !== 'preview') return;
    const state = snapshot(), g = generation;
    if (!state || state.id !== previewMatch || state.status === 'complete' || !$('vpPermission').checked) throw Error('Open the camera for this unfinished match first.');
    phase = 'starting'; lastToken = ''; previousState = null; controls();
    try {
      await request('start', {state, permissionConfirmed: true});
      if (g !== generation || !valid()) post('stop');
    } catch (e) { post('close'); if (g === generation) { phase = 'idle'; previewMatch = ''; } throw e; }
    finally { controls(); layout(); }
  }
  function onScore(state) {
    if (!valid() || !['starting', 'recording'].includes(phase) || !state || state.id !== previewMatch || state.token === lastToken) return;
    const changedLedger = !previousState || JSON.stringify(previousState.ledger) !== JSON.stringify(state.ledger);
    const label = !previousState ? 'Recording started' : changedLedger ? state.ledger.at(-1)?.label || 'Scoring history changed' :
      previousState.running !== state.running ? state.running ? 'Clock started' : 'Clock paused' : 'Match state updated';
    post('snapshot', {state, label}); lastToken = state.token; previousState = structuredClone(state);
  }
  async function stop() {
    if (!['starting', 'recording'].includes(phase)) return;
    onScore(snapshot()); phase = 'stopping'; controls(); layout(); note('Finishing and checking the device recording…');
    try { await request('stop'); }
    catch (e) { report(e); }
  }
  function leaving() {
    if (['starting', 'recording'].includes(phase)) stop();
    else if (phase === 'opening') reset();
    else if (phase === 'preview') { post('close'); phase = 'idle'; previewMatch = ''; }
    controls(); layout();
  }
  function reset() {
    WMVideoUI.reset(); generation++; grant = null; authorization = null; listTicket++; phase = 'idle'; previewMatch = ''; lastToken = ''; previousState = null;
    post('reset'); statusText = '';
    for (const task of pending.values()) { clearTimeout(task.timer); task.reject(Error('The video screen changed. Reopen Match Book to continue.')); }
    pending.clear();
    if ($('vpPanel')) {
      $('vpPanel').hidden = $('vpLibrary').hidden = true; $('vpStage').hidden = true; $('vpPermission').checked = false;
      $('vpTakes').replaceChildren(); $('vpAllTakes').replaceChildren();
    }
  }
  function display(state) {
    const s = WMVideoCore.stateAt([{atMs: 0, state}], 0), seconds = Math.ceil(s.remainingMs / 1000);
    return `${String(s.red_name).slice(0, 55)}  ${s.scores.red}   •   ${s.scores.other}  ${String(s.other_name).slice(0, 55)}\n${s.phaseLabel}   ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  }
  function layout() {
    if (!['preview', 'starting', 'recording'].includes(phase) || !$('vpStage') || !valid()) return;
    const rect = $('vpStage').getBoundingClientRect(), cx = Math.min(innerWidth - 1, Math.max(0, rect.x + rect.width / 2)), cy = Math.min(innerHeight - 1, Math.max(0, rect.y + rect.height / 2));
    const overlay = !!$('vpCameraWorkspace');
    const visible = !$('vpStage').hidden && rect.width > 0 && rect.height > 0 && (overlay ? !$('matchScoreSheet').classList.contains('hidden') : !!document.elementFromPoint(cx, cy)?.closest('#vpStage'));
    post('layout', {visible, overlay, x: rect.x, y: rect.y, width: rect.width, height: rect.height, viewportWidth: innerWidth,
      text: snapshot() ? display(snapshot()) : ''});
  }
  async function list() {
    ensure(); const g = generation, ticket = ++listTicket;
    const result = await request('list');
    if (g !== generation || ticket !== listTicket || !valid()) return;
    const rows = result.takes || []; WMVideoUI.count(rows.length);
    function render(container, matches) {
      container.innerHTML = matches.length ? matches.map(row => `<div class="vp-take"><b>${row.demo ? 'Demo · ' : ''}${esc(row.label)}</b><p>${esc(row.status === 'ready' ? 'Saved on this device' : row.status === 'partial' ? 'Partial recording on this device' : 'Interrupted recording · recovery check needed')} · ${esc(new Date(row.createdAt).toLocaleString())}</p><p>${esc(row.reason || '')}${row.boutId?' · '+(row.upload?.status==='ready'?'Uploaded · available to athlete & family':row.upload?.status==='uploading'?'Uploading '+(row.upload.progress||0)+'%':'Waiting to upload'):''}</p><div class="vp-actions">${['ready', 'partial'].includes(row.status) ? `<button type="button" data-action="play" data-id="${esc(row.id)}">Replay &amp; export</button>` : `<button type="button" data-action="recover" data-id="${esc(row.id)}">Check recovery</button>`}<button type="button" class="secondary" data-action="delete" data-id="${esc(row.id)}">Delete device copy</button></div></div>`).join('') : '<p>No saved videos for this account and team on this device.</p>';
      container.querySelectorAll('button').forEach(button => button.onclick = async () => {
        try {
          ensure(); if (active()) throw Error('Stop and save your recording first.');
          if(button.dataset.action==='delete'){const row=rows.find(r=>r.id===button.dataset.id);if(row?.boutId&&row.upload?.status!=='ready')throw Error('Wait for the verified upload before removing this device copy.');if(!confirm(row?.upload?.status==='ready'?'Remove the device copy? The uploaded video stays available to the athlete and family.':'Delete this device recording and its score timeline? There is no cloud copy.'))return;}
          post('close'); phase = 'idle'; previewMatch = ''; controls();
          button.disabled = true;
          await request(button.dataset.action, {id: button.dataset.id});
          if (valid()) await list();
        } catch (e) { report(e); } finally { button.disabled = false; }
      });
    }
    if ($('vpTakes')) render($('vpTakes'), rows.filter(row => row.matchId === snapshot()?.id));
    if ($('vpAllTakes')) render($('vpAllTakes'), rows);
  }
  function monitor() {
    if (grant && !valid()) { reset(); return; }
    if (previewMatch && (document.hidden || snapshot()?.id !== previewMatch)) { leaving(); return; }
    if (['preview', 'starting', 'recording'].includes(phase)) { post('heartbeat'); controls(); layout(); }
  }
  setInterval(monitor, 250);
  setInterval(async () => {
    if (!grant || !context().allowed || refreshing || !navigator.onLine) return;
    refreshing = true;
    try { await authorize(true); controls(); } catch { /* The bounded native lease supports temporary arena outages. */ }
    finally { refreshing = false; }
  }, 60000);
  document.addEventListener('scroll', layout, true); window.addEventListener('resize', layout);
  document.addEventListener('visibilitychange', () => { if (document.hidden) leaving(); });
  window.addEventListener('pagehide', reset);
  window.addEventListener('beforeunload', event => { if (active()) { event.preventDefault(); event.returnValue = ''; } });
  async function uploadQueue(){if(!valid()||active()||!navigator.onLine||document.hidden)return;await request('uploadNext');}
  window.addEventListener('online',()=>uploadQueue().catch(()=>{}));
  setInterval(()=>uploadQueue().catch(()=>{}),30000);
  async function quickStart(){await sync();ensure();if(!snapshot()?.bout_id)throw Error('Open an assigned tournament bout.');$('vpPermission').checked=true;await preview();await start();}
  async function openLibrary(){if(active())throw Error('Stop and save your recording first.');await sync();ensure();post('close');phase='idle';previewMatch='';controls();WMVideoUI.openLibrary();await list();}
  window.WMVideoPilot = {sync, onScore, leaving, reset, active,quickStart,openLibrary};
})();
