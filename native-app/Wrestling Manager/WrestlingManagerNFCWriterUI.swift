import Foundation

enum WrestlingManagerNFCWriterUI {
    static let script = #"""
    (() => {
      const u = new URL(location.href);
      const trusted = u.protocol === 'https:' && (!u.port || u.port === '443') && !u.username && !u.password &&
        ((u.hostname === 'theteammanager.app' && ['/', '/index.html'].includes(u.pathname)) ||
         (u.hostname === 'meleman35.github.io' && (u.pathname === '/wrestling-weight-manager-public' || u.pathname.startsWith('/wrestling-weight-manager-public/'))));
      if (window.top !== window || !trusted || window.wmNFCWriterInstalled) return;
      const bridge = window.webkit?.messageHandlers?.athleteNfc;
      const button = document.getElementById('programAthleteNfcBtn');
      const sheet = document.getElementById('athleteCardSheet');
      const status = document.getElementById('athleteCardStatus');
      if (!bridge || !button || !sheet || !status || typeof window.wrestlingManagerNfcResult !== 'function') return;
      window.wmNFCWriterInstalled = true;
      const originalResult = window.wrestlingManagerNfcResult;
      // The original status sits above the large QR card. Mirror it beside
      // the writer controls so an iPad scrolled to Program can see every step.
      const progress = document.createElement('p'); progress.id = 'wmNFCWriteStatus';
      progress.className = 'fine'; progress.setAttribute('role', 'status');
      progress.setAttribute('aria-live', 'polite');
      progress.setAttribute('style', 'font-size:16px;line-height:1.4;margin:12px 0;overflow-wrap:anywhere');
      function syncStatus() { progress.textContent = status.textContent; }
      function say(text) { status.textContent = text; syncStatus(); }
      new MutationObserver(syncStatus).observe(status, {childList:true, characterData:true, subtree:true});
      const label = document.createElement('label'); label.textContent = 'Program card using';
      const select = document.createElement('select'); select.id = 'wmNFCWriter';
      select.setAttribute('aria-label', 'Card writer'); label.append(select); button.before(label, progress);
      const stop = document.createElement('button'); stop.type = 'button'; stop.className = 'wide secondary';
      stop.textContent = 'Cancel programming'; stop.hidden = true; button.after(stop);
      const replacement = document.createElement('div'); replacement.hidden = true;
      replacement.setAttribute('role', 'group'); replacement.setAttribute('aria-label', 'Replace card contents');
      const explanation = document.createElement('p');
      const replace = document.createElement('button'); replace.type = 'button'; replace.className = 'wide';
      replace.textContent = 'Replace card contents';
      const keep = document.createElement('button'); keep.type = 'button'; keep.className = 'wide secondary';
      keep.textContent = 'Cancel — keep current card';
      replacement.append(explanation, replace, keep); stop.after(replacement);
      let active = null;
      const state = () => window.wrestlingManagerNativeNFCStatus || {};
      const open = () => !document.hidden && !sheet.classList.contains('hidden') &&
        !document.body.classList.contains('kiosk-locked') && !document.querySelector('#appLockOverlay:not(.hidden)');
      const ready = source => source === 'bluetooth' ? state().externalConnected === true : source === 'builtin' && state().builtInAvailable === true;
      function current(id, token, readerID) {
        const a = active;
        return !!(a && a.id === id && a.token === token && a.readerID === readerID && open() &&
          pendingNfcRequest === a.request && session === a.session && session?.user?.id === a.userID &&
          activeTeam?.id === a.teamID && activeSeason?.id === a.seasonID &&
          activeAthleteCard === a.card && activeAthleteCard?.credential_token === a.token &&
          activeAthleteCard?.athlete_id === a.athleteID && athleteCardRequestVersion === a.version &&
          document.getElementById('athleteCardSelect')?.value === String(a.athleteID) &&
          athleteCardRows.some(row => String(row.athlete_id) === String(a.athleteID)) &&
          select.value === a.source && ready(a.source) &&
          (a.source !== 'bluetooth' || state().readerIdentifier === a.readerID));
      }
      window.wmNFCWriterIsCurrent = current;
      function clear() {
        if (active) clearTimeout(active.timeout);
        active = null; stop.hidden = true; replacement.hidden = true; select.disabled = false; button.disabled = false;
      }
      function cancel() {
        if (!active) return;
        const id = active.id;
        if (pendingNfcRequest === active.request) pendingNfcRequest = null;
        clear(); bridge.postMessage({command:'cancel', requestId:id});
        say('Programming cancelled. If writing had started, program the card again before using it.');
        update();
      }
      function update() {
        const s = state(), chosen = active?.source || s.writerSource || select.value || (s.externalConnected ? 'bluetooth' : 'builtin');
        const options = [];
        if (s.externalConnected || chosen === 'bluetooth') options.push(['bluetooth', (s.readerName || 'Bluetooth NFC reader') + (s.externalConnected ? '' : ' — disconnected')]);
        if (s.builtInAvailable || chosen === 'builtin') options.push(['builtin', 'iPhone NFC' + (s.builtInAvailable ? '' : ' — unavailable')]);
        const key = JSON.stringify(options);
        if (select.dataset.options !== key) {
          select.replaceChildren();
          for (const [value, text] of options) { const option = document.createElement('option'); option.value = value; option.textContent = text; select.append(option); }
          select.dataset.options = key;
        }
        select.value = chosen;
        button.textContent = active ? 'Programming…' : 'Program Card / Wristband';
        button.disabled = !!active || !ready(chosen);
        if (active && !current(active.id, active.token, active.readerID)) { cancel(); return; }
        if (active?.source === 'bluetooth' && !replacement.hidden) return;
        if (active?.source === 'bluetooth' && s.readerMessage) say(s.readerMessage);
        syncStatus();
      }
      select.onchange = () => { if (active) cancel(); bridge.postMessage({command:'selectWriter', writer:select.value}); };
      button.onclick = () => {
        if (!open() || !session?.user?.id || !activeTeam || !activeAthleteCard) return;
        if (pendingNfcRequest || active) { message('Finish or cancel the current card operation first.', true); return; }
        const source = select.value, c = activeAthleteCard;
        if (!ready(source)) { say('Connect the selected reader in Scale & Card Reader Setup, then try again.'); return; }
        if (!athleteCardRows.some(row => String(row.athlete_id) === String(c.athlete_id))) return;
        if (source === 'builtin' && !confirm(`Program this card for ${c.first_name} ${c.last_name}? Existing tag contents will be replaced.`)) return;
        const id = crypto.randomUUID();
        const request = {id, mode:'write', athleteId:c.athlete_id, teamId:activeTeam.id, userId:session.user.id};
        pendingNfcRequest = request;
        active = {id, request, source, card:c, token:c.credential_token, athleteID:c.athlete_id,
          userID:session.user.id, teamID:activeTeam.id, seasonID:activeSeason?.id, session,
          version:athleteCardRequestVersion, readerID:source === 'bluetooth' ? state().readerIdentifier : '',
          timeout:setTimeout(cancel, 125000)};
        select.disabled = true; button.disabled = true; stop.hidden = false;
        say(source === 'bluetooth' ? 'Place one card on the reader. Leave it there until programming and verification finish.' : 'Hold the card against the top of the iPhone.');
        bridge.postMessage({command:'write', requestId:id, token:c.credential_token, writer:source, readerIdentifier:active.readerID});
      };
      stop.onclick = cancel; keep.onclick = cancel;
      replace.onclick = () => {
        if (!active || !current(active.id, active.token, active.readerID)) { cancel(); return; }
        replacement.hidden = true;
        say('Checking the card again before replacing its contents…');
        bridge.postMessage({command:'confirmWrite', requestId:active.id, approved:true});
      };
      window.wrestlingManagerNfcResult = async result => {
        if (result?.event === 'status') { await originalResult(result); update(); return; }
        if (!active || result?.requestId !== active.id) return originalResult(result);
        if (!current(active.id, active.token, active.readerID)) { cancel(); return; }
        if (result.event === 'replaceRequired') {
          explanation.textContent = `This card already contains data. Replace it with ${active.card.first_name} ${active.card.last_name}'s athlete card? Its current contents will be lost.`;
          replacement.hidden = false; say('Confirm whether to replace this card.'); return;
        }
        // A write acknowledgement is accepted only within the original scope.
        clear(); await originalResult(result);
        if (result.cancelled && result.message) say(result.message);
        update();
      };
      window.addEventListener('wmNFCReaderStatus', update);
      document.addEventListener('visibilitychange', () => { if (document.hidden) cancel(); });
      window.addEventListener('pagehide', cancel);
      new MutationObserver(() => { if (active && !current(active.id, active.token, active.readerID)) cancel(); }).observe(document.body, {attributes:true, childList:true, subtree:true, attributeFilter:['class']});
      setInterval(() => { if (active && !current(active.id, active.token, active.readerID)) cancel(); }, 200);
      update(); bridge.postMessage({command:'status'});
    })();
    """#
}
