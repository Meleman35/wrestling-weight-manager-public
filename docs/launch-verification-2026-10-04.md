# Combined launch verification — October 4, 2026

Main-app verification checkpoint: `17911b0c4fe2210ce76829284f418c3e7d30193b` on PR #62, with all 24 workflows successful. The subsequent Node-verifier change has additional checks listed below. This report concerns candidate code, not production billing or Apple acceptance.

Follow-up checkpoint `c23c32ee211320fb265ffa29398f035c4c9d9dff`: the full main-app Debug/Release and production encrypted capture/queue workflow passed again. Billing passed 159 Node/PostgreSQL tests with zero failures or skips, all six Deno compatibility checks, and notification database, Swift and browser jobs. Evidence: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37243198669 and https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37243198754.

## Passed

- Full original main-app Debug and Release simulator builds, with preserved bundle/signing identity and matching canonical billing/remote/scale sources.
- Production capture host with actual encrypted file queue and Keychain: camera opens before stable weight, one scan authorization, two automatic weight/photo saves, fresh-zero next-scan handoff, duplicate/revoked scan rejection, isolated personal-account cleanup and stale-queue resurrection rejection. Camera hardware and BLE input are simulated.
- Billing: 151 tests passed, zero failed or skipped, including disposable PostgreSQL transactions, concurrent purchase bindings, exact session revocation, deletion actor locks, deleting-team rejection, unavailable-purchaser access, canonical family selection and restricted app-role access.
- Separate Apple notification database checks: refund update and inbox completion are atomic; duplicates, stale status, leases, deletion freeze and client-role denial are checked.
- Native purchase authentication/transport executables and Swift component type checking.
- Browser Plans and family selection, including responsive rendering, native activation readiness and account/session lifecycle isolation.
- Existing application regressions including offline/Mat Mode, parent permission and adult review, account deletion, health/trainer, notifications, cards, merge, practice plans and statistics.
- Remote reporting JavaScript/PostgreSQL/browser checks, including bounded export, immutable time windows, retention, lower valid reweigh selection and club access.

Evidence:
- Main app and production capture host: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37241459224
- Billing: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37241459155
- Remote foundation: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37241459196

## Scope of these results

The owner already confirmed isolated Build 7 physical scale/camera behavior. That does not establish end-to-end production reporting. A compiled app and simulated capture do not validate actual Apple receipts, live tournament imports, hosted throughput, real device camera/BLE permissions or live database/storage expiry.

No web publication, live remote/billing data schema deployment, customer payment activation, App Store submission or production data deletion was performed in this integration work. Hosted changes include the read-only, JWT-protected readiness diagnostics, the owner-created $7/month Node verification service, and the restricted billing identity described below. Remote reporting remains hidden. The original main app still loads https://theteammanager.app/.

The diagnostic returned HTTP 200 with `appleCertificateVerification: false` and `billingEnabled: false`. Pinned Deno 2.1.4 reproduces the missing `crypto.X509Certificate.prototype.verify` API. Apple's official verification library needs that function; local payment verification cannot be activated on the checked Supabase runtime.

A separate Node backend verifier is deployed from commit `5ce6fee11931e9fe4cf191f052bbda92eeaef380` to `https://wm-apple-verifier.onrender.com`. Render deployment `dep-db1eonc9v7es73f7kp60` is live; Node 22.23.3 built and started successfully. External checks returned HTTP 200 with `ready: true` for `/health`, and HTTP 403 with `not_authorized` for an unauthenticated POST to `/apple`. These checks validate startup and rejection of unauthenticated requests, not Apple credentials or a real transaction.

The six Deno compatibility checks pass for the remote path, including an explicit assertion that local certificate verification remains blocked. Focused Node checks cover authorization, input bounds, request/environment binding, worker failure and configuration. No valid live Apple transaction has been verified in this environment.

The Apple private key is not available in the project or uploaded files. The owner supplied it directly to the approved Node service as `APPLE_IAP_PRIVATE_KEY`. The owner saved the service URL and matching generated shared secret. Live diagnostic version 4 returned HTTP 200 with both configuration flags, reachability and authentication all true; billingEnabled remains false. Four diagnostic tests cover secret redaction, exact destination, denied/malformed/oversized responses, redirect rejection and method/origin restrictions. Damon approved the $7/month hosting on October 4 and completed the Render deployment. See `docs/apple-verifier-deployment.md` for the concrete setup. Private database connection acceptance, billing deletion/retention and paid-team remainder integration, remote program/consent/credential provisioning, trusted capture provenance and live routes/workers remain prerequisites, not completed deployments.

