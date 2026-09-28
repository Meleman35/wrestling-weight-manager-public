# Full offline operation — requested September 28, 2026

Status: v0.20.88 adds a browser-first **Offline workspace** for personal coach accounts. It downloads a bounded, clearly labeled core team pack and enables durable attendance marks, individual event edits and queued text messages there. Full-app offline operation is still incomplete. The normal app screens remain online paths; this document preserves the remaining work.

Damon needs Wrestling Manager to remain usable underground, at school, and at tournaments without service. Download all records the signed-in person is authorized to access onto their device, allow offline work, preserve it across force quit/restart, then reconcile with the server on reconnect. Apple/iPhone/iPad first; preserve current web users. Coaches must be able to compose and queue messages offline. Maintain guardian visibility and communication safeguards.

## Current source findings

- Core loads and writes call Supabase tables/RPCs directly; the main app is not backed by a durable replicated local database.
- Online reconnect currently triggers `refreshTeamData`, which refreshes data but does not constitute an offline write queue.
- `sendCommunicationMessage` calls `send_communication_message` directly; a failed send stays in the visible text box but has no general persistent outbox or stable retry identity. It must not be advertised as safe offline sending.
- Official weigh-in sheets have a dedicated IndexedDB store. Video pilot has device-local storage and a bounded offline authorization lease. Keep both systems intact; coordinate their inventories rather than migrating/deleting existing recordings.
- Auth/session state, roles and data-loading error handling need an explicit offline startup path. A valid local session, app PIN/Face ID and previously downloaded data must work without a network login attempt deleting the cached workspace.
- Current repository contains the web application; native package/background-task changes require locating the actual iOS source and validating a new native build.

## Implemented in v0.20.88

- Profile → Offline workspace; existing profile PIN gate and account isolation. Download requires current online coach access and an active team/season.
- Complete keyset pagination for the roster, season team events, attendance and permitted thread directory. Latest 80 messages per thread only; no attachment bytes, organization events, removed roster members, full profile/medical records or full message archive. A failed download retains the previous pack. Packs are snapshots, not a single database-wide point-in-time snapshot.
- A static-only service worker and vendored Supabase JS 2.117.2 enable browser startup without the CDN. Updates wait for prior controlled app windows to close; they never force reload a recorder. Service-worker cache contains no authenticated API responses.
- Account-scoped AES-GCM encrypted IndexedDB documents and nonextractable origin-stored CryptoKeys. This is browser-origin encryption plus the existing PIN UI gate, **not** a PIN-derived encrypted vault or native Keychain database. Same-origin injected JavaScript/device compromise is outside that protection.
- Atomic encrypted outbox/draft/record persistence with revision compare-and-swap. Web Locks coordinate sending across windows. Failure to persist never claims success. Encrypted message drafts survive browser restart.
- Private transaction ledger with unique account + operation ID. Lost acknowledgements can replay without repeating message receipts/notifications. Existing message safety and guardian delivery logic runs once. Attendance checks active membership at replay; event and attendance edits require the recorded server revision.
- Conflict review offers the server version or an explicitly resubmitted local version. Rejected work stays available for review. No automatic destructive last-writer-wins policy.
- Foreground reconnect/resume/manual sync with retry backoff. Auto-send requires the same signed-in account, an unlocked workspace in this browser session, and the app remaining unlocked. Closing the workspace with Back permits syncing; Lock pauses it. Force quit requires reopening/unlocking. No background-worker or iOS force-quit delivery claim.
- A conservative **pilot** seven-day download expiry, displayed in the UI. School-configurable lease policy is pending; the pilot duration is not presented as a school rule. Revoked access learned during download/replay locks the pack; pending work remains retained. Logout is blocked while pending work/drafts remain.
- Team refresh uses Download / update; automatic incoming delta refresh remains pending. Local acknowledgements immediately update the local records. Two-coach conflicts never overwrite silently.
- Verified in headless Chromium, including a separate browser-process restart with networking disabled, plus synthetic SQL transactions rolled back in Supabase. Physical iPhone/iPad and native wrapper verification remain required before claiming native offline support.

## Required architecture

