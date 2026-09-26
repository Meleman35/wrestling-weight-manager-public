# Current draft: athlete recording and private sharing

Updated September 25, 2026. The sections below describe the earlier recording-only pilot; this section supersedes their statements that cloud-upload code is absent. Production remains unchanged and all new database work is unapplied.

The current draft adds athlete-profile **Score & record match**, coach-confirmed event rules, exact event/athlete assignments, linked-parent recording/sharing permission, server-imported bout/opponent identity, private Storage upload records/policies, browser and native foreground TUS upload queues, verified-upload device removal, and athlete/family watch/download. Go live remains disabled because provider ingestion, live playback authorization, and parent live-alert integration are unfinished. A device-recording dot is explicitly labeled not live.

Validation: nine PGlite authorization/storage groups, seven upload protocol/resume groups, nine native-adapter browser groups (including one-click assigned-teammate capture), shared scoring/source preservation and JavaScript syntax. These are synthetic fixtures. Native upload Swift passes grammar parsing only; it has not been compiled in Xcode or exercised against real Supabase Storage.

See [TestFlight services, costs and acceptance gates](TESTFLIGHT-SERVICES-2026-09-25.md) for the complete current rollout state, service inventory, external dependencies and required hardware tests. Original device files are not automatically deleted. Family removal revokes shared access; physical object purge remains pending implementation. Initial bout preparation requires a connection; an already-authorized open recording can continue through temporary service loss.

---

# Video Pilot — private recording and synchronized replay

Prepared September 25, 2026. Draft branch `work/video-pilot-046` from published main `82e89ca2ec9cd3f28ed205e19ce3a9d28fb62eb4` (0.20.42).

## Delivery status

Implemented and browser-tested: allowlisted recording inside Match Book, camera preview with a scoreboard, same-device scoring, durable video segments, private device replay, seekable scoring events, interruption recovery, and original-video / JSON-timeline export.

**Unpublished.** The migration is not applied. The global pilot switch defaults to off and no team/user grants are seeded. No production data, paid entitlements, TestFlight setting, published native build, subscription product, streaming account, email or push notification was changed. The application build label stays at the published baseline until deliberate integration/release.

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

## Native iPhone/iPad adapter (draft; no device results yet)

`src/video-pilot-native.js` selects the `wmVideoPilot` bridge when present; the browser recorder is then inactive. The same Match Book hooks and ledger snapshots drive capture and replay. Native commands include authorization, preview, start, snapshot, stop, list, recovery, replay and delete. Movies never cross the JavaScript bridge.

The separately delivered Swift draft uses a serial AVFoundation capture queue with `AVCaptureMovieFileOutput`, 720p H.264 where available, two-second movie fragments and a 20-minute take limit. Original `.mov` files and atomic JSON histories live in protected Application Support storage, excluded from automatic backup. Initial available-space reserve is 512 MiB; the capture output stops at 256 MiB free. A crash can lose the last fragment or leave unplayable footage. Recovery only claims a partial recording after asset loading and a frame-decode check. A normal stop also verifies playback before reporting a saved copy. Export original video and JSON from the native replay; the scoreboard is not embedded in the movie.

Native snapshot timestamps come from `recordedDuration`, not the wrestling clock. Native replay uses historical ledger totals and elapsed video time for the display. Tapping an event seeks a few milliseconds past its timestamp to avoid media-timescale rounding selecting the previous snapshot. The browser event seek also has a one-millisecond rounding allowance. Rules and scoring actions remain in the existing scorer.

The Swift bridge checks the trusted main-frame app origin and obtains its own allowlist lease from the fixed Supabase RPC. The access token is used only in an ephemeral, non-caching request; redirects are refused. It validates the returned account, team, active-roster IDs and expiry. Main-page navigation, account/team changes, app backgrounding, camera interruption, lease expiry, a missing scoring-screen heartbeat and critical thermal state stop capture. Permission descriptions include camera recording and microphone use. Existing NFC, scale, security and APNs bridges/entitlements are preserved; credential scanning is blocked while video owns the camera.

The camera preview is a native view aligned with the web preview rectangle. Rotation, keyboard/sheet overlap, preview positioning, thermal behavior, audio sessions, interruption finalization and recovery require physical iPhone/iPad tests. Capture orientation is chosen when opening the camera; keep that orientation for the take.

