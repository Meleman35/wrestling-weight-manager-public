# Combined launch acceptance

This is the single device acceptance round to run **after** the hosted prerequisites below are complete. Do not ask the owner to repeat the isolated scale test while these prerequisites remain open.

## Candidate and known state

- Integration: PR #62, `codex/launch-integration-20261004`.
- Original app: `native-app/Wrestling Manager Xcode App.xcodeproj`, scheme `Wrestling Manager`, version 1.0 (9).
- Preserved bundle ID `com.damonmele.wrestlingmanager` and signing team `RGB5BL98V8`.
- Normal Run has no local StoreKit configuration. `Wrestling Manager Local StoreKit` is explicitly a simulation scheme; its receipts must never be accepted by the hosted service.
- Local Family Video prices reflect the owner's approved $10 monthly / $75 annual decision. Team Pro remains $75 monthly / $269.99 annual. Live purchase screens use Apple's localized metadata. App Store Connect prices still require independent confirmation.
- Owner confirmed the isolated Build 7 camera/scale flow on October 4. Its tested transport/stability logic is preserved in the main app's local package.
- These source changes do not publish the website, deploy billing/remote services, enable paid access, or submit to Apple.

## Prerequisites before handing over the device checklist

1. Resolve the confirmed Apple-verification runtime incompatibility using the prepared Node service in `docs/apple-verifier-deployment.md`. Damon approved and deployed the Render service on October 4. The private Apple key is configured there, and the saved Supabase URL/shared secret passed live authentication. Actual signed Apple evidence still needs verification. Keep the existing `.p8` as `APPLE_IAP_PRIVATE_KEY` in that Node service, with only its private URL/shared secret in Supabase. Keep the key out of chat, source, screenshots, the native app and ZIPs. Public key ID remains `79R244P822`; products, agreements, tax and banking do not need recreating for this step.
2. Complete and verify hosted billing deletion/retention integration, least-privilege runtime identity, schema migrations, notification receiver and authenticated reconciliation schedule. Test Apple's signed sandbox notification delivery. The runtime composition deliberately requires deployment verification and a restricted database identity.
3. Finish remote program/window provisioning, canonical consent and credential resolution, trusted capture provenance and server-clock validation, team/director coverage, private storage and the 240-hour retention worker. Complete their server deletion/merge catalog integration and hosted capacity checks.
4. Connect the remote reporting coordinator to its authorized native capture screen and real receipt service. Server-saved data must not be represented as saved while only queued on the device. The reporting screen stays hidden until that integration is ready.
5. Publish the reviewed web candidate with matching cache/version changes, then build the same native candidate. Confirm no production data was altered by acceptance fixtures.
6. Require current CI to pass: full Debug/Release app builds; production capture/queue tests; billing PostgreSQL/native/browser checks; remote export/retention/access checks; existing app regressions.

## One device round

Use designated test accounts and fictional athlete records. Use an adult in appropriate athletic clothing for camera tests. Keep ordinary paid accounts and real athlete records out of destructive tests.

| Check | Required result |
|---|---|
| Sign in and open Plans | Team Pro and Family Video appear in the main app; Apple's prices and original team binding are correct. |
| Purchase and restore in Apple sandbox | Test cancellation, pending approval, completed purchase, lost response/reopen and restore. Server access changes only after verified delivery. Family selections contain accepted linked athletes and remain consistent across team copies. |
| Switch account/team; lock/background | Previous account requests and screens close. No old photo, purchase result, access display or capture continues into a replacement account. |
| Camera setup and two athlete credentials | Confirm face, singlet, feet and scale framing once. Each NFC/QR lookup identifies the intended enrolled athlete. Scan → step on → automatic weight/photo → step off → next scan. |
| Permitted reweigh | A lighter valid repeat replaces the selected result with its matching photo/time. A heavier repeat keeps the lower result. A tournament that disallows reweigh rejects a repeat. |
| Movement, disconnect and deadline | No settled result is fabricated after movement, stale readings, disconnect, changed device clock or the closed capture window. Reconnect/retake does not attach a previous athlete's image. |
| Interrupted delivery and restart | A captured attempt stays visibly queued until the matching server receipt is saved. Retry/restart returns the same submission/receipt and does not duplicate or refresh the original timestamp. |
| Director across two clubs | Club readers see only their club; the assigned director sees both. Name, member number, picture, scale weight and time remain matched. |
| Export and actual vendor import | Save CSV and photo workbook to Files, reopen them, and import the agreed columns into Trackwrestling / USA Bracketing using a test tournament. Vendor-specific weight-update automation remains off until proven. |
| Retention notice | Directors see the ten-day expiry/download warning and understand their saved copy persists independently. Automated expiry tests cover the exact 240-hour boundary; the owner need not wait ten days. |
| Disposable account deletion | Cancel first. Then delete a designated disposable personal account containing queued remote evidence. Require server completion plus local cleanup; another account's files remain usable. Verify the approved paid-team remainder behavior with another authorized administrator. |
| Existing main app smoke check | Sign-in, scale/NFC setup, team navigation, messaging safeguards, Offline Mat Mode and saved bouts remain usable. |

Record each failed step with the test account role, expected behavior, actual behavior and whether connectivity changed. A screenshot of status text is enough; do not send athlete photographs or private keys.

## Submission work

Prepared listing text and review fields are in `docs/app-store-submission-draft.md`; they have not been entered or submitted.

After acceptance, review App Store privacy answers against the deployed data inventory, complete category/content-rights/age-rating fields and review notes, attach the correct subscriptions and accepted build, and check outstanding trader verification. Earlier screenshots are not proof of current App Store Connect status. Public release still requires Apple's review.
