# v0.20.89 — offline availability and settings layout

The reported screenshots show the installed native app attempting the browser-only pilot, plus a settings button without the standard full-width styling. The old flow asked for a PIN and offered Download before discovering that service workers were unavailable. It also treated navigator.onLine as proof of an internet connection.

Changes:
- Match Offline workspace to the full-width settings buttons with the same spacing.
- Label the native entry “Offline workspace · Safari.” Before PIN or download, explain that native offline team support needs an app update and give the correct website address with Copy.
- Detect unsupported browser APIs and insecure contexts before the download flow.
- Do not offer unsupported native download/sync actions or register a service worker in that native container.
- Remove the unverified Connected claim. Show pending changes and an Offline hint when the browser reports it.
- Place Download and Sync in a spaced, full-width action group on supported browsers.
- Bump the static cache version; retain all IndexedDB data and queued work.

Validation: all six focused `tests/offline-089-browser.cjs` checks pass, including native entry before PIN, correct address copy, Back returning to settings, unsupported browser detection, supported-browser access, and matching bounds at 320/390/430/768px. All 18 `tests/offline-088-browser.cjs` checks still pass, including restart, storage failure, conflict handling and outbox persistence. Phone screenshots were visually inspected; inline JS and whitespace checks pass.

This corrects availability and layout. It does not enable native iPhone/iPad offline startup. That still requires native source/build integration and physical-device verification. No database migrations or native binaries are changed in this release.
