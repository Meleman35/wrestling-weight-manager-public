import Foundation

// The exact same compatibility module is supplied in the web patch. A one-time
// install guard prevents duplicate handlers when the web release catches up.
enum WrestlingManagerVideoScorerUI {
    static let script = #"""
(() => {
  const appURL = new URL(location.href);
  const customApp = appURL.origin === 'https://theteammanager.app' &&
      ['', '/', '/index.html'].includes(appURL.pathname);
  const legacyApp = appURL.origin === 'https://meleman35.github.io' &&
      (appURL.pathname === '/wrestling-weight-manager-public' || appURL.pathname.startsWith('/wrestling-weight-manager-public/'));
  if (appURL.username || appURL.password || !(customApp || legacyApp)) return;
/* Presentation-only compatibility for Match Book 0.20.47 and the native video pilot.
 * Uses the existing scorer/confirmation/save path. No new point engine or permissions.
 * Also bundled in native revision 7 so the pilot is testable before a web release.
 */
(() => {
  'use strict';
  if (window.WMVideoScorerControls) return;
  const $ = id => document.getElementById(id);
  const snap = () => window.WMMatch?.videoSnapshot?.();
  function control(state) {
    if (!state || state.style === 'beach') return null;
    // The existing engine owns control, including Undo and corrected positions.
    const value = window.WMScoring?.state(state);
    return value === 'red' || value === 'other' ? value : null;
  }
  const name = (state, side) => `${side === 'red' ? state.red_name || 'Red' : state.other_name || 'Opponent'} · ${side === 'red' ? 'Red' : state.style === 'folkstyle' ? 'Green' : 'Blue'}`;
  let observer = null, observed = null;
  function refresh() {
    const state = snap(), top = control(state), corners = $('matchCorners');
    if (corners && corners !== observed) {
      observer?.disconnect(); observed = corners;
      observer = new MutationObserver(refresh);
      observer.observe(corners, {childList: true, subtree: true});
    }
    for (const button of corners?.querySelectorAll('[data-fall]') || []) {
      const available = !!state && state.status !== 'complete' && state.phase === 'period' && button.dataset.fall === top;
      button.hidden = !available;
      button.setAttribute('aria-label', `${name(state || {}, button.dataset.fall)}: confirm fall or defensive fall`);
    }
    const badge = $('vpPanel')?.querySelector('.vp-badge');
    if (badge && Number(window.wrestlingManagerNativeVideoSourceRevision) >= 7) badge.textContent = `VIDEO PILOT · TEST ACCESS · NATIVE r${Number(window.wrestlingManagerNativeVideoSourceRevision)}`;
    const copy = $('vpPanel')?.querySelector('h3 + p');
    if (Number(window.wrestlingManagerNativeVideoSourceRevision) >= 7 && copy?.textContent.includes('Choose the orientation before tapping Record')) {
      copy.textContent = 'Turn sideways before Record for a landscape movie. Controls can rotate during recording; the saved movie keeps its starting shape.';
    }
  }
  function installDialog() {
    const operations = window.WMOperations;
    if (!operations?.dialog || operations.dialog.wmVideoFalls) return;
    const original = operations.dialog;
    const wrapped = async function(spec) {
      const state = snap(), top = control(state);
      if (spec?.title !== 'Finish match' || !state || !top || !spec.fields?.some(f => f.id === 'result' && f.options?.some(o => o[0] === 'Fall'))) {
        return original.call(this, spec);
      }
      const defender = top === 'red' ? 'other' : 'red';
      const fields = spec.fields.map(field => field.id === 'result' ? {...field, options: [
        ...field.options.filter(option => option[0] !== 'Defensive Fall'),
        ['Defensive Fall', `Defensive Fall · ${name(state, defender)} wins`]
      ]} : field);
      const answer = await original.call(this, {...spec, fields});
      if (!answer || answer.result !== 'Defensive Fall') return answer;
      if (snap()?.id !== state.id || control(snap()) !== top) return null;
      // Never silently reverse the selected winner. Name the defensive winner
      // explicitly and require a separate referee-result confirmation.
      const confirm = await original.call(this, {
        title: 'Confirm defensive fall',
        description: `${name(state, defender)} wins by pinning ${name(state, top)}, who was recorded in control. No escape or reversal points will be added. Confirm only the referee’s result.`,
        fields: [], submit: `Confirm ${defender === 'red' ? 'Red' : state.style === 'folkstyle' ? 'Green' : 'Blue'} wins`
      });
      if (!confirm || snap()?.id !== state.id || control(snap()) !== top) return null;
      return {...answer, winner: defender, result: 'Defensive Fall'};
    };
    wrapped.wmVideoFalls = true;
    operations.dialog = wrapped;
  }
  // Prevent a stale/hidden button from being activated between a rerender and the observer.
  document.addEventListener('click', event => {
    const button = event.target?.closest?.('#matchCorners [data-fall]');
    if (!button) return;
    const state = snap();
    if (!state || state.phase !== 'period' || state.status === 'complete' || control(state) !== button.dataset.fall) {
      event.preventDefault(); event.stopImmediatePropagation(); refresh();
    }
  }, true);
  function install() { installDialog(); refresh(); }
  window.WMVideoScorerControls = {revision: 1, control, refresh, install};
  install();
  const timer = setInterval(install, 500);
  window.addEventListener('pagehide', event => {if (!event.persisted) {clearInterval(timer); observer?.disconnect();}});
})();

})();
"""#
}
