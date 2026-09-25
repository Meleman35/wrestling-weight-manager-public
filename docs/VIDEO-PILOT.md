# Video Pilot — private recording and synchronized replay

Prepared September 25, 2026. Draft branch `work/video-pilot-046` from published main `82e89ca2ec9cd3f28ed205e19ce3a9d28fb62eb4` (0.20.42).

## Delivery status

Implemented and browser-tested: allowlisted recording inside Match Book, camera preview with a scoreboard, same-device scoring, durable video segments, private device replay, seekable scoring events, interruption recovery, and original-video / JSON-timeline export.

**Unpublished.** The migration is not applied. The global pilot switch defaults to off and no team/user grants are seeded. No production data, paid entitlements, TestFlight setting, native project, subscription product, streaming account, email or push notification was changed. The application build label stays at the published baseline until deliberate integration/release.

The tournament-alert, paid-launch and organization-leadership branches are separate held drafts. This branch does not imply their inclusion. Merge them deliberately later; do not replace index.html from another branch wholesale.

## Tester workflow after activation

1. A personal coach account with an active team role and explicit unexpired pilot grant opens Clipboard → Practice & Competition → Match Book.
2. Choose/create a match. Use the existing Test scorebook for synthetic athlete names, or associate at least one active roster athlete for a real match.
3. Confirm filming permission, open the camera, then tap **Record privately**. Camera permission alone does not start recording.
4. Score through the existing Match Book controls. While recording, the camera and scoreboard remain visible above the scrolling scoring controls. The compact Start/Stop clock button forwards to the existing match-clock action.
5. Tap **Stop & save video**. A successful device-file write and a decoded video frame are required before showing a saved replay. This does not prove the entire match is present or every frame decodes.
6. Open the saved video from that match or the Match Book device-video list. Tap a scoring event to seek. Export the video and score JSON separately if a backup is needed.

Record privately never broadcasts or notifies anyone. Cloud upload and Go Live are unavailable. A saved match score in the existing cloud Match Book is separate from the device-only video.

## Capture, timing and recovery

- MediaRecorder captures one continuous take; every emitted segment is written and closed in Origin Private File System (OPFS). Video blobs are never stored in localStorage and an entire match is not held in a JavaScript chunks array.
- IndexedDB stores the recording manifest and an append-only snapshot timeline. The original scoring engine (`WMScoring`, `WMNFHS`, and the standalone Mat Mode page) is unchanged. Narrow hooks observe existing Match Book persistence and screen changes.
- Snapshots are timestamped relative to MediaRecorder's start event using `performance.now()`. Recorder timeslice counts and the paused wrestling clock never serve as the recording timebase. Scoring snapshots include period/phase, remaining match time, running state, and a copied ledger.
- Replay selects the latest snapshot at the player's current time, then advances its running clock only by the elapsed video time. Undo/corrections preserve earlier immutable snapshots; viewing before a correction still shows the original score. Camera-first-frame latency and audio/video drift still require measurement on physical devices.
- Final assembly streams committed files into an OPFS replay file; original segments are retained for recovery. This temporarily uses roughly twice the media size. No background upload or automatic deletion occurs.
- Initial free-space reserve is 256 MiB, ongoing low-space threshold is 64 MiB, queued-media ceiling is 32 MiB, and a take is limited to 20 minutes. These limits reduce risk and do not guarantee a particular match can fit.
- Backgrounding, media-track mute/end, leaving a match, expiry or changed account/team stops capture. A normal stop drains pending writes; a killed page or operating-system interruption may lose its final segment. Partial recovery assembles only committed segments and checks whether a frame decodes. Missing endings and unplayable segments are never labeled a complete saved recording.
- Browser persistence is requested where available, but the browser/OS can evict site data and clearing app data removes these files. Export is the independent backup. The browser implementation is not a native durable recording claim.
- The scoreboard is a **player overlay**. It is not burned into the exported original MP4/WebM. Native fullscreen video may omit HTML overlays; use the in-app player for synchronized scores.

## Access and offline behavior

`video_pilot_context` is a narrow public invoker RPC backed by a private function with a fixed empty search path and fresh authenticated-user checks. Raw grants and the global switch are private RLS-enabled tables with no client permissions. No grants can be created by a browser. Both explicit team/user grant and active staff membership are required; organization affiliation, family purchases, or local flags grant no server access.

The context returns a bounded in-memory lease, at most two hours and never beyond grant expiry, plus active roster IDs. No identity tokens or lease are persisted for offline reopening. Prepare the test by opening Match Book online. While this authorized page stays open, local recording/scoring/save/replay can work through loss of arena internet. After restart, reconnect to check access before opening recordings. The existing app has no new offline-shell installation mechanism in this change.

