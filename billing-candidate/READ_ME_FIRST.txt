Current combined candidate — October 4, 2026

PR #62: https://github.com/Meleman35/wrestling-weight-manager-public/pull/62
This includes the original main native app in native-app/, Plans & purchases,
server-verified native activation, canonical family selection, notification/runtime
composition, and billing/deletion actor locks. Full main-app Debug/Release builds
and the billing database/browser/native checks have passed on integration checkpoints.
Consult current PR checks for the latest exact commit. The Apple key is configured
privately in Render; Supabase's verifier authentication and restricted database
connection passed live checks. Server deployment, retention/reconciliation and
athlete-merge compatibility remain outstanding. The complete deletion worker now
has seven synthetic billing integration scenarios; no billing data schema is live.
Payments are not enabled. See docs/launch-acceptance-batch.md for the one combined
acceptance round after those prerequisites are ready.

The notes below are historical component checkpoints, not the current integration
status. Earlier "not wired" statements may be superseded by PR #62; deployment and
physical sandbox results must never be inferred from component checks.

Wrestling Manager billing candidate — October 3, 2026

STATUS: Prepared integration code. Payments are not enabled.
Draft PR: https://github.com/Meleman35/wrestling-weight-manager-public/pull/57
Do not replace the working Xcode project or submit a build from these files alone.

Implemented
- Four Team Pro / Family Video monthly and annual products.
- Team Pro binding to one team per Apple purchaser for initial launch; restores
  preserve the original team. Owned unpaid reservations can be cancelled.
- Personal Family Video scope, up to two linked athlete profiles across teams.
  Any separately authorized filming device may record a covered athlete.
  Family coverage does not grant Team Pro to the whole team.
- Supabase authentication and transactional session/user checks.
- PostgreSQL transaction locks, unique ownership, immutable scope, durable
  acknowledgement and rollback. Private draft schema with RLS and restricted grants.
- Apple signature verification and canonical subscription status adapter using
  the pinned official library. Refund, expiry and grace policy checks.
- Disabled-by-default Fetch route for prepare, deliver, abandon, access and coverage.
- Native StoreKit purchase, restore, unfinished recovery and updates listener.
- Native HTTP adapter with public gateway key, authenticated requests, strict
  acknowledgements, blocked redirects and immutable account/session generation.
  Logout stops the adapter; a stopped instance cannot be reused.

Verification
- Latest isolated CI: 108 backend checks passed, none skipped, including disposable
  PostgreSQL concurrency, rollback, cancelled reservation and role-access checks.
- Apple SDK type checking passed for all three candidate Swift files.
- Native HTTP executable checks passed for scope, authentication, strict response
  handling, account changes and logout.
- These are not valid Apple receipt tests, full-project Xcode builds or device
  sandbox tests. No live billing database, endpoint or paid entitlement deployed.

Integration order and remaining work
1. Resolve account deletion / financial retention behavior and coordinate billing
   transactions with deletion freeze and the deletion catalog. Do not activate the
   draft schema before this is complete.
2. Generate a migration through the existing Supabase workflow. Provision a private
   backend identity with only the intended wm_billing_runtime grants; validate
   production runtime compatibility for PostgreSQL and the Apple library.
3. Configure server-only Apple credentials and official trust roots. The private
   .p8 stays out of GitHub, the web app, native app, screenshots and chat.
4. Connect the implemented family selection and access APIs to the native/web
   host. Preserve the video pilot gate until a separate paid-video rollout is ready.
5. Wire verified notifications and scheduled reconciliation so refunds, expirations
   and renewals update access even when the purchasing device is offline.
6. Integrate the candidate Swift files into the working native project. Add an
   origin-checked, main-frame-only web bridge and authenticated session lifecycle.
   Plan screens must use Apple product metadata and server-authoritative access.
7. Run full Xcode compilation, local StoreKit and device sandbox checks: purchase,
   cancellation, pending approval, restart/network recovery, restore, account
   switch/logout, monthly/annual changes, refund and expiry.
8. Paid Apps Agreement, bank account and U.S. W-9 confirmed Active from owner screenshots October 3, 2026. Digital Services Act remains In Review. Complete remaining review metadata.
   Submit first subscriptions with the app version and subscription group.

Known product limits
- Third-athlete and athletes 4–8 discounts are requested but prices and additional
  products are undecided. They are not active in this candidate.
- Live streaming, hosted image/video limits and SMS service are not ready for sale
  as unlimited benefits. Final plan text must describe actual available coverage.
- Do not infer a paid flag from purchase success, local receipts or an HTTP ack.
  Refresh access from the authoritative server after delivery.

