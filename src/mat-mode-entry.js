// Plain Mat Mode links open the installed app's offline screen. Connected
// chairman/judge links and an existing web session keep their original route.
(() => {
  'use strict';
  document.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest?.('a[data-wm-mat-mode]');
    if (!link || link.hasAttribute('download') || (link.target && link.target !== '_self')) return;
    const destination = new URL(link.href, location.href);
    const plainMat = new URL('./mat-mode.html', location.href);
    if (destination.href !== plainMat.href) return;
    // Never open another screen over the web session's exit-PIN gate.
    try { if (localStorage.getItem('wm-mat-session')) return; } catch { return; }
    const handler = window.webkit?.messageHandlers?.offlineMatMode;
    if (typeof handler?.postMessage !== 'function') return;
    event.preventDefault();
    document.getElementById('wmMatEntryStatus')?.remove();
    try {
      handler.postMessage({command: 'open'});
    } catch {
      const status = document.createElement('p');
      status.id = 'wmMatEntryStatus';
      status.setAttribute('role', 'status');
      status.textContent = 'Mat Mode could not open. Try again or use the Mat Mode icon at the top of the app.';
      link.insertAdjacentElement('afterend', status);
    }
  });
})();
