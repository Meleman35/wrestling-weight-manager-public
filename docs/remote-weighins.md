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


## Nationwide and tournament service contract

src/remote-weighins-service.mjs is a server-only dependency-injected service, not a deployed API. It requires trusted live-session, program, window, roster, evidence and transactional store adapters. It never accepts role/coverage assertions from the submission. Programs distinguish network and tournament; tournament windows/captures bind an explicit event ID and reports say Remote tournament check-in, never official certification. Each weekly/event roster is explicitly enrolled with remote consent.

Operators submit only for their assigned program/club. Directors read assigned programs; club readers query only their own club and do not receive network-wide totals. Report projection excludes photo/evidence references, operator/session IDs and arbitrary roster/medical columns. Pages are bounded to 500 rows; the 5,002-athlete synthetic test checks ordering/page boundaries and missing totals. The current adapter loads a complete authorized period to aggregate; production needs indexed, server-paginated roster/receipt queries, a bounded snapshot/revision cursor for exports, and capacity/load acceptance. This test is not a production performance result.

Capture evidence must come from an immutable private evidence service that verifies session/athlete/reading/photo provenance, consent and digest. The service contract rejects client-only camera flags as verification. No implemented evidence provider is supplied yet. New submissions are admitted only within a bounded explicit sync grace (maximum seven days); identical previously accepted retries return their original receipt after that deadline. Actual PostgreSQL atomicAccept must enforce this transactionally, recheck current access/session/coverage and prevent concurrent current captures. The test store is serialized in-memory only; no database concurrency acceptance is claimed.

22 isolated Node tests now cover both capture and reporting service contracts. Production activation remains blocked on the documented private adapters, durable outbox, retention/deletion compatibility and native/device acceptance. No pricing, customer scope or tournament rules are silently created.


## Isolated PostgreSQL storage draft

supabase/drafts/remote-weighins.sql defines seven private, RLS-enabled tables for programs, reporting windows, club enrollments, explicit assignments, expected roster/consent, private evidence metadata and immutable submissions/receipts. No anon/authenticated privileges, public RPC, server grants, storage bucket or production migration are created. A server-only invoker acceptance function locks the program and authorization rows, rechecks current Auth session/operator/coverage/consent, validates evidence binding and capture deadlines, returns exact prior receipts and rejects duplicate current captures using unique constraints. Receipts use server time. The program lock conservatively serializes submissions; production throughput and real multi-connection contention remain untested.

The isolated PGlite test executes actual SQL and verifies retry/conflict handling, expired/replaced sessions, revoked assignment/consent/coverage, sync deadline, evidence rejection, uniqueness, client privilege denial and all seven RLS flags. There are 22 service/capture tests plus the database executable. Synthetic fixtures never touch the production Supabase project.

This SQL is intentionally outside migrations: foreign-key ownership/deletion semantics, immutable correction history, real UUID team/athlete references, managed-account/native-lock checks, server grants/RLS policy, billing adapter and the reviewed deletion/merge catalogs still need integration against current production schema. No cascade or deletion retention promise is invented here. Private evidence metadata is not an implemented photo storage provider; bucket uploads, digest verification, signed access and purge reconciliation remain unfinished. Provisioning and production activation must not use this draft directly.


## Photo provider and encrypted queue implementation

src/remote-weighins-photos.mjs implements the Supabase private storage calls (upload with upsert:false, download, remove) behind a server-only provider. It checks bounded JPEG markers, computes SHA-256, reserves an immutable path/binding and recovers uncertain upload responses by downloading and hashing existing bytes. Read returns verified bytes only after authorization both before and after download, with no-store/private headers; it never exposes public or signed download URLs. Purge revokes metadata first, deletes the object and checks for a definite not-found response. Seven provider tests use a fake storage backend, not a live bucket. Full JPEG decoding and pixel/metadata normalization must run in a bounded trusted decoder before calling this provider; JPEG markers alone do not validate an image. Evidence persistence/authorization/native provenance adapters remain required; this module is not a deployed endpoint. It avoids long-lived signed-upload capabilities so revocation can be checked on each upload request.

src/remote-weighins-outbox.mjs implements AES-GCM encryption with random IVs and account/club/submission identity as authenticated data. It keeps the exact payload and photo until a confirmed receipt has been encrypted and persisted. Five tests use a real temporary disk adapter to verify a new queue instance recovers encrypted captures, failed deliveries remain pending, account/club isolation, conflicting retries, wrong keys, bounds and lock interruption. Keys are nonextractable during the test; no native Keychain provisioning or IndexedDB store is installed. A native production adapter must persist protected keys and atomic ciphertext files, serialize access across instances/devices, and recover transactions safely. The test disk adapter is not atomic or native protected storage. Module operations serialize one instance only; cross-instance locking/atomic create and crash-at-write acceptance remain required.