Configuration inventory (public identifiers only)
Apple In-App Purchase key ID: 79R244P822
Apple issuer ID: b5931be7-ac93-4ab3-9b1a-15e1dd26a549
Private signing key: configured directly by the owner in the Render verifier.
Apple numeric app ID: 6815511370 confirmed from App Store Connect screenshot October 3, 2026.
Bundle ID: com.damonmele.wrestlingmanager confirmed from both configurations
of the uploaded working Xcode project. The same value is confirmed in App Store Connect.
Endpoint reserved in native code:
https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-billing
This endpoint has not been deployed. Publishable gateway key is public app
configuration; service-role credentials and Apple private keys are server only.

Product catalog
com.damonmele.wrestlingmanager.teampro.annual — $269.99/year
com.damonmele.wrestlingmanager.teampro.monthly — $75/month
com.damonmele.wrestlingmanager.familyvideo.annual — $75/year
com.damonmele.wrestlingmanager.familyvideo.monthly — $10/month
Actual localized purchase prices must come from StoreKit, not this checklist.

Local checks
npm ci --ignore-scripts
npm test
Real database checks require BILLING_TEST_DATABASE_URL pointing to the disposable
localhost billing_test database. Never point that suite at live project data.

Working web UI release 0.20.120 and installed native build 1.0 (8) remain the
baseline. This candidate is a separate draft, not a replacement release.

Subscription presentation candidate added:
- Localized StoreKit prices only; no invented price fallback.
- Team selection required, family target has no team, restore cannot rebind.
- Streaming, storage, SMS and extra-athlete availability explained explicitly.
- Purchase readiness disabled by default. This model does not grant access.
- Four presentation checks passed; web/native rendering integration remains.

Reusable subscription screen candidate added:
- Monthly/annual choices and Restore Purchases use injected native callbacks.
- No receipt, credentials or paid access stored in the component.
- Requests disable controls; disposed screens ignore late responses.
- Text rendered through textContent; syntax check passed, visual QA pending.
- Board Room video meetings belong to a future organization plan, not Team Pro.

Subscription browser QA passed:
- Responsive widths 320/390/768/1100, price text escaping, family target, restore,
  pending approval, busy controls and disposed account response isolation.
- Styling and screenshot artifact are included in the draft CI.

Native WebKit bridge candidate added:
- Disabled by default; no web command can enable it or supply credentials.
- Exact main-frame origin and current native session required for every request.
- Bounded strict commands for products/purchase/restore/recovery.
- Host must register wmPurchases as a reply handler, attach the same web view,
  start the store updates listener after sign-in and invoke stop on logout,
  account change, page navigation or native dismantling.
- Native host session construction and full-project/device testing remain.

Native purchase client added:
- Reply-handler client for products, purchase, restore and recovery.
- Immutable session generation, irreversible stop and concurrent request guard.
- Strict native metadata/outcome validation; no credentials or paid flag accepted.
- Six lifecycle/response checks passed. Host must wire current session generation
  and stop both client/screen and native store/transport on logout or navigation.
- Apple SDK compilation of native bridge and browser screen QA both passed.

Subscription controller composition added October 3:
- Loads validated native product metadata and mounts the existing screen.
- Requests authoritative access refresh after delivered purchase/restore/recovery.
- Supplies a session invalidation guard; the host must check it before committing
  any async access response. Disposal stops the client and removes the screen.
- Purchase readiness still defaults off. Full native host and backend deployment
  remain required; this does not enable purchases in the installed app.
- Four controller lifecycle checks plus ten client/presentation checks passed.

Server access service candidate added:
- Uses current actor and server-resolved team/athlete/filming permissions.
- Evaluates verified subscription snapshots with existing expiry/refund policy.
- Returns only requested team/athlete flags and check time; no purchaser data.
- Five service authorization checks pass.
- PostgreSQL accessTransaction and resolveAccess are now implemented (see below).
  No access endpoint has been deployed or client grant enabled.

Database access and family selection connected October 3:
- Load billing-storage-candidate.sql, then billing-access-candidate.sql only into
  a disposable database; production deletion/retention integration still blocks
  deploying either draft. Existing deletion schema fingerprints must be updated
  through that workflow before any production schema change.
- POST action access accepts teamID, optional athleteID and eventID (an event
  requires an athlete). Family Video recording access requires all three IDs.
  It returns teamID, athleteID, eventID, teamPro, familyVideo and checkedAt only.
- Database resolves athlete.profile_id and selected coverage profiles. Accepted
  guardian relationships and active membership on the requested team are required.
