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

No web publication, live remote/billing migration, customer payment activation, App Store submission or production data deletion was performed in this integration work. Hosted changes are the read-only, JWT-protected `wm-runtime-readiness` diagnostic and the owner-created $7/month Node verification service described below. Remote reporting remains hidden. The original main app still loads https://theteammanager.app/.

The diagnostic returned HTTP 200 with `appleCertificateVerification: false` and `billingEnabled: false`. Pinned Deno 2.1.4 reproduces the missing `crypto.X509Certificate.prototype.verify` API. Apple's official verification library needs that function; local payment verification cannot be activated on the checked Supabase runtime.

A separate Node backend verifier is deployed from commit `5ce6fee11931e9fe4cf191f052bbda92eeaef380` to `https://wm-apple-verifier.onrender.com`. Render deployment `dep-db1eonc9v7es73f7kp60` is live; Node 22.23.3 built and started successfully. External checks returned HTTP 200 with `ready: true` for `/health`, and HTTP 403 with `not_authorized` for an unauthenticated POST to `/apple`. These checks validate startup and rejection of unauthenticated requests, not Apple credentials or a real transaction.

The six Deno compatibility checks pass for the remote path, including an explicit assertion that local certificate verification remains blocked. Focused Node checks cover authorization, input bounds, request/environment binding, worker failure and configuration. No valid live Apple transaction has been verified in this environment.

The Apple private key is not available in the project or uploaded files. The owner supplied it directly to the approved Node service as `APPLE_IAP_PRIVATE_KEY`. The owner saved the service URL and matching generated shared secret. Live diagnostic version 4 returned HTTP 200 with both configuration flags, reachability and authentication all true; billingEnabled remains false. Four diagnostic tests cover secret redaction, exact destination, denied/malformed/oversized responses, redirect rejection and method/origin restrictions. Damon approved the $7/month hosting on October 4 and completed the Render deployment. See `docs/apple-verifier-deployment.md` for the concrete setup. Private database identity, billing deletion/retention and paid-team remainder integration, remote program/consent/credential provisioning, trusted capture provenance and live routes/workers remain prerequisites, not completed deployments.

Use `docs/launch-acceptance-batch.md` for the single combined physical round after these prerequisites are complete. Use `docs/app-store-submission-draft.md` for prepared listing and review text after the accepted feature set is known.

## October 5 billing continuation

The private paid-team remainder candidate now includes database storage, atomic personal billing cleanup at the leased deletion transition, current-admin access checks, post-deletion refund matching, pending-refund preservation, immutable paid boundaries and bounded expiry cleanup. Seven isolated PostgreSQL scenarios passed. These are synthetic tests, not deployed financial data changes. The ordinary Node suite passed locally with the localhost PostgreSQL suite skipped; GitHub CI provides that separate real-server check. See `billing-candidate/deletion-coverage-decision.md` for remaining catalog and full-worker integration requirements.

GitHub billing verification at `48dbaa441d4f506622339aa4e0e7d5f3bd3b4c89` completed successfully: 168 Node/PostgreSQL tests, zero failures or skips, six pinned Deno checks, both notification/remainder PostgreSQL executables, Swift type/transport/authentication and browser jobs. Run: https://github.com/Meleman35/wrestling-weight-manager-public/actions/runs/37249226840. The real PostgreSQL suite ran there, including the updated schema load order.
