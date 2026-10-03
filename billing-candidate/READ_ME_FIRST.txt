Wrestling Manager billing candidate — October 2, 2026

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
- Disabled-by-default Fetch route for prepare, deliver and abandon operations.
- Native StoreKit purchase, restore, unfinished recovery and updates listener.
- Native HTTP adapter with public gateway key, authenticated requests, strict
  acknowledgements, blocked redirects and immutable account/session generation.
  Logout stops the adapter; a stopped instance cannot be reused.

Verification
- Latest isolated CI: 76 backend checks passed, none skipped, including disposable
  PostgreSQL concurrency, rollback, cancelled reservation and role-access checks.
- Apple SDK type checking passed for the two candidate Swift files.
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
4. Implement authenticated family athlete selection and authoritative access APIs;
   resolve canonical profile IDs and current guardian/filming permissions on server.
5. Wire verified notifications and scheduled reconciliation so refunds, expirations
   and renewals update access even when the purchasing device is offline.
6. Integrate the candidate Swift files into the working native project. Add an
   origin-checked, main-frame-only web bridge and authenticated session lifecycle.
   Plan screens must use Apple product metadata and server-authoritative access.
7. Run full Xcode compilation, local StoreKit and device sandbox checks: purchase,
   cancellation, pending approval, restart/network recovery, restore, account
   switch/logout, monthly/annual changes, refund and expiry.
8. Complete App Store Connect paid agreements, tax, banking and review metadata.
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
Private signing key: downloaded on owner's Mac; not configured on server yet.
Apple numeric app ID: still needs confirmation for production verification.
Bundle ID: confirm from the working Xcode target and App Store Connect; do not
infer it from a product ID prefix.
Endpoint reserved in native code:
https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-billing
This endpoint has not been deployed. Publishable gateway key is public app
configuration; service-role credentials and Apple private keys are server only.

Product catalog
com.damonmele.wrestlingmanager.teampro.annual — $269.99/year
com.damonmele.wrestlingmanager.teampro.monthly — $75/month
com.damonmele.wrestlingmanager.familyvideo.annual — $99.99/year
com.damonmele.wrestlingmanager.familyvideo.monthly — $14.99/month
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
