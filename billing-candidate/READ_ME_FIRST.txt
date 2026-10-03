Wrestling Manager billing candidate — October 2, 2026 evening

This is prepared code for integration, not an installed payment release.
Do not replace the working Xcode project or submit a new build from these files.

Implemented and verified with 51 synthetic server/policy tests:
- Four exact products created in App Store Connect: Team Pro annual/monthly
  and Family Video annual/monthly.
- Team Pro remains bound to one team per purchaser for the initial launch.
  Original purchases and restores never silently move the team license.
- Family Video belongs to the authenticated personal account and covers up to
  two server-selected, currently linked athletes across teams.
- Any separately authorized filming device may record a covered athlete.
  Family billing never grants Team Pro or access to unrelated athlete records.
- Server-authorized purchase intents and opaque account tokens.
- Refund, expiry, grace, conflicting evidence, session changes and forged
  ownership rejected. Transactions finish only after durable acknowledgement.
- Apple signature verification and canonical status adapter with pinned library.
- Native StoreKit purchase, restore, recovery and update-listener component.
  Native API now takes a team or family target; the production adapter must
  implement this updated interface. Product prices come from Apple metadata.

The repository/auth ports are explicit contracts, not production implementations.
The intent repository must lock purchaser+subscription group, check current team
purchase authority or family eligibility, and enforce the one-team binding across
pending intents and historical purchases. The delivery repository must lock both
original subscription and intent token, enforce unique ownership, and return only
once commit succeeds. Do not interpret unit test in-memory storage as a database.

Family coverage inputs must come from current authenticated server relationship
queries and separately verified filming permissions. The base plan supports two
unique linked athletes. Third-athlete and 4–8 discounts are requested, but their
amounts/products are still undecided and are not activated in this candidate.

Still required before payments can be enabled:
1. Production storage/auth adapters, financial retention/deletion integration,
   verified Apple notifications and scheduled expiry reconciliation.
2. Apple server credentials and official root certificates configured privately.
3. A guarded native/web purchase bridge and plan UI with authenticated lifecycle.
4. Compilation against Apple SDK, then StoreKit configuration and device sandbox
   purchase, pending, cancellation, restoration and recovery tests.
5. App Store Connect banking/tax/agreement completion and required review metadata.

Local verification: npm test in this folder (51 tests pass). The library smoke
check rejects a forged signed transaction; no valid Apple purchase was tested.
No database schema, live paid access, billing endpoint or TestFlight build changed.

The existing working native app and archives remain the integration source. This
folder is a candidate to merge into that project after its ports are implemented.

Backend work added October 2 evening:
- Supabase token authentication mints an internal context only after verifying the
  exact token with Auth, then checks session/user status inside the DB transaction.
- PostgreSQL repository uses transaction-scoped original/token/purchaser locks,
  unique constraints, immutable bindings, and commit-before-acknowledgement.
- Private draft schema enables RLS and denies app roles direct billing access.
- Isolated PostgreSQL CI tests use synthetic fixtures, never the live database.
- 57 local tests pass; the real PostgreSQL suite runs only in disposable CI.

This is still a draft SQL schema, not a generated/deployed Supabase migration.
Financial retention/deletion catalog integration remains a deployment blocker.
Pending unpaid team selections can be cancelled through an authenticated operation;
paid original bindings and other accounts remain protected. HTTP routing, family coverage selection, Apple keys,
notification processing and production-runtime tests also remain unfinished.

Isolated PostgreSQL CI passed all 64 checks (before additional cancellation/coverage
checks). No billing schema or function was deployed to the live project.

Fetch-compatible route candidate added:
- Explicitly disabled by default; authenticated prepare/deliver/abandon commands.
- Bounded JSON bodies, exact browser origin, and sanitized error responses.
- It is not a deployed Edge Function and does not yet expose access/coverage APIs.
- HTTP routing tests pass locally; production runtime wiring remains unfinished.

Native HTTP adapter candidate added:
- Team/family prepare, receipt delivery, and unpaid cancellation requests.
- Uses one immutable account/session/generation with the latest access token.
- Rejects stale account responses, unexpected acknowledgement keys and redirects.
- Stops its ephemeral URLSession on logout. No local paid flag is installed.
- Endpoint name is reserved in code only; it has not been deployed.
- Integration must provide authoritative access refresh and destroy both store
  and adapter on logout. No web purchase bridge or live buttons are wired yet.
