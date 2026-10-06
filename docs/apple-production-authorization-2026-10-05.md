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
review fields remain incomplete in the supplied screenshots. Later agreement and
product screenshots are recorded below. Notification version was not visible in these screenshots;
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

## Agreement and product screenshots, 18:35–18:44 America/Denver

| Item | Observed status |
| --- | --- |
| Paid Apps Agreement | Active, effective October 3, 2026–September 18, 2027. |
| Free Apps Agreement | Active. |
| Payout bank account | Active; no bank identifiers copied into this record. |
| U.S. Form W-9 | Active, submitted October 3. |
| Digital Services Act verification | In Review, last updated October 3. Approval remains unconfirmed. |
| Wrestling Manager Team Pro subscription group | Prepare for Submission. |
| Annual product | 1 year, level 1, Prepare for Submission. |
| Monthly product | 1 month, level 1, Prepare for Submission. |

The October 5 18:44:56 screenshot truncates both product IDs and reference names.
It does not establish exact IDs, configured prices, availability, localizations or
review-material completeness. Apple defines Prepare for Submission as created but
not yet submitted for review. The visible banner says the first subscription group
must be submitted with a new app version. Neither fact establishes why the
Production notification API returns 401. No App Store settings were changed and no
additional API request was made after reviewing these screenshots.

## Annual product details, 18:55–18:56 America/Denver

| Field | Observed value and check |
| --- | --- |
| Reference name / product Apple ID | Wrestling Manager Team Pro Annual / `6818669953`. |
| Product ID | `com.damonmele.wrestlingmanager.teampro.annual`; exact match to the native StoreKit product list and server policy. |
| Duration / U.S. price | 1 year upfront / $269.99; matches the agreed annual plan. |
| Availability | All countries or regions selected. Other currencies/regions use different displayed prices; only the U.S. price was compared to the agreed base price. |
| Family Sharing | Off; the page offers Turn On. |
| English (U.S.) display name | Team Pro Annual. |
| English (U.S.) description | Annual Team Pro access for one wrestling team. |
| Optional promotional image | Empty. |
| Purchase options | App Store, Apple Business and Apple School Manager; Multiseat Purchases Allowed. |
| Tax category | Match to parent app; this does not independently confirm the parent's category. |
| Review Information screenshot | Empty. Capture the actual purchase screen from the accepted app with fictional data before submission. |
| Review notes | Blank; prepare useful reviewer navigation after the final device flow is accepted. |

Apple's multiseat option supports purchasing multiple seats and assigning access
to other people. The inspected candidate purchases with an appAccountToken and
binds the subscription to one team; it has no accepted multiseat assignment flow.
Recommendation for the first release: disable multiseat purchases in Purchase
Options and retain App Store availability. Apple Business/School Manager require
multiseat and will be unavailable for this product when it is disabled. This does
not reduce authorized membership within the covered team. No setting was changed
by this screenshot review; obtain confirmation of the saved configuration. Keep
the annual upfront plan and existing Family Sharing setting intact.

The review screenshot and purchase-option work are launch preparation, not an
established explanation for the Production 401. Annual's saved multiseat correction
remains unconfirmed; the later monthly evidence follows.

## Monthly product details, 19:01–19:04 America/Denver

| Field | Observed value and check |
| --- | --- |
| Product Apple ID | `6818671348`. |
| Product ID | `com.damonmele.wrestlingmanager.teampro.monthly`; exact match to the native StoreKit product list and server policy. |
| Duration / U.S. price | 1 month / $75.00; the United States (USD) row is visible in the 19:04:28 screenshot and matches the agreed monthly plan. |
| Availability | All countries or regions selected. Only the U.S. price was compared to the agreed base price. |
| Family Sharing | Off; the page offers Turn On. |
| English (U.S.) display name | Team Pro Monthly. |
| English (U.S.) description | Monthly Team Pro access for one wrestling team. |
| Optional promotional image | Empty. |
| Purchase options | Initially Multiseat Purchases Allowed at 19:01. The 19:04:36 screenshot shows The App Store only and Multiseat Purchases Not Allowed. |
| Tax category | Match to parent app; this does not independently confirm the parent's category. |
| Review Information screenshot | Empty. Capture the actual purchase screen from the accepted app with fictional data before submission. |
| Review notes | Blank and explicitly Optional. Add useful navigation after device acceptance. |

The two 19:04 crops do not include the product title; they follow the owner's
monthly product inspection. They do not establish that annual's purchase options
were also saved. No additional Apple API request, purchase, entitlement change,
release or submission followed this review.

A fresh read-only lookup for `damonmele+wmtest@gmail.com` after this review found
zero Auth accounts and zero confirmed accounts at that checkpoint. The owner
subsequently confirmed the ordinary app account at 19:14 and created **WM Launch
Test** at 19:30. Exact account/team authority was checked and bounded Sandbox
enrollment now expires at 22:00 America/Denver. No purchase or entitlement was
created. See `sandbox-purchase-acceptance.md`; matching web/native preparation
still precedes device purchases.

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

1. Both product IDs, durations, U.S. prices and localizations are checked. Monthly
   now shows App Store only and multiseat Not Allowed; confirm that annual has
   the same saved purchase options. Capture both actual app review screenshots
   during final device acceptance. Agreement, bank and tax status checks are
   complete; trader verification remains In Review. Cloud security-key sign-in
   did not complete. The test account/team and bounded enrollment are now ready;
   complete matching web/native preparation before device purchases as described
   in `sandbox-purchase-acceptance.md`.
2. Correct only an observed mismatch or incomplete requirement. Preserve completed
   banking/tax setup, app identity and the working IAP key. Do not repeat the API
   request without a configuration change or a specific Apple diagnostic request.
3. An unsent support-case draft is in `apple-production-support-draft.md`, now with
   agreement/product status evidence. Sending requires explicit owner
   authorization; no live JWT, private key or customer records belong in the case.
4. Require a verified signed Production TEST and successful delivery before
   marking production authorization complete. Real purchase/restore and benefit
   grant/removal remain separate device acceptance requirements.

## Official sources reviewed

- [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification)
- [Generating JSON Web Tokens for API requests](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests)
- [Creating API keys to authorize API requests](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)
- [Apple commerce engineer response on Production/Sandbox 401](https://developer.apple.com/forums/thread/711801)
- [In-App Purchase statuses](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses)
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
- [In-App Purchase information and review screenshot](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- [Manage subscription purchase options](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-purchase-options-for-auto-renewable-subscriptions)
