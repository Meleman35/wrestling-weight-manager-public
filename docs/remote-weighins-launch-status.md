# Remote weigh-in launch status — October 4, 2026

Remote weigh-ins remain a development candidate in PR #60. No remote endpoint,
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

## Ready for physical testing

Open `native-device-check/RemoteScaleCheck.xcodeproj`, select the separate
RemoteScaleCheck scheme and run on the team iPad or iPhone. This app does not
replace Wrestling Manager. It numbers fictional adult test athletes in a continuous session, with no sign-in,
HTTP, upload, payment or saved photographs. Images clear on close/background.

Physical testing on October 4 confirmed a Build 3 automatic weight/photo capture
and a disconnect timeout. Build 4 failed to advance after one capture while the
screen showed 0.0 lb. Build 5 removes the extra shutter countdown, advances on
one fresh empty-scale response and retries camera presentation after dismissal.
It includes an iPad simulator regression for three captures inside the real
SwiftUI sheet, single-zero handoff, mixed-response rejection and retained setup.
Only camera hardware and BLE are simulated; physical acceptance remains pending.
The production host signals its coordinator for the next authorized scan only
after durable save and scale clear.

Check portrait/landscape framing; setup cancel/retake; immediate capture after
stable weight; stepping off before stability; disconnecting the scale; and
backgrounding during capture. Use an adult in appropriate athletic clothing.
No athlete pictures need to be sent back. This does not test production QR/NFC
resolution, authenticated server receipts or offline delivery.

## Remaining launch integration

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

The full app launch additionally retains the existing sandbox purchase/restore,
general deletion device acceptance, privacy inventory and Apple review gates.
Successful web publication and simulator compilation do not establish those.

References for the JPEG implementation and deployment constraints:
- https://github.com/jpeg-js/jpeg-js#decode-options
- https://supabase.com/docs/guides/functions/limits