Use `docs/launch-acceptance-batch.md` for the single combined physical round after these prerequisites are complete. Use `docs/app-store-submission-draft.md` for prepared listing and review text after the accepted feature set is known.

## October 5 billing continuation

The private paid-team remainder candidate now includes database storage, atomic personal billing cleanup at the leased deletion transition, current-admin access checks, post-deletion refund matching, pending-refund preservation, immutable paid boundaries and bounded expiry cleanup. Seven isolated PostgreSQL scenarios passed. These are synthetic tests, not deployed financial data changes. The ordinary Node suite passed locally with the localhost PostgreSQL suite skipped; GitHub CI provides that separate real-server check. See `billing-candidate/deletion-coverage-decision.md` for remaining catalog and full-worker integration requirements.

GitHub billing verification at `48dbaa441d4f506622339aa4e0e7d5f3bd3b4c89` completed successfully: 168 Node/PostgreSQL tests, zero failures or skips, six pinned Deno checks, both notification/remainder PostgreSQL executables, Swift type/transport/authentication and browser jobs. Run: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37249226840. The real PostgreSQL suite ran there, including the updated schema load order.

## Restricted database identity checkpoint

Migration `20261005011326_billing_runtime_identity` is applied. It provisions only the restricted billing login/runtime roles and a server-generated connection credential in Supabase Vault. Live checks confirmed the expected role attributes, no application-table or Vault-read access for the login, unchanged deletion schema hash and unchanged security-advisor findings. No billing data schema or paid access was activated.

The JWT-protected `wm-billing-readiness` v1 is deployed. Its live POST returned HTTP 200 with database readiness false until the owner saves `BILLING_DATABASE_URL` in Edge Function Secrets. Actual password authentication and selected-role checks remain unverified until that copy. See `docs/billing-database-connection.md`.

Local verification: 154 Node tests passed, zero failed, with one disposable localhost PostgreSQL suite skipped; seven pinned Deno tests passed; the isolated PostgreSQL identity executable passed, including rollback and overwrite refusal. A separate Deno CLI type-check could not fetch `pg` because the local npm registry connection was refused. The deployed function successfully imported that pinned dependency and served its live readiness response; this is not a claim that the CLI type-check passed.

The owner's private copy is now verified live: HTTP 200 with database URL configuration, connectivity and restricted identity all true; billing remains disabled. At checkpoint `036ef6ce4e8ebd59480c96d767721434ec6df913`, all 24 GitHub workflows completed successfully, including Billing candidate checks, Remote weigh-in foundation and Combined launch candidate. Billing run: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37251194161.

## Full billing/deletion worker integration

The candidate now prepares a paid-team remainder before the generic deletion worker erases billing records. All seven billing tables enter the reviewed planner, schema fingerprint, read and write-freeze coverage. Seven complete worker scenarios passed using synthetic users and injected Auth/Storage providers, including rollback, late-write denial, exact paid-period preservation, acknowledged refunds, personal/team/all scope isolation and Auth retry completion. The seven earlier paid-remainder scenarios and existing deletion planner/service/handler regressions also passed. The Node suite remains 154 passed, zero failed, one local PostgreSQL skip.

Read-only live source comparison confirmed the service, schema hash, bounded reader and media sealing bodies match canonical sources. The candidate media inventory uses its existing hosted follow-up migration, preserving another adult's shared profile photo when their team staff record is removed and keeping the original migration assembly unchanged. The live deletion hash remains `c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8`, with a matching catalog and no pending deletion jobs at the check. Billing data SQL remains undeployed pending athlete-merge compatibility, a reviewed migration, hosted acceptance and scheduling.

## Family coverage and athlete merge checkpoint

All 25 workflows at `2181716857822b5071a2192370f64ad909db9765` passed, including the full combined Debug/Release build, remote foundation, billing and scoped-deletion worker. This is the completed baseline before the merge changes below.

