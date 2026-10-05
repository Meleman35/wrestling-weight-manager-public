# Production Apple authorization investigation — October 5, 2026

Production 401 remains unresolved after a bounded recheck at 23:41 UTC. The same
live verifier accepted a fresh Sandbox request and verified successful delivery.
Customer payments remain disabled. No web/native release or App Store submission
was made. Keep the working key and environment separation intact.

## Owner screenshots and bounded recheck, 23:41–23:43 UTC

The owner's October 5 screenshots confirm the app ID `6815511370`, exact bundle
`com.damonmele.wrestlingmanager`, and saved Production/Sandbox receiver URLs.
The 17:36:49 America/Denver screenshot shows the In-App Purchase key under
**Active (1)**: key ID `79R244P822`, issuer
`b5931be7-ac93-4ab3-9b1a-15e1dd26a549`. Both match the deployed public
configuration. No private key was viewed or changed.

Version 1.0 is **Prepare for Submission**, with no build selected on that version
page. This does not establish whether TestFlight has uploaded builds. The Apple
Standard License Agreement is selected. Category, content rights, age rating and
review fields remain incomplete in the supplied screenshots. Product statuses,
current Paid Applications Agreement status and trader verification approval have
not yet been inspected. Notification version was not visible in these screenshots;
the earlier owner confirmation of Version 2 remains the evidence for that setting.

| Check | Fresh result |
| --- | --- |
| Preflight | Readiness true; 10 focused diagnostic, response-validation and connection tests passed. |
| Private diagnostic | Version 3, five deployed files matched reviewed source; fixed expiry 23:51:33 UTC; unauthenticated call returned 403. Existing database capability and verifier credentials used only server-side. |
| Production | One request at `2026-10-05T23:41:57.791860Z`; Apple HTTP 401, no numeric Apple error code returned by the adapter, no TEST token. |
| Sandbox control | Request accepted at `2026-10-05T23:42:08.158061Z`; returned TEST signature verified; Apple reports first-attempt SUCCESS at `23:42:09.333Z`. Notification ID `c3e67756-7c41-4484-af77-a5da8698e0a5`. |
| Closure | Restored the original closed handler as version 4 at 23:42:39 UTC, with gateway JWT verification enabled. Deployed source matched; unauthenticated request rejected by gateway with 401. Handler itself remains 410. |
| Postcheck | At 23:43:09 UTC readiness true; zero subscriptions, purchase intents, notification inbox rows and enrolled accounts. |

This is an environment-specific authorization failure under the same service and
credential configuration. Its root cause is still unknown. Sandbox control success
does not prove a customer purchase, benefit delivery or Production readiness.
There is no evidence here that changing notification URLs or rotating the working
key would fix it. The unreleased app state alone is not an established cause.

## Earlier read-only checkpoint

| Check | Result and limit |
| --- | --- |
| GitHub main | `4a5ec6c429740b56e9e5da7219ed0b254f3e31e3`; web release 0.20.122 remains the published checkpoint. No fresh live-web byte comparison in this continuation. |
| PR #62 | Open, draft, unmerged at `38869f46528776e88323ccf7fcb1a15843895155`; all 26 workflows completed successfully. This is the inspected pre-documentation head, not a claim about later heads. |
| Local candidate | `26fd67d43a81d79bc98cf134396e3d185b63d644`, tree `92ee95c38f995b4cd24e91061c0d5c0520416d0d`; existing untracked backup and validation files preserved. |
| Render | Existing `wm-apple-verifier` service remains live at `275daac1ca45229e0e2e680f67239ae9d23b7714`, deploy `dep-db1hsngu01pc73eh8pi0`; automatic deploy is off. `/health` returned `{"ready":true}`. Health is not Apple authorization. |
| Render logs | Log retrieval failed with a Render logging-service 503/504. No new claim of clean runtime logs. |
| Verifier source | Public configuration, evidence adapter, test adapter, server, worker and package/lock files have no diff between the live Render commit and the inspected candidate. |
| Supabase metadata | Billing v1, notifications v2, scoped deletion v12 and closed-test diagnostic v2 match the handoff's version checkpoint. Metadata read is not a fresh deployed-source comparison. |
| Database readiness | `notification_deployment_ready()` returned true. Zero subscriptions, purchase intents, notification inbox rows, enrolled accounts and pending deletion jobs. No records changed. |
| Scheduler | `wm-billing-notifications` remains active every minute; observed run at 18:53 UTC succeeded. This idle run is not a Production TEST delivery. |
| Purchase identity | Exact lookup for the selected test login returned no Auth account. Creation/confirmation and exact-team authority must precede enrollment. See `sandbox-purchase-acceptance.md`. |
| App Store Connect | The available browser reached Apple's sign-in form. No authenticated app, product, key, agreement, build or trader-status read was possible yet. |

## Code and documentation findings

The pinned official Node library is `@apple/app-store-server-library` 3.1.0.
`createAppleEvidenceAdapter` passes the same configured key ID, issuer and bundle
to Apple's API client for both environments. The client selects the expected
Production/Sandbox host and signs a fresh ES256 bearer JWT with `bid`, issuer,
audience `appstoreconnect-v1` and a five-minute expiry. This matches the reviewed
authentication format. No production-only signing branch or alternate credential
was found. This is source review, not inspection of a live signed request or key.

Apple documents HTTP 401 on Request a Test Notification as invalid JWT
authorization; missing notification URL has a separate 404 response. An Apple
commerce engineer also states that a properly constructed JWT should work in
both environments and emphasizes case-sensitive bundle IDs. Other developers
in that forum report success after first release, but that anecdote does not
establish this app's cause or justify releasing unaccepted billing.

## Remaining owner-visible checks

1. Use the owner's signed-in Mac session to read **Business → Agreements** and
   both Team Pro products under **Apps → The Wrestling Manager → Monetization →
   Subscriptions**. Screenshots of statuses are sufficient; banking/tax details
   are unnecessary. The cloud browser security-key sign-in was not completed.
2. Correct only an observed mismatch or incomplete requirement. Preserve completed
   banking/tax setup, app identity and the working IAP key. Do not repeat the API
   request without a configuration change or a specific Apple diagnostic request.
3. An unsent support-case draft is in `apple-production-support-draft.md`. Add the
   remaining status evidence before sending. Sending requires explicit owner
   authorization; no live JWT, private key or customer records belong in the case.
4. Require a verified signed Production TEST and successful delivery before
   marking production authorization complete. Real purchase/restore and benefit
   grant/removal remain separate device acceptance requirements.

## Official sources reviewed

- [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification)
- [Generating JSON Web Tokens for API requests](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests)
- [Creating API keys to authorize API requests](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)
- [Apple commerce engineer response on Production/Sandbox 401](https://developer.apple.com/forums/thread/711801)