- Existing video_can_record is reused, including event permission, consent,
  active roster, pilot/test gates and recorder restrictions. A subscription does
  not turn on a non-pilot team. Personal accounts only on this access endpoint;
  managed-device access still requires separate host/endpoint integration.
- Permission and subscription state are read in one SQL statement. Access and
  coverage transactions share the actor lock used by scoped_deletion_begin;
  live user/session row locks remain held through transaction completion.
  Target team/organization deletion and owner deletion suppress coverage.
- POST action coverage accepts athleteIDs (0–2 roster IDs). Server resolves the
  owner and canonical profiles, rejects duplicate profiles/unaccepted links,
  replaces slots atomically and returns selectedCount. Clearing is supported.
  Selecting athletes alone grants no paid access. Additional discounts are not
  implemented. Selection UI and server endpoint deployment are still pending.
- An access response is a current status display, not a reusable upload/recording
  authorization. Every protected operation must check server permissions again.
- Real PostgreSQL tests include captured app permission helper definitions and
  synthetic teams/guardians/events; they never use live athlete or billing data.

Launch payment status updated October 3, 2026:
- Owner screenshots confirm Paid Apps Agreement, bank account and U.S. W-9 Active.
- Digital Services Act In Review; account setup does not activate the billing runtime.
- Family prices above reflect the owner's October 3 revision; change the matching
  App Store Connect prices before submission. StoreKit localized metadata remains
  authoritative in the purchase screen. SMS allowance has not been defined.

App Store Information screenshots verified October 3, 2026:
- App name The Wrestling Manager; Apple ID 6815511370.
- Bundle ID com.damonmele.wrestlingmanager matches the uploaded Xcode project.
- Version 1.0 is Prepare for Submission.
- Category fields, subtitle, content-rights declaration and age ratings are unset.
- Production and sandbox App Store Server Notification URLs are unset.
- Configure notification URLs only after the signed V2 receiver is deployed/tested.
- Screenshots of the encryption/medical documentation sections alone do not
  establish a completed declaration or any requirement to upload documents.
- Supplied Wrestling-Manager-Info(2).plist parses successfully; the project-referenced
  filename is Wrestling-Manager-Info.plist. Usage descriptions come from build settings.

Subscription notification receiver candidate added:
- Bounded server-only POST accepts signedPayload only, with explicit rate limiter.
- Uses AppleEvidenceAdapter.notificationTransaction for signature verification and
  canonical subscription status. No app-user JWT is expected on this Apple route.
- Durable private inbox acknowledgement required before HTTP 200; duplicate
  notifications preserve first observation and immutable original/token binding.
- Seven HTTP checks passed; disposable PostgreSQL checks confirm immutable retries,
  environment/binding conflicts and anon/authenticated denial.
- Verified Apple TEST notifications are now handled without granting access.
  Summary and consumption notifications still require distinct handling; do not
  configure server URLs until runtime deployment and Apple test delivery pass.
- Inbox schema remains a draft: retention/deletion catalog and runtime privileges
  must be integrated. Worker leasing, canonical recheck and entitlement application
  are not yet wired. This receiver alone does not change paid access.

Notification reconciliation worker and Apple configuration added:
- Refreshes canonical Apple status before applying a known original/token binding.
- Existing-subscription policy is shared with purchase delivery; no fake user session
  is constructed. Notification processing never creates a purchaser/team binding.
- Private SQL leasing supports exclusive claims, expired leases and retry delay.
- Worker commits subscription snapshot and inbox completion in one transaction;
  failed/expired leases roll back. Old active evidence cannot overwrite a newer refund.
- Uses existing deletion actor lock and personal-account/tombstone controls.
  Unavailable owners stay pending for retry; no paid grant is introduced.
- 44 focused policy/Apple/HTTP/worker/config checks pass locally. Disposable
  PostgreSQL worker checks cover refund atomicity, duplicate/stale status, exclusive
  and expired lease, deletion freeze/retry and client denial. Full CI also runs
  the existing billing suite and Apple SDK/native/browser checks.
- Confirmed identity fixed in apple-server-config.mjs; server secret required:
  APPLE_IAP_PRIVATE_KEY (original multiline contents of owner's In-App Purchase .p8).
  Superseded October 4: the private key is configured in the deployed Render Node
  verifier, not Supabase. Supabase holds only APPLE_VERIFIER_URL and the matching
  APPLE_VERIFIER_SHARED_SECRET; both passed live authentication on October 5.
  See docs/apple-verifier-deployment.md. Never paste the private key in chat/GitHub.
- Runtime deployment, dedicated DB identity, financial retention/deletion catalog,
  verified Apple trust roots, authenticated scheduler and real sandbox/device tests
  remain required. No live endpoint or migration was deployed in this step.