These modules expand the suite to 34 contract/provider/queue tests plus the SQL executable. Live schema was read only on October 3 to establish actual team/athlete UUID and deletion-catalog structures; no real records were read or mutated. Native wrapper source must be recovered and preserved before adding Keychain, camera and scale composition; do not replace the existing native app with these modules.


## iOS queue candidate

native-candidate/WrestlingManagerRemoteOutbox.swift implements an actor-scoped CryptoKit AES-GCM store with account/club/submission authenticated identity, WhenUnlockedThisDeviceOnly Keychain keys, complete file protection, backup exclusion and atomic ciphertext writes. It refuses to regenerate a missing key over existing captures; corrupt records fail visibly. Confirmed receipts are persisted before a capture can be removed. SDK typechecking is in CI; physical lock/unlock, force-quit, write interruption, Keychain access, low-storage and deletion acceptance are still required. Host must use one instance per account/club, call lock on session/role/app-lock changes, validate authorized native context before/after async delivery, and never expose raw queue methods to arbitrary web origins. No WKWebView bridge/camera composition is installed by this candidate.

The recovered October 3 purchase-host package supplies the ContentView baseline but is not the complete current Xcode project and omits later billing Authentication/PageSession components. Full wrapper composition must reconcile those additions and the installed scale/NFC/deletion/video code; do not install that older package as a replacement. Current full Xcode source is needed for that integration.

### Native capture integration (October 3 source upload)

The user supplied the build 1.0 (8) Xcode project settings, the separate 36-file
app source folder, AmericanScaleKit sources, StoreKit configuration and
verification package. The uploaded ContentView includes the established scanner,
NFC, security, video and deletion hooks; it does not yet register the later
purchase-authentication/page-session candidates. Preserve this source when
assembling the next native build; do not substitute the earlier partial purchase
host package. These private uploads are not copied into the public repository.

New native candidates:
- `WrestlingManagerRemoteCapture.swift`: native scan-bound evidence state, bounded
  stable BLE sample run, movement/disconnect invalidation, 30-second freshness,
  photo notice, immutable envelope matching the service contract.
- `WrestlingManagerRemotePhoto.swift`: camera-only AVFoundation presenter; exposure-time timestamps; front camera
  preference; decode/render/re-encode to strip original metadata, orient correctly
  and cap dimensions at 1280 pixels. No photo-library selection.
- `WrestlingManagerRemoteCaptureHost.swift`: joins the state, camera and protected
  outbox behind an injected live authorization check; background cancellation;
  checks authorization again before queueing. Queue success is not acceptance.

These are integration components, not registered production web handlers. The
host needs authoritative personal-session/club/window activation, roster-resolved
QR/NFC routing, actual packet receipt callbacks (not cached UI weight changes),
lock/navigation/deletion hooks, retry UI and upload transport. The stable-sample
rule is a capture aid, not scale calibration or official event certification.
Physical iPad testing remains necessary for camera permissions/rotation, sample
cadence and stability, protected storage, cancellation and reconnect behavior.

`prepare-native-remote-scale.py` was exercised against a local copy of the
uploaded source. It installs the four dormant components and adds an optional
`onRemoteWeightPacket(Double, Date)` callback at parsed BLE receipt, including
unchanged repeated weights. Stale-peripheral callbacks are excluded. The
installer validates exact source anchors before writing, preserves the original
scale file in a backup and rolls back on write failure. No original uploaded ZIP
is overwritten. The app must connect that callback to the active host, forward
connection loss to `scaleDisconnected()`, and clear it on host closure.

The host blocks rescans/discards during durable writes, avoiding a discarded
attempt racing a completed save. Local save failures expose `retrySave()` without
regenerating submission IDs or evidence. Full uploaded-app Xcode building is
separate from the candidate SDK typecheck; the supplied pieces do not include the
project's referenced root `Wrestling-Manager-Info.plist`.


### Native queue delivery

`WrestlingManagerRemoteDelivery.swift` joins an injected authenticated transport to
`WrestlingManagerRemoteDeliveryStore.swift` and the protected outbox. It validates
photo acknowledgement identity/size and exact SHA256 digest before submit, validates server
receipt identity/time/status, and persists the receipt before returning success.
The worker checks live authorization between stages, excludes concurrent delivery,
and blocks late callbacks after locking. Retried delivery uses unchanged payload
and image data. Ambiguous acceptance and disk errors retain both; the server's
idempotent accept operation must return the original receipt. A previously stored
receipt also requires current authority before returning to the UI. Upload/read
HTTP endpoints and current-session transport wiring remain to be implemented.

