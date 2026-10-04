# Remote weekly weigh-ins — draft foundation

This branch adds an isolated capture state machine and director-report preview. It does not modify index.html, change ordinary kiosk behavior, deploy a backend, grant access or activate billing. Serve the repository locally and open previews/remote-weighins.html for fictional club/status filters and CSV export. Never provide real records to the preview.

## Capture contract

An authorized operator opens a server-issued program/window/club context with an account-session generation. QR/NFC resolution must return a canonical eligible athlete. A new scan clears all prior evidence. A settled reading must arrive after the scan; a camera photo follows that reading with notice acceptance. Manual weights, gallery/profile photos and stale callbacks are rejected. A new reading invalidates the previous photo. The freshness bound is at most 30 seconds; this is a draft product default to validate with hardware.

The submitted envelope binds operator, club, program, reporting window, athlete, reading, photo reference and capture ID. First delivery freezes the envelope and assigns a submission ID. Failed/unconfirmed delivery remains pending; retry reuses exactly that envelope. Only a matching server receipt marks it submitted. Disposing on account/team/session change removes in-memory content and rejects late callbacks. After a confirmed submission, discard/advance clears the capture before the next scan.

No durable offline queue exists here. An in-memory pending envelope is lost on reload. Production adapters must persist an encrypted account/club-scoped envelope and privately captured image before delivery, recover the same ID after restart, reconcile receipts, and dispose/revoke safely. They must not persist photos or sensitive records in ordinary localStorage.

## Director report

The server-authorized expected roster, not only submitted rows, determines missing athletes. Window instants are explicit with an IANA display timezone; no device-local week calculation. Captures fall in [opensAt, closesAt). Accepted receipts at/after closesAt are late. This definition must be explicit in configuration and UI; offline capture times remain untrusted until server validation. Network totals are independent of filtered rows. CSV exports filtered records and neutralizes leading formula characters.

Only one current submission is accepted per club/athlete/window. The reducer rejects conflicting current records. Corrections must be server-versioned with reason, actor, immutable prior record and explicit supersession; never silently choose the latest browser timestamp. Server-side revisions, idempotency constraints and late-sync policy are still required.

## Production integration still required

- Program and participating club enrollment; confirmed director/operator roles and canonical expected roster; explicit guardian notice/consent where required. Organization leadership alone does not expose all athlete weights.
- Paid coverage adapter: qualifying club/team or organization coverage must be verified server-side. Family Video never unlocks club administration; one team purchase does not cover a network. Organization/network pricing remains undecided. Preserve closed controls until the adapter exists.
- Private database tables/RLS, narrow authenticated APIs, live session checks, immutable idempotency receipts and transaction-safe concurrent submission/correction. Validate membership/athlete/period/evidence on every read/write; do not trust client context or timestamps.
- Private evidence storage with capture-session ownership, immutable photo digest/metadata, bounded upload, expiry and signed authorized reads. A client source:'camera' flag is not evidence of camera provenance. No image URLs/data are included in reports or CSV.
- Native scale and camera composition with front-camera positioning, preview, notice, retake and required-photo failure paths. Keep existing QR camera/scanner and ordinary kiosk behavior intact. A photo is a human review aid, never biometric verification or certified weight proof.
- Durable encrypted native outbox and upload recovery, account/club isolation, storage limits, same-receipt retry, and original capture versus server receipt timestamps.
- Decide photo retention/capacity independently of video budgets. Integrate all new records/evidence into the reviewed deletion catalog and athlete merge authority before deployment. Do not introduce schema that silently breaks deletion fingerprints.
- Physical scan → fresh settled reading → photo → offline/restart → upload acceptance; late/cross-club access, revoked membership/coverage, account switching and correction tests with synthetic fixtures.

## Validation

node --test tests/remote-weighins.mjs

Tests cover stale participants, camera callbacks, source restrictions, evidence expiry, exact retry envelopes, pending acknowledgments, account disposal, reporting boundaries, missing roster, program/club isolation, conflicts and formula-safe CSV. These are local contract tests, not production authorization/device acceptance.