The billing merge candidate transfers family selections to the kept canonical athlete, keeps existing slot assignments and collapses duplicate selections without adding subscriptions. Coverage changes invalidate an earlier merge preview. Direct billing-runtime writes to selections are revoked; the authorized selector shares the merge lock before resolving profiles. The router patch pins the complete inspected function body and leaves the live schema fingerprint gate intact.

Six full-schema synthetic PostgreSQL merge checks passed: source drift and atomic installation refusal; restricted helper/table permissions; stale preview, slot/guardian preservation and retry receipts; late failure rollback; pending deletion/shared-identity protection; same-profile coverage and schema drift rejection. The Node suite passed 154 tests, zero failures, with the local real-server PostgreSQL suite skipped. A separate-connection lock-contention test was added to that CI suite. No live billing data schema changed.

Next: review and assemble the combined billing/deletion/merge migration, run hosted acceptance, then configure signed Apple notification delivery and scheduled reconciliation. Remote hosted provisioning, capture/receipt/private storage/expiry services and native reporting integration remain necessary before the combined device round. The full paid nationwide release is provisionally estimated at 1–2 weeks to submission readiness from this checkpoint, assuming no major testing failures, plus Apple's review. This is a planning range, not a guaranteed release date; a smaller core-app release needs an explicit scope decision.

## Approved core-first release

Damon approved launching the core app first on October 4 at 8:14 PM Mountain. Nationwide remote weigh-ins and director billing/trials move to a later update. The launch bootstrap no longer imports or registers the remote reporting client and removes its unused entry/screen. Ordinary scale/NFC tools remain. Purchase notices, submission notes and the single device checklist reflect this scope; remote acceptance is preserved separately.

The CLI-generated `20261005023948_core_billing_deletion_merge.sql` combines all seven private billing tables with deletion and merge integration. Installation locks the existing lifecycle configuration, rejects pending deletions, pins the live baseline fingerprint and six privileged function definitions, and atomically updates both reviewed compatibility gates. It preserves the current deletion-enabled flag and does not activate payments. Source assembly parity and five isolated migration scenarios cover drift refusal, pending deletion, restricted roles, access restrictions, replay refusal and an actual merge after the fingerprint change. All seven complete deletion-worker scenarios now execute against this assembled migration and pass with synthetic identities/providers.

Core benefit audit: live `private.wrestler_statistics_covered` returns false, and practice plans delegates to it. Video recording still requires the pilot/consent/recorder gates. Connecting purchases alone will not unlock these benefits; paid feature enforcement must be completed and accepted before activation. The first-release estimate must account for that remaining work. The earlier 1–2 week estimate described the full nationwide release and is not a core release date.

Hosted deployment checkpoint: `scoped-deletion` version 12 is active and its five downloaded files exactly match the reviewed local source. Only the billing-aware planner and policy changed from version 11; HTTP authentication, request handling and worker execution source are unchanged. The subsequent `apply_migration` request for `core_billing_deletion_merge` returned `status: declined` without a reason. No workaround was attempted. Read-only checks confirm no `wm_billing` schema, unchanged live/approved `c1f0c928…02bdf8` fingerprint, deletion still enabled and zero pending jobs. The live migration needs approval before retry.

At `f84611cc35e63ca0ca62de72f5138391af6850b7`, core launch information/browser verification, billing real PostgreSQL policy, native Swift, all migration/deletion database scenarios and the general deletion regression passed. The subscription browser test still looked for the old disclosure heading; its selector is corrected to the new heading and now checks that remote weigh-ins are clearly deferred. Local browser execution was unavailable because the browser download was truncated; GitHub runs the actual browser checks.


## October 5: approved deployment and hosted acceptance

Damon explicitly approved the billing migration after the earlier automatic decline. The retry succeeded. The applied migration version is `20261005023948`; the local file was aligned with hosted history without changing its reviewed SQL. All seven tables have RLS and deletion-freeze triggers. Anonymous and authenticated roles have no schema/table access, and the restricted billing runtime cannot directly write family selections. Deletion remains enabled, with live/catalog fingerprint `22b2b942416753db8212d4f2bb4550da01713e687376eb2becaa8f6dfb22f350`. The merge router uses that fingerprint and the family-coverage integration. Installation left zero billing rows and no pending jobs.

