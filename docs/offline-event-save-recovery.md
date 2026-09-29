# Offline event save recovery — proposed v0.20.91

Prepared September 28, 2026, Mountain time. Baseline: main commit `d3c4c8b696cfd81813495eb199c1d2dd6441452a` (v0.20.90).

## Problem and change

When an offline event edit failed to commit to device storage, `queue()` rendered the saved event again. The user's unsaved title, notes and other form values disappeared. Rejecting a second edit while the first was still queued had the same effect.

The event form now stays intact after a failed save and its submit button becomes available again. Other queue forms keep their existing rendering behavior. A late failure from a previous workspace/profile cannot replace the new screen's status. The existing encrypted store, operation IDs, duplicate guard and server revision checks are unchanged. Successful saves still follow the existing render/sync path.

The source and embedded index are identical. The proposed app label and static service-worker cache advance to v0.20.91 so a future release can install the corrected shell through the existing waiting-worker lifecycle. This draft does not deploy it.

## Verification

The new regression test failed on the unchanged baseline: expected the edited title `Keep my revised practice`, but the UI reverted to `Practice` after an injected storage failure.

With the fix, five checks pass in Node using jsdom 26.0.0, fake-indexeddb 6.0.0 and Web Crypto against the actual production workspace and encrypted-store scripts:

1. A rejected storage commit leaves no queued item, keeps the edited fields and enables retry.
2. Retrying persists the original edited values exactly once with the original server revision.
3. A duplicate-edit rejection preserves both the existing operation and the user's new form input.
4. Lock clears the unsaved fields from the screen and retains the encrypted outbox.
5. A late save failure after a profile change leaves the new profile's screen and status alone.

The test also verifies that the deployed bundle contains the exact workspace source. JavaScript syntax and `git diff --check` pass. Results: `validation/offline-save-recovery.json`.

Run the focused fixture with these pinned dependencies installed outside the repo:

```sh
npm install --prefix /tmp/wm-offline-test --no-audit --no-fund jsdom@26.0.0 fake-indexeddb@6.0.0
NODE_PATH=/tmp/wm-offline-test/node_modules node tests/offline-save-recovery.cjs
```

The Playwright companion `tests/offline-save-recovery-browser.cjs` exercises the full embedded app with the existing fake server adapter. Its browser execution remains pending: the available Chromium process crashed at startup and the Playwright browser download returned an unavailable page. No browser/device pass is claimed. Before release, run it plus `tests/offline-refresh-090-browser.cjs` and `tests/offline-088-browser.cjs` with a working Chromium executable.

## Scope and remaining checks

This is the browser Offline workspace. The installed native app still directs this feature to Safari; this fix does not add native offline startup or expand offline support to all app screens. Unsaved event fields remain only in the open form after a failed commit; closing or locking still clears them. No new draft-persistence guarantee is introduced.

No database migration, production API call, message delivery, native source change or deployment was performed. The Supabase changelog was checked for relevant contract changes; this patch does not change Supabase calls or schema. The browser fixtures use local synthetic teams only.

Device acceptance: test a storage failure and retry in Safari, verify the existing reconnect/conflict flow, and verify the new static shell activates only through the current safe update lifecycle.
