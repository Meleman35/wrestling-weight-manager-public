# Remote weigh-in launch status — October 4, 2026

**Later update, not a version 1.0 launch requirement.** Damon approved launching the core app first on October 4 at 8:14 PM Mountain. Preserve all work below for that update. The first-release bootstrap does not register the remote reporting client and removes its entry/screen; ordinary team scale/NFC use remains in scope. Remote director billing/trials, hosted evidence/retention, nationwide capacity and vendor-import acceptance are deferred together. This decision does not enable or price any unfinished remote service.

The combined launch candidate is now in PR #62 (`codex/launch-integration-20261004`), incorporating the earlier PR #60 remote work. No remote endpoint,
private bucket, scheduled purge or paid director product was activated overnight.
The existing Wrestling Manager app stays usable. Team athlete card PDF export
was separately published in web version 0.20.121 through PR #61.

## Implemented and checked

- Camera setup with full-frame confirmation, singlet/face/feet/scale guidance,
  memory-only test pictures and an automatic shutter immediately after stable weight.
  Movement, a stale BLE packet or the closing deadline resets readiness.
- Locked original capture fields; protected native retry/outbox components;
  240-hour expiry; explicit late receipt handling and downloaded-copy warnings.
- Club reports with canonical names, USAW/AAU IDs, private photo review, CSV and
  photo-embedded Excel. Portrait pictures retain their aspect ratio.
- One-statement database pagination and full report revisions. Tests exercise
  3,200 athletes across 32 clubs and abort exports after same-count data changes.
- Browser transport with bounded bodies, fixed endpoint, current-session checks,
  timeout and cancellation on close.
- Required server JPEG normalization before any evidence reservation or upload:
  complete decoding, dimensions at most 1280 by 1280, five-MiB input/output caps,
  approximate 48-MiB decoder allocation limit, strict decoding, and fresh encoding
  from pixels only. EXIF and comments are not copied. Provider and PostgreSQL/HTTP
  tests now use actual JPEG images, including rejection of marker-only junk.
- Eighty-five Node/PGlite tests pass locally. Prior native validation includes
  Apple SDK release/DEBUG typechecking, capture/delivery/retention executables,
  American Scale protocol tests and the full unsigned simulator build. Consult
  the current PR checks for the final combined branch result.

The JPEG normalizer takes the pinned `jpeg-js` 0.4.4 codec. Production composition
must inject `createRemoteJPEGNormalizer({codec})` into `createRemotePhotoProvider`;
the provider refuses to construct without it. Decode runs after authorization.
Storage hashes cover normalized bytes; original encrypted capture bytes remain
unchanged for retries. Keep codec and quality fixed for pending captures. A future
codec change requires an explicit retry compatibility plan, not silent replacement.
Pixel processing does not establish identity, clothing, scale or capture-time
authenticity. Those still require trusted provenance and authorized human review.

## Device testing and main-app integration

The owner confirmed the isolated Build 7 scan → step on → weight/photo → step off
flow on October 4. Do not request another isolated scale test. Its tested scale
package is copied into the original main app under `native-app/`, retaining the
original bundle ID, signing team and app features. The combined app is version
1.0 (9). Full Debug and Release simulator builds have passed.

The production capture host now opens the camera immediately after one authorized
scan and waits for stable BLE evidence with the camera already ready. Durable
queue completion and fresh scale-clear advance the session without another setup.
The automated production-host test also exercises real encrypted queue storage
and personal-account cleanup. Check PR #62's current result before handing over;
compilation alone does not establish the test result.

Account deletion now inventories queued remote photos/weights during local
preflight, removes only the deleted account's files after verified server
completion, and prevents stale queue instances from writing them back. This does
not deploy the server-side remote deletion/retention integration.

The core release's single physical acceptance round is in
`docs/launch-acceptance-batch.md`; remote-specific acceptance follows below for the later update. The main app still loads the live website;
a local build does not deploy the candidate site or remote endpoint. Reporting
remains hidden until authorized live capture and receipt integration is ready.

## Remaining integration for the later remote update

1. Wire the production app coordinator to live scope/consent and QR/NFC resolution,
   its scale connection, camera setup/recheck, protected queue and reporting UI.
   Preserve the existing working native project and signing configuration.
2. Implement trusted capture provenance and clock validation, transaction-time
   team/director coverage, canonical program/event provisioning and profile editing.
   Complete verified Apple billing composition using the existing product setup.
3. Review new records against the real deletion/merge catalogs and ownership rules;
   install private grants, storage, authenticated routes and retention/reconciliation
   workers. Do not bypass schema drift guards or broaden access to make tests pass.
4. Complete hosted rate limits and capacity/concurrency acceptance, including JPEG
   runtime cost under the deployed platform's limits. Local tests are not a hosted
   performance result. Neither the decoder limit nor a timer preempts synchronous
   CPU work; production must enforce admission and platform resource budgets.
5. Complete real-device offline/restart/two-club tests, Save to Files and printer
   acceptance, and actual-weight import acceptance in Trackwrestling/USA Bracketing.
   Vendor-specific automatic weight updates remain disabled.

Core launch retains sandbox purchase/restore, general deletion device acceptance,
privacy inventory and Apple review gates. Remote work does not block that release.
Successful web publication and simulator compilation do not establish acceptance.

## Later-update device acceptance

After the remote prerequisites above pass, use fictional athletes and an adult in appropriate athletic clothing. Check scan → step on → automatic weight/photo → step off → next scan; permitted lighter/heavier reweighs; movement/disconnect/window close; locked original timestamps; interrupted upload/restart with the same receipt; two-club director access; CSV/photo-workbook Save to Files and real vendor import; exact 240-hour expiry and saved-copy warning; remote evidence cleanup after disposable account deletion. Do not ask the owner to repeat the already-passed isolated scale test while live remote integration is incomplete.

References for the JPEG implementation and deployment constraints:
- https://github.com/jpeg-js/jpeg-js#decode-options
- https://supabase.com/docs/guides/functions/limits

Build 6 adds the existing Bluetooth NFC reader to the isolated test, fresh-card
removal gating, and per-card lower-weight selection. Private draft tournament
windows may explicitly allow repeats; server reports select one lowest valid
attempt with its matching photo/timestamps. The window setting locks at
activation. Production credential resolution, hosted acceptance and director
window provisioning still need the previously listed integration work.