1. A versioned local data layer: account/team/organization/season scoped records, revision, deleted/tombstone state, server cursor, last-sync time, snapshots and attachment manifests. Native protected database/files with keys in Keychain; browser IndexedDB plus storage persistence and quota handling. Do not blindly copy entire server responses across accounts or cache authenticated data in a shared service-worker cache.
2. App shell available offline: native bundled resources and a web service-worker cache limited to approved static assets. Self-host/pin dependencies currently loaded from CDNs. Do not force reload or activate an update while recording or while unsynced work exists. Keep a known-good asset version and local-schema rollback strategy.
3. Authorized initial snapshot: paginate every permitted entity, checkpoint progress and expose a truthful “Ready offline” status only after completeness checks. Download profile/team/season data, schedules, attendance, weights, goals, forms and signed document copies, permitted conversations, roster/board records and relevant media manifests. Each role receives its existing authorized subset, never the entire organization database by default. Previously unvisited authorized records must still be included, not merely whichever screen was opened.
4. Transactional outbox: commit a local change and its pending operation together before confirming “Saved on this device.” Store operation UUID, account, role context, entity ID, server revision, timestamp, payload, dependencies, attachment references and retry state. Never dequeue on a timeout; dequeue only after server acknowledgement stored locally. Preserve failed operations and show a recoverable reason.
5. Server sync contracts: idempotency keys with uniqueness and returned result, revision-based edits, authorization rechecked on EVERY replay, incremental cursors/tombstones and ordered processing. A wrapper that replays every old RPC is unsafe: many existing writes have non-idempotent side effects such as invitations, notifications or uploads.
6. Conflicts: append-only weights/messages/results use unique operation IDs; attendance and event/profile edits compare the version edited, keep both candidate values and request review on conflicts. Never silently overwrite two coaches' competing attendance marks, eligibility decisions or schedule changes. Rejected/changed permissions retain the local work for an authorized recovery path without executing the denied action.
7. Sync triggers: reconnect, foreground/resume, manual retry and supported native background tasks. Network presence is only a hint; authenticate and make a real request. Use bounded exponential backoff, one drainer per account/device, safe multi-window coordination and resumable uploads. iOS schedules background execution; promise catch-up on opening/resuming, not immediate delivery while force-quit.
8. Privacy/lifecycle: PIN/Face ID to unlock cached records; device protection/encryption; explicit account switching isolation; remote revocation applied at next contact. Define an offline access policy with the school rather than inventing one. On logout with pending work, offer sync/wait or an explicit protected retention decision; do not silently erase pending work. On lost access, lock cached content and preserve a safe recovery path. Test device loss, storage exhaustion and migration interruption.

## Feature behavior

| Area | Offline behavior | Reconnection requirement |
| --- | --- | --- |
| Locker Room, roster, profiles, goals | Read downloaded authorized records; local edits with clear pending status | Recheck permissions and revisions; reconcile edits |
| Schedule | View/create/edit locally, durations/arrival/repeats and saved venues | Commit series changes with preview/conflict protection; online map search |
| Attendance/eligibility | Record local marks and proposed dated restrictions | Server revision checks and conflict review; retain history |
| Messages/Whistle | Compose and queue; show Waiting to send, edit/cancel before submission | Server permission + SafeSport checks, required guardian visibility, then one message/notification |
| Messages with media | Save original attachments durably and stage upload | Resumable upload and idempotent final message; no orphaned or duplicate posts |
| Match Book/Mat Mode/scale/kiosk | Continue existing local/device capabilities and add durable pending records where missing | Reconcile results/weights; do not alter certification or peer-to-peer rules |
| Forms/signatures | Download forms; save local completion with accurate signed-on-device time | Validate current form/version and finalize receipt/audit on server |
| Board Room | Cached permitted records, local notes and drafts | Board votes/official approvals need explicit concurrency and eligibility rules; do not finalize a quorum result from disconnected devices |
| Invitations/accounts/billing | Prepare drafts where useful | First sign-in, account creation, permission grants, purchases and external delivery require online validation |
| Video/live | Record locally and view downloaded video | Upload/share/live delivery requires internet; visible size/space controls for video downloads |

Guardian safeguards are server authoritative at send time. Offline UI must never display “Sent” before acceptance. Queued messages must not bypass current membership, muted/blocked/guardian restrictions, minor/adult rules, monitoring or notification mirroring. Delayed-send time is distinct from offline queue time; decide what to do when its scheduled time passed before reconnect, with visible confirmation rather than surprising bulk sends.

## Delivery order and release gates

A. Implement and test the local store/outbox APIs and account isolation behind a disabled flag; add idempotent server sync endpoints and automated crash/retry/conflict tests.
B. Ship offline shell and verified data download/read mode, progress/space controls, last synced indicator and offline unlock; test a cold airplane-mode launch after force quit on a real iPhone/iPad.
C. Enable coach attendance, schedule and text-message writes individually after their server replay gates pass. Validate force quit before/after local commit, disconnect before/after server commit, token expiry and guardian-safe delivery. Add media and other modules through explicit adapters.
D. Extend every feature in the matrix; surface online-required operations honestly. Only describe the entire app as offline-ready after the module audit and device testing complete.

Acceptance scenarios: first download completeness; airplane-mode cold launch; multiple offline days; app/phone restart; storage full; same account on two recording devices; two coaches changing the same event; revoked permission during outage; expired tokens; app update while offline; repeated network flaps; a lost acknowledgement causing retry without duplicate message/notification; pending work after logout/account switch; attachment upload interruption; calendar timezone/DST; no exposure of another family/team's data; existing BLE/kiosk/video continues working.

## Schedule video requests

Reference recordings show location search/recent venues, start and separate meeting time, 1h/90m/custom duration and weekly repeat. v0.20.87 adds original duration presets (1h/90m/2h/custom) and saved/recent venue search to the existing form, retaining arrival/weigh-in and recurring-series controls. No reference artwork or code is reused. Geographic address autocomplete remains pending a supported maps integration; local venue search must not be described as live map results.

Technical references checked September 28, 2026:
- https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API
- https://developer.apple.com/documentation/backgroundtasks
- https://supabase.com/docs/guides/database/functions