The expanded acceptance fixture caught a closed-team edge case: pre-existing paid remainders could be touched before sealed record erasure. The source-pinned `20261005024934_billing_closed_team_remainders.sql` excludes closing teams/organizations from remainder reconciliation; their sealed rows are erased normally. The new fixture regression executes the real planner, worker, service and freeze triggers, verifies cross-account preservation and checks scoped fixture cleanup. Service-only fixture helpers are installed by `20261005024932_core_billing_hosted_acceptance.sql`; they require an expiring capability and tagged synthetic identities.

Real hosted acceptance run `aa9b1d7a-ccc5-4c4c-a630-d826385e4a60` completed in one worker attempt. Real Auth and Storage checks passed: departing account/files/billing removed; old JWT rejected; other account, profile, athlete, team, file and billing preserved. All 20 verification flags passed. Cleanup then removed the retained fixtures, confirmed `fixtures_cleaned: true`, expired the capability and left zero billing rows/no pending jobs. The temporary `core-billing-deletion-acceptance` Edge runner was replaced by a closed HTTP 410 handler (version 2, JWT verification enabled). This acceptance used synthetic subscription snapshots, not signed Apple purchase evidence.

`20261005025902_team_pro_feature_access.sql` connects existing practice-plan and wrestler-statistics operations to verified Team Pro storage. It preserves their role/athlete authorization and adds live personal session, payer, deletion, expiry/refund/grace and paid-team remainder checks. Production is the default. Sandbox requires an expiring server-managed `auth.users.raw_app_meta_data.wm_billing_sandbox` enrollment for the exact caller/team; no account was enrolled by installation. Neither client/JWT metadata nor a tester enrollment alone grants paid access. Seven isolated full-schema scenarios pass, including actual practice save/read and statistics reads, 40 policy-parity cases, cross-team denial and session/refund/expiry restrictions.

Live post-deployment checks confirm both benefits are connected, helpers are not client-executable, the deletion fingerprint still matches and there are no subscriptions. Security-advisor counts remain at the prior baseline: 110 informational RLS/no-policy entries, 2 anonymous and 183 authenticated definer warnings, and 1 password-protection warning; no new billing findings. All 25 workflows passed at `9b406ac0ab5c5ab8417c6b4b13d070af7cb687ef`; the new checkpoint must also pass CI after publication.

Payments remain disabled. Next prerequisites are the actual signed Apple notification/purchase flow, durable reconciliation/retention scheduling, Family Video's accepted paid rollout, and one consolidated native device round. No website publication or App Store submission is implied by these server deployments.


## October 4, 9:08–9:10 PM Mountain: Team Pro first; Family Video and texting target

Damon accepted deferring Family Video from the first release and set a three-week goal, then added texting to that same update. The target is October 25, subject to acceptance and Apple review. Nationwide remote weigh-ins remain a separate later update. The roadmap is in `family-video-texting-update-plan.md`.

The first-release host now exposes Team Pro only; a direct Family Video open request shows an unavailable notice without activating StoreKit or loading family selections. Backend capabilities advertise only the two Team Pro products, and the authenticated prepare route rejects both Family Video IDs before creating an intent. Existing verified delivery/restore reconciliation and future family component tests remain. Native StoreKit already restricts product loading and purchases to the server-authorized product set. Focused launch checks pass (15/15); the full local Node suite passes 155 tests with one localhost database skip. The full main-app native build at the prior `954ca5d5a69a864c62dbc852d68c7a470968775c` checkpoint passed. Updated browser checks must pass on the new published checkpoint.

A one-time October 25 morning readiness review is scheduled. It will inspect current repository evidence and report remaining owner decisions/tests; it cannot activate purchases/texting or submit/release a build.

## October 5: hosted Apple notification receiver and schedule

Migration `20261005032225_billing_notification_runtime.sql` is installed. Readiness
requires the reviewed schema/catalog hash, completed and cleaned hosted deletion
acceptance, all seven billing RLS/freeze protections and the exact reviewed
deletion preparation function. Worker authorization uses a dedicated Vault
credential generated inside the database; no new secret was copied or exposed.
Anonymous/authenticated roles cannot invoke the helpers, and even the restricted
billing role cannot read Vault or invoke the private scheduler.

