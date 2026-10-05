# Core app launch acceptance

Owner approved the phased release on October 4, 2026 at 8:14 PM Mountain: core app first; nationwide remote weigh-ins in a later update. On October 4 at 9:08 PM Mountain, Damon also deferred Family Video; at 9:10 PM he added texting to the same update goal of October 25. First-release purchases are Team Pro only. See `family-video-texting-update-plan.md`. This is the single core device acceptance round to run **after** the hosted prerequisites below are complete. Remote capture, director billing/trials, exports, vendor imports and 240-hour remote evidence expiry do not block this release. Preserve their later-update requirements in `docs/remote-weighins-launch-status.md`.

## Candidate and known state

- Integration: PR #62, `codex/launch-integration-20261004`.
- Original app: `native-app/Wrestling Manager Xcode App.xcodeproj`, scheme `Wrestling Manager`, version 1.0 (9).
- Preserved bundle ID `com.damonmele.wrestlingmanager` and signing team `RGB5BL98V8`.
- Normal Run has no local StoreKit configuration. `Wrestling Manager Local StoreKit` is explicitly a simulation scheme; its receipts must never be accepted by the hosted service.
- First-release Team Pro remains $75 monthly / $269.99 annual. Live purchase screens use Apple's localized metadata. Family Video prices ($10 monthly / $75 annual) are retained for the later update and must not be offered at launch.
- Owner confirmed the isolated Build 7 camera/scale flow on October 4. Its tested transport/stability logic is preserved in the main app's local package.
- These source changes do not publish the website, deploy billing/remote services, enable paid access, or submit to Apple.

## Prerequisites before handing over the device checklist

1. Resolve the confirmed Apple-verification runtime incompatibility using the prepared Node service in `docs/apple-verifier-deployment.md`. Damon approved and deployed the Render service on October 4. The private Apple key is configured there, and the saved Supabase URL/shared secret passed live authentication. Actual signed Apple evidence still needs verification. Keep the existing `.p8` as `APPLE_IAP_PRIVATE_KEY` in that Node service, with only its private URL/shared secret in Supabase. Keep the key out of chat, source, screenshots, the native app and ZIPs. Public key ID remains `79R244P822`; products, agreements, tax and banking do not need recreating for this step.
2. Verify Apple's signed sandbox notification delivery using `apple-notification-setup.md`. The receiver and private minute scheduler are deployed; both Production and Sandbox worker probes passed. Hosted billing deletion/retention integration and schema migrations are installed. The restricted database connection passed live password authentication and role checks after the owner's private secret copy (see `docs/billing-database-connection.md`). Real hosted Auth/Storage deletion with all billing tables passed, preserved the other account, rejected the old JWT and cleaned every fixture. See the October 5 checkpoint in `launch-verification-2026-10-04.md`. The app purchase endpoint remains undeployed; its activation still requires these checks and the device purchase round. The runtime composition requires deployment verification and a restricted database identity.
3. Connect paid access to the actual first-release benefits. Practice plans and wrestler-statistics coverage now use verified Team Pro state, with current session, deletion, expiry/refund and isolated sandbox checks. Seven full-schema protected-operation scenarios pass; real Apple device purchase acceptance remains. Family Video is deferred and must not appear as a first-release purchase. Its pilot/consent/recorder work belongs to the later update. A working purchase/restore screen alone is insufficient. Verify granted, expired and refunded access at the protected operation. Advertise only accepted available benefits.
4. Keep remote reporting unregistered in `src/launch-bootstrap.mjs` and exclude remote/director promises from the first-release listing and purchase screens. Preserve ordinary team scale/NFC behavior and future remote source/tests.
5. Publish the reviewed web candidate with matching cache/version changes, then build the same native candidate. Confirm no production data was altered by acceptance fixtures.
6. Require current CI to pass: full Debug/Release app builds; billing PostgreSQL/native/browser checks; core launch entry points and existing app regressions. Existing remote component tests may continue as regression coverage without implying remote launch readiness.

## One device round

Use designated test accounts and fictional athlete records. Keep ordinary paid accounts and real athlete records out of destructive tests. Reuse the known working scale/NFC setup; do not repeat isolated remote camera testing.

| Check | Required result |
|---|---|
| Sign in and open Plans | Only Team Pro is offered in the main app; Apple's prices and original team binding are correct. |
| Purchase and restore in Apple sandbox | Test cancellation, pending approval, completed purchase, lost response/reopen and restore. Server access changes only after verified delivery. Family Video purchase requests are blocked and no texting benefit is advertised. |
| Purchased benefits | The plan's advertised accepted features work for the covered team/athlete. Refund/expiry tests remove paid access without changing roles or guardian controls. An unrelated team receives no benefit. |
| Switch account/team; lock/background | Previous account requests and screens close. No old photo, purchase result, access display or capture continues into a replacement account. |
| Ordinary team weigh-in and athlete cards | Existing scale/NFC/QR identification records the intended test athlete's weight; Save to Files and printing work for the team athlete-card export. Remote reporting is absent. |
| Disposable account deletion | Cancel first. Then delete a designated disposable personal account. Require server completion plus local cleanup; another account's files remain usable. Verify the approved paid-team remainder behavior with another authorized administrator. |
| Existing main app smoke check | Sign-in, scale/NFC setup, team navigation, messaging safeguards, Offline Mat Mode and saved bouts remain usable. |

Record each failed step with the test account role, expected behavior, actual behavior and whether connectivity changed. A screenshot of status text is enough; do not send athlete photographs or private keys.

## Submission work

Prepared listing text and review fields are in `docs/app-store-submission-draft.md`; they have not been entered or submitted.

After acceptance, review App Store privacy answers against the deployed data inventory, complete category/content-rights/age-rating fields and review notes, attach the correct subscriptions and accepted build, and check outstanding trader verification. Earlier screenshots are not proof of current App Store Connect status. Public release still requires Apple's review.