Eight whole-page native-adapter fixture groups pass: permission gating/error UI, forwarding the existing scoring/undo history, preview layout, offline stop routing, replay routing, failed-save/recovery labels, team changes, access denial and stale authorization responses. This is a **synthetic message bridge**, not evidence that Swift compiles or AVFoundation records. Four added Swift files pass a portable grammar parse only. No signing, TestFlight upload, database activation, native camera, filesystem recovery or native player execution was performed here.

## Access and offline behavior

`video_pilot_context` is a narrow public invoker RPC backed by a private function with a fixed empty search path and fresh authenticated-user checks. Raw grants and the global switch are private RLS-enabled tables with no client permissions. No grants can be created by a browser. Both explicit team/user grant and active staff membership are required; organization affiliation, family purchases, or local flags grant no server access.

The context returns a bounded in-memory lease, at most two hours and never beyond grant expiry, plus active roster IDs. No identity tokens or lease are persisted for offline reopening. Prepare the test by opening Match Book online. While this authorized page stays open, local recording/scoring/save/replay can work through loss of arena internet. After restart, reconnect to check access before opening recordings. The existing app has no new offline-shell installation mechanism in this change.

When online the page refreshes permission each minute. Removal/disable takes effect on the next successful check; an offline session can continue until its bounded lease expires. Device-local files are scoped to account and team. Access is enforced by the application UI, not encryption against someone with browser developer tools or filesystem access. This pilot has no cloud media read/write endpoints. Cloud access must receive separate server authorization before any upload/viewing feature is enabled.

## Verification performed

- Pure timeline checks: seeking before/after awards, clock pauses, immutable undo history, duplicate observations and periods.
- Eleven whole-page Chromium groups using **actual MediaRecorder, synthetic camera/microphone and real OPFS/IndexedDB**, with synthetic account/API fixtures: offline save, historical overlay seeking, restart playback, team separation, denied permissions, low storage, interrupted save, recovery, write failure, account separation and server denial.
- Six PGlite groups executing the actual migration against isolated synthetic tables: disabled default, exact grants/roster, wrong roles/teams, raw-table denial, anonymous denial, revoke/expiry/membership removal and two-hour cap.
- Existing eight login/onboarding and eight Clipboard/navigation groups pass.
- Source checks verify all unrelated inline scripts, shared scoring rules, standalone Mat Mode, app.js, styles.css and auth callback are preserved, and embedding is idempotent. All 42 inline scripts pass syntax checks.
- Screenshots inspected at phone width. No real athlete media or accounts were used.

This is **not** physical iPhone/iPad, WKWebView, TestFlight, APNs, cloud-upload or cross-network streaming verification. A synthetic camera establishes browser capture behavior, not arena reliability, battery use, thermal limits or camera quality.

Build: `python scripts/embed-video-pilot.py`. Tests: `node tests/video-pilot-core.cjs`, `node tests/video-pilot-browser.cjs`, `node tests/video-pilot-native-browser.cjs`, `node tests/video-pilot-db.cjs`, `python tests/video-pilot-source.py`, `python tests/check-source.py`. Browser tests use installed Playwright and `CHROMIUM_EXECUTABLE_PATH`; database tests accept `PGLITE_MODULE`. See validation JSON and screenshots for evidence.

## Activation and next device gate

Before a real-team pilot, obtain Damon's exact team and tester accounts, then stage/apply only `20260925202706_video_pilot_access_02046.sql` through the normal reviewed database flow. Enable the switch and grant only those verified user/team IDs with a chosen expiry. No application UI administers grants yet. Disabling the switch or setting `revoked_at` closes subsequent server checks. Do not grant all teams or derive grants from organization affiliates.

The uploaded Xcode source has now been inspected and a separate native draft ZIP prepared. The later-uploaded `WrestlingManagerNative` / `AmericanScaleKit` package is included unchanged, and its project reference now uses the package beside the project instead of the original Desktop path. The native draft has not been compiled in Xcode or tested on an iPhone/iPad. Its source is delivered separately; it is not published into this public web repository. The production web page still lacks this draft's hooks, so installing the native source alone does not activate recording. The next gate is a physical iPhone/iPad test of start/stop, 10–20 minute capture, offline scoring, app switch/lock/interruption, restart recovery, storage pressure and export before approving real event footage.

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