`wrestling-manager-apple-notifications` version 2 is active. All 27 downloaded
deployment files exactly match source. Production and Sandbox routes are
separate; the host never routes user purchase commands. The first deployment
revealed Supabase's internal path omits `/functions/v1`; the corrected strict
allowlist handles both internal and external forms, with a regression check.
Authenticated probes returned HTTP 200, `status: idle`, in both environments.
External checks returned 405 for GET, 403 for missing worker authorization and
browser origins, 400 for an empty notification, and 503 for forged signed data.
These results do not establish successful verification of real Apple evidence.

The `wm-billing-notifications` minute schedule was enabled only after those
probes. Its next two executions succeeded. It calls the bounded leased worker
only for due work; idle ticks perform no outbound request. Operational cleanup
removes completed or unbound pending inbox entries older than 30 days and expired
paid-team remainders, while preserving bound pending work and the subscription
ledger. Cleanup defers to active account deletion. This is separate from the
future remote weigh-in evidence policy of exactly 10 days.

Local verification: 161 Node tests passed, zero failed, one localhost PostgreSQL
skip. Four full-schema runtime database scenarios passed, covering permissions,
deployment drift, bounded retention, deletion priority and fixed scheduler
routes. Security-advisor counts remain unchanged (110 informational, 2 anonymous
and 183 authenticated definer warnings, 1 password-protection warning), with no
new billing findings. The live deletion hash remains
`22b2b942416753db8212d4f2bb4550da01713e687376eb2becaa8f6dfb22f350`;
there are zero subscription/inbox rows and zero pending deletion jobs.

Next owner setup is the Production/Sandbox Version 2 URL pair in
`apple-notification-setup.md`. Then complete a real signed Apple TEST, finish the
separate app billing route and run the consolidated native sandbox acceptance.
Payments remain disabled; no website publication or App Store submission occurred.

## October 5: real Apple Sandbox delivery and purchase acceptance host

After the owner saved both Version 2 notification URLs, the existing Render
service deployed `275daac1ca45229e0e2e680f67239ae9d23b7714`. Apple's real Sandbox
TEST verified successfully and Apple reported first-attempt delivery `SUCCESS`.
Production's test API returned 401 twice; its cause remains unconfirmed and
production billing stays blocked. The temporary capability-authenticated,
expiring operator bridge was replaced by a closed version 2 with JWT verification
enabled. See `apple-notification-test-results.md`. All 25 workflows passed at
that checkpoint.

Migration `20261005040311_sandbox_billing_enrollment.sql` adds a runtime-only,
server-metadata enrollment check without changing tables or the deletion hash.
The new `wrestling-manager-billing` version 1 accepts Sandbox evidence only, with
no request-selectable environment. Every actor read rechecks enrollment; prepare,
access, stored restore bindings and writes also check the exact enrolled team.
Family purchase/selection routes remain unavailable. No account was enrolled.
Production or local Xcode evidence cannot create access through this host.

The main native candidate now requires a server-declared purchase environment
matching StoreKit's verified app transaction and bundle ID before purchase
activation. Older native activation code rejects the new capabilities shape.
The updated Swift source is identical in the candidate and main app; project
identity/source integrity passes. Current SDK compilation and full builds must
pass on the published checkpoint, followed by real device acceptance.

Six full-schema database scenarios passed: deployment/role restrictions,
server-only enrollment, exact team/product preparation, actual delivery/access
services, rejection of Production evidence, enrollment revocation during Apple
waits, immutable restore scope, refund access removal, and invalid sessions/bans/
membership. Auth and Apple providers are synthetic in these database scenarios.
The full Node suite passes 169 tests, with zero failures and one localhost
PostgreSQL skip. Real PostgreSQL and native SDK checks run in CI.

All 28 deployed billing files match source. Hosted HTTP checks returned 401 for
missing/forged user authentication, 403 for foreign origins, 405 for GET, 204 for
the approved browser preflight, and 404 for a requested production subroute.
The live readiness check stays true; deletion hash and security-advisor counts
are unchanged. The next owner decision is a dedicated test login/team, followed
by the matching web/native candidate and consolidated device round described in
`sandbox-purchase-acceptance.md`. No real purchase or production charge has been
tested or enabled, and no App Store submission was made.
