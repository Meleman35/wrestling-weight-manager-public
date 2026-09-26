/* Camera presentation only. Move the actual scorer controls; never duplicate scoring logic. */
window.WMVideoUI = (() => {
  'use strict';
  const $ = id => document.getElementById(id);
  let workspace = null, moved = [], library = null, libraryMark = null, previousFocus = null, overtimeMark = null;
  function move(node, parent) {
    if (!node) return;
    const mark = document.createComment('video control position');
    node.before(mark); moved.push([node, mark]); parent.append(node);
  }
  function camera(enabled, native = false) {
    if (!enabled) {
      if (!workspace) return;
      overtime(false);
      for (const [node, mark] of moved.reverse()) mark.replaceWith(node);
      moved = []; workspace.remove(); workspace = null;
      $('matchScoreSheet')?.classList.remove('vp-camera-sheet');
      document.body.classList.remove('vp-camera-mode', 'vp-native-camera');
      return;
    }
    if (workspace || !$('vpStage')) return;
    closeLibrary();
    const sheet = $('matchScoreSheet');
    workspace = document.createElement('div'); workspace.id = 'vpCameraWorkspace';
    workspace.innerHTML = `<div class="vp-camera-clock"></div><div class="vp-camera-bar"></div>
      <div class="vp-camera-foot"><button id="vpMore" class="secondary" type="button" aria-expanded="false" aria-controls="vpMorePanel">More controls</button></div>
      <section id="vpMorePanel" hidden><div class="vp-head"><h3>Match controls</h3><button id="vpMoreClose" type="button">Back to camera</button></div><div id="vpMoreControls"></div></section>`;
    sheet.append(workspace);
    move($('vpStage'), workspace);
    move($('matchCorners'), workspace);
    for (const id of ['matchPeriodLabel', 'matchClock', 'matchToggle']) move($(id), workspace.querySelector('.vp-camera-clock'));
    for (const id of ['vpStart', 'vpStop', 'vpCameraClose']) move($(id), workspace.querySelector('.vp-camera-bar'));
    move($('vpLiveState'), workspace.querySelector('.vp-camera-foot'));
    move($('matchUndo'), workspace.querySelector('.vp-camera-foot'));
    // Keep every remaining scoring action, including conditionally available actions, intact.
    for (const node of [...sheet.children]) {
      if (node === workspace || node.id === 'vpPanel' || node.classList.contains('sheet-handle') || node.classList.contains('sheet-head')) continue;
      move(node, $('vpMoreControls'));
    }
    const more = open => { $('vpMorePanel').hidden = !open; $('vpMore').setAttribute('aria-expanded', String(open)); (open ? $('vpMoreClose') : $('vpMore')).focus({preventScroll:true}); };
    $('vpMore').onclick = () => more(true); $('vpMoreClose').onclick = () => more(false);
    sheet.classList.add('vp-camera-sheet'); document.body.classList.add('vp-camera-mode');
    document.body.classList.toggle('vp-native-camera', native); sheet.scrollTop = 0;
  }
  function overtime(ready) {
    if (!workspace) return;
    const button = $('matchOvertime');
    if (ready && !overtimeMark) { overtimeMark = document.createComment('overtime control position'); button.before(overtimeMark); workspace.querySelector('.vp-camera-clock').append(button); }
    else if (!ready && overtimeMark) { overtimeMark.replaceWith(button); overtimeMark = null; }
  }
  function mount() {
    if (!$('vpPanel') || $('vpSavedVideos')) return;
    const row = document.createElement('div'); row.className = 'vp-saved-entry';
    row.innerHTML = '<button id="vpSavedVideos" type="button" class="secondary">Saved videos</button><p id="vpSavedNotice" role="status" hidden></p>';
    $('vpPanel').append(row);
    $('vpSavedVideos').onclick = () => window.WMVideoPilot.openLibrary().catch(e => { $('vpSavedNotice').hidden = false; $('vpSavedNotice').textContent = e.message; });
  }
  function count(n) { if ($('vpSavedVideos')) $('vpSavedVideos').textContent = `Saved videos (${n})`; }
  function saved(ok) {
    if (!$('vpPanel')) return;
    const details = $('vpTakes')?.closest('details'); if (details) details.open = true;
    const notice = $('vpSavedNotice');
    if (notice) { notice.hidden = false; notice.textContent = ok ? 'Video saved in this app. Replay below, or open Saved videos. It is not added to Photos automatically.' : 'Original files kept. Open Saved videos to check recovery.'; }
    if (!$('matchScoreSheet').classList.contains('hidden')) {
      $('vpSavedVideos')?.scrollIntoView({block:'center'}); $('vpSavedVideos')?.focus({preventScroll:true});
    }
  }
  function closeLibrary() {
    if (!library) return;
    if (libraryMark) libraryMark.replaceWith($('vpLibrary'));
    library.remove(); library = null; libraryMark = null;
    if (previousFocus?.isConnected) previousFocus.focus({preventScroll:true}); previousFocus = null;
  }
  function openLibrary() {
    if (library) return;
    const content = $('vpLibrary'); if (!content || content.hidden) throw Error('Reconnect and reopen Match Book to check saved-video access.');
    previousFocus = document.activeElement; libraryMark = document.createComment('saved video library'); content.before(libraryMark);
    library = document.createElement('section'); library.className = 'vp-replay'; library.id = 'vpDeviceLibrary';
    library.setAttribute('role','dialog'); library.setAttribute('aria-modal','true'); library.setAttribute('aria-label','Saved videos');
    library.innerHTML = '<div><div class="vp-head"><h2>Saved videos</h2><button type="button" id="vpLibraryClose">Close</button></div></div>';
    library.firstElementChild.append(content); document.body.append(library);
    $('vpLibraryClose').onclick = closeLibrary; $('vpLibraryClose').focus();
  }
  function reset() { camera(false); closeLibrary(); if ($('vpSavedNotice')) { $('vpSavedNotice').hidden = true; $('vpSavedNotice').textContent = ''; } count(0); }
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && library) { e.stopPropagation(); closeLibrary(); } });
  return {camera, overtime, mount, saved, count, openLibrary, closeLibrary, reset};
})();
