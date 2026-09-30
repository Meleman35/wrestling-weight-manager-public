# Account deletion: offline workspace adapter (draft)

September 29, 2026. `src/account-deletion-device.js` is unmounted and does not run at import. It is not included in `index.html`, the service worker, or native revision 20. No live account or device is changed by adding this file. Account-deletion intake and fulfillment remain disabled and undeployed.

## Exact implemented scope

`WMAccountDeletionDevice.clearOfflineAccount({subjectId, requestId}, {signal})` replaces only the specified account's entries in the `keys` and `records` stores of IndexedDB `wm-coach-offline-v1`, version 1. These are the encrypted offline packs, queue/history, event drafts, chat drafts and conflict copies written by the current `WMOfflineStore`. It does not resolve a child, family or team from the account, and does not enumerate or delete any other account.

A single strict-durability read/write transaction replaces the CryptoKey and encrypted record with content-free deletion markers. A separate read transaction must verify both exact markers before returning `offlineWorkspaceCleared: true`. This is deliberately narrow evidence, not `deviceClean`, account deletion completion or server revocation proof. Errors and cancellations never return success; retries are idempotent. Database-open/transaction waits are bounded, and provider/storage error bodies are not returned.

Why markers instead of simply deleting the two keys: an old open app window can already be encrypting an offline save. Its existing revision comparison must encounter a changed record rather than an absent row. Record marker version 0 is unreadable to the unchanged version-1 store; the non-CryptoKey key marker also stops a first-key-creation race. Valid old records have UUID revisions and cannot equal the marker's reserved revision. No database version upgrade or changes to the released store are needed for this compatibility check.

Markers retain the account UUID only as the IndexedDB key. They contain no request ID, email, child/team identifiers, timestamps, ciphertext or encryption key. Retaining even this minimal local account fence needs an approved lifecycle/retention policy; it is not anonymous data. This operation does not promise forensic disk wiping or removal from browser/OS backups.

## Mandatory integration gates

This adapter is **not authorization**. The future controller must derive the account/request pair from freshly verified server deletion state, not URL parameters or an arbitrary UI field. UUID validation only prevents malformed local keys. Do not invoke cleanup merely because a request was opened or canceled, or because a device is offline.

Before mounting it, implement and verify:

- Server-side access denial for the departing account, including stale JWTs, managed access, asynchronous delivery/outbox jobs and provider tokens. Stop outgoing work before cleaning local storage. This adapter cannot recall an already-sent network request.
- Account-scoped disposal of pending reads, decrypted in-memory views and editors in every open tab/native web view, with a reconnect handshake before any flush. Already-decrypted data can still exist in memory after the storage transaction; markers do not recall that memory or prove global access revocation.
- The complete inventory of other local stores: legacy localStorage/sessionStorage, match drafts and native recording manifests/files, auth sessions/bridge/keychain data and other devices. These are **untouched**, not certified absent. Preserve recorder originals and user-exported Photos/Files copies according to the separately reviewed policy.
- Tested browser/native lifecycle and retention behavior on distributed iPhone/iPad Build 4 and the fixed Mac app. Chromium tests do not establish WKWebView, radio, camera, native file or App Review acceptance.

Unknown database versions or additional stores fail closed with `device_scope_unreviewed`. There is no fallback to `clear()`, `deleteDatabase()`, app uninstall, blanket Web Storage clearing or deleting shared shell caches. A future schema must receive its own reviewed adapter.

## Validation

Run `NODE_PATH=.ci/node_modules node tests/account-deletion-device.cjs` with the repository's pinned Playwright and Chromium. The test loads the unchanged `src/offline-store.js` and the new adapter, using real Chromium IndexedDB/WebCrypto with synthetic accounts. It checks 14 groups: import/invalid-scope side effects, account isolation, unrelated storage preservation, legacy read/write denial, concurrent retries, a second browsing context, suspended encryption and first-key-generation races, transaction rollback, cancellation, independent verification failure, unavailable storage and unknown schema refusal.

The runner writes `validation/account-deletion-device.json`; the launch-readiness workflow runs it and uploads that report. An unrelated synthetic video database sentinel checks that this adapter never clears unrelated storage; it is not a test of the real native recording database.

Local JavaScript syntax checks were run. Browser navigation in the preparation workspace was blocked by its administrator policy, so full browser execution is delegated to the existing draft-branch GitHub Actions checks, with results to be recorded only after those checks complete. No production deployment or deletion is part of this test.

References: current source `src/offline-store.js` and `src/chat-drafts.js`; MDN IndexedDB transaction documentation; Supabase user-management/session documentation for the separate stale-token gate. See `docs/account-deletion-fulfillment.md` for the still-incomplete server/provider/record adapters.