When online the page refreshes permission each minute. Removal/disable takes effect on the next successful check; an offline session can continue until its bounded lease expires. Device-local files are scoped to account and team. Access is enforced by the application UI, not encryption against someone with browser developer tools or filesystem access. This pilot has no cloud media read/write endpoints. Cloud access must receive separate server authorization before any upload/viewing feature is enabled.

## Verification performed

- Pure timeline checks: seeking before/after awards, clock pauses, immutable undo history, duplicate observations and periods.
- Eleven whole-page Chromium groups using **actual MediaRecorder, synthetic camera/microphone and real OPFS/IndexedDB**, with synthetic account/API fixtures: offline save, historical overlay seeking, restart playback, team separation, denied permissions, low storage, interrupted save, recovery, write failure, account separation and server denial.
- Six PGlite groups executing the actual migration against isolated synthetic tables: disabled default, exact grants/roster, wrong roles/teams, raw-table denial, anonymous denial, revoke/expiry/membership removal and two-hour cap.
- Existing eight login/onboarding and eight Clipboard/navigation groups pass.
- Source checks verify all unrelated inline scripts, shared scoring rules, standalone Mat Mode, app.js, styles.css and auth callback are preserved, and embedding is idempotent. All 41 inline scripts pass syntax checks.
- Screenshots inspected at phone width. No real athlete media or accounts were used.

This is **not** physical iPhone/iPad, WKWebView, TestFlight, APNs, cloud-upload or cross-network streaming verification. A synthetic camera establishes browser capture behavior, not arena reliability, battery use, thermal limits or camera quality.

Build: `python scripts/embed-video-pilot.py`. Tests: `node tests/video-pilot-core.cjs`, `node tests/video-pilot-browser.cjs`, `node tests/video-pilot-db.cjs`, `python tests/video-pilot-source.py`, `python tests/check-source.py`. Browser tests use installed Playwright and `CHROMIUM_EXECUTABLE_PATH`; database tests accept `PGLITE_MODULE`. See validation JSON and screenshots for evidence.

## Activation and next device gate

Before a real-team pilot, obtain Damon's exact team and tester accounts, then stage/apply only `20260925202706_video_pilot_access_02046.sql` through the normal reviewed database flow. Enable the switch and grant only those verified user/team IDs with a chosen expiry. No application UI administers grants yet. Disabling the switch or setting `revoked_at` closes subsequent server checks. Do not grant all teams or derive grants from organization affiliates.

The current Xcode project is on Damon's Mac and absent from this checkout. Obtain a ZIP of that project to inspect the actual WKWebView origin, bridge, camera/microphone usage descriptions, capture lifecycle, protected device-file storage, push entitlements and signed builds. Do not invent or replace those settings from an old project. The next gate is a physical iPhone/iPad test of start/stop, 10–20 minute capture, offline scoring, app switch/lock/interruption, restart recovery, storage pressure and export before approving real event footage.

## Live viewing and parent alerts: pending integration

Implement these only after capture/recovery is validated on the target devices:

- Select and configure a dedicated private streaming backend. Database/file storage alone is not a live-video service. No streaming plan was selected or purchased here.
- Separate **Go Live** from private recording. Server validates recorder, active team/roster and filming/guardian controls. Issue short-lived ingest credentials only to that recorder; never bundle provider secrets.
- Provider-confirmed playable video transitions a broadcast to Live. Persist a broadcast ID and a per-recipient delivery key. Enqueue one opted-in alert only for currently eligible linked guardians. A reconnect for that broadcast cannot enqueue duplicate alerts.
- Recheck permissions before short-lived playback authorization and again before notification delivery. A family entitlement never creates a child/guardian relationship or includes coach tools.
- Viewer timestamps must align the overlay to delayed video. Real-time score state cannot simply overlay a delayed stream. Provider timing support and any separate scoring-device pairing need their own verification.
- Expose accurate Live Now / Reconnecting / Ended / Replay processing states. Deep links target an exact broadcast, then its verified replay or accurate ended state. No prerecorded clip or local toast should be labeled a live stream or a tested push.
- Implement native APNs registration/background delivery with the actual Xcode project. Test separate broadcaster/viewer networks, closed-app notifications, revocation, reconnects and deduplication.
- Measure viewer-minutes, stored minutes, processing/egress, start delay, recording/upload failures and device battery/thermal behavior before finalizing Family Live pricing. The $49.99 family proposal remains provisional; purchases remain disabled.

Technical references consulted: [MediaRecorder data timing](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/dataavailable_event), [OPFS directory access](https://developer.mozilla.org/en-US/docs/Web/API/StorageManager/getDirectory), [Supabase row security](https://supabase.com/docs/guides/database/postgres/row-level-security), and [Supabase changelog](https://supabase.com/changelog). No provider behavior or native-device result is inferred from these references.