Native delivery tests use an actor-backed fixture to exercise failed submit,
failed receipt persistence, wrong evidence/receipt, exact retry bytes and revoked
access. They do not exercise actual network endpoints or device Keychain.


### HTTP service composition

`remote-weighins-http.mjs` provides bounded authenticated POST handlers for photo
upload, submission, report and private photo reads. Photo requests carry a capture
payload and canonical base64 JPEG; photo binding is allowlisted from that payload.
Trusted authentication and explicit rate-limit allowance run before body parsing.
Limits apply to actual streamed bytes, not just Content-Length. Foreign browser
origins are denied; configured app origins receive narrow CORS. Responses are
no-store and internal provider exceptions are not returned to clients. Missing
production auth/storage/database/rate-limit adapters are not replaced with mocks.
This composition is not a deployed Supabase function.


`WrestlingManagerRemoteHTTP.swift` now supplies the native delivery transport for
that route contract: fixed project HTTPS endpoint, ephemeral no-cookie/no-cache
URLSession, redirect rejection, personal account/session/generation checks before
and after every request, authenticated authorization/photo/submit requests and
bounded JSON response validation. `authorizeCapture` is an obligatory trusted
handler dependency; an explicit true result is required. This does not provision
that endpoint or infer billing/roster/native provenance from client fields.
Session provider wiring must reuse the current auth coordinator rather than a
page-supplied token; close the client with the capture/delivery host on logout,
lock and page change. Response size is checked after URLSession download; this is
not yet a streaming response size cap. Real HTTP and full app tests remain.


`WrestlingManagerRemoteReportingSession.swift` is the native composition owner: one
protected outbox is shared by camera capture and HTTP delivery. The owner verifies
scope vs personal session, installs one delivery worker despite async reentrancy,
closes camera and transport on background, and exposes `close()` for app
lock/logout/navigation/club-change/deletion hooks. It also closes owned resources
when released. `authorizeActivation` must enforce current program/window/club and
operator coverage at activation, not merely return a client-side flag. Current
wrapper registration and real production adapters still remain.


### Database and in-app reporting composition

`remote-weighins-postgres.mjs` now supplies real parameterized query adapters for
the draft schema: verified Auth session/assignments, active coverage/windows,
consented roster, evidence, atomic SQL receipt acceptance and scoped reports.
The trusted personal-session verifier and canonical roster-name resolver are
mandatory production dependencies. PGlite integration runs this adapter and the
reporting service together, including exact receipt retry and revoked access.
The read path still uses whole scoped roster/submission arrays; indexed SQL
pagination and consistent report snapshots are not implemented yet.

The reporting service provides an authorized context of granted programs/clubs
and windows. Photo reads resolve a submission to evidence only on the server,
checking program read authority and current athlete consent; evidence IDs stay
out of report responses.

`remote-weighins-screen.mjs` and `remote-weighins-app.mjs` add the real component
and browser HTTP adapter for the in-app More screen: program/club and window
selection, status filter, pagination, accepted totals, capture/receipt timezones
and private photo review. Text uses DOM textContent; photos use revocable local
blob URLs. The app adapter closes on visibility/account/lock changes, rejects
managed accounts and stale callbacks, and enables native capture only when an
actual host activation adapter is supplied.

`prepare-remote-reporting-screen.py` was exercised on a copy of the repository's
index.html. It adds the More entry and sheet, explicit close/auth/lock hooks and
module registration behind an `enabled:false` deployment gate. It validates
source anchors and backs up the input. Production index is not changed by this
PR; flip the gate only together with the reviewed production backend deployment.
This integration script needs current main source when applied, preserving other
work. Browser CI tests use fictional scoped responses, not real accounts.


Receipt recovery is now an explicit authenticated route: compare the exact frozen
capture fields to the accepted database record and require the current operator,
program/club/window and athlete consent before returning its receipt. Native
delivery checks this route before photo upload, allowing a lost acceptance reply
to recover without needing the verification image again. Receipt times are
normalized to the same UTC millisecond representation in accept and lookup
responses. This intentionally projects PostgreSQL's finer timestamp precision;
the original full precision remains stored in the database. Native recovery tests
confirm this path does not upload or resubmit an already accepted capture.
