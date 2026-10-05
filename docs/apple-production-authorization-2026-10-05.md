# Production Apple authorization investigation — October 5, 2026

This read-only continuation does not enable customer payments, publish the web
candidate, install a native build or submit to Apple. Production 401 is unresolved;
no additional Apple TEST request was sent and the closed diagnostic bridge was
not reopened. Keep the working key and environment separation intact.

## Fresh evidence

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

## Next bounded action after owner sign-in

1. Read the existing app `6815511370`, exact bundle
   `com.damonmele.wrestlingmanager`, current version/build, both Team Pro product
   statuses, agreement status and saved Version 2 notification URLs. Preserve
   earlier confirmed banking/tax setup; fix only a newly observed issue.
2. Read the active In-App Purchase key's public metadata and compare key ID
   `79R244P822` and issuer `b5931be7-ac93-4ab3-9b1a-15e1dd26a549` with
   `billing-candidate/apple-server-config.mjs`. Do not retrieve, display,
   regenerate, revoke or copy the `.p8` to diagnose a metadata mismatch.
3. If configuration differs, review the precise correction before applying it.
   If configuration agrees, collect a fresh bounded Production diagnostic
   through an explicitly reviewed private operator path. Retain only status,
   numeric error, time and safe delivery metadata; never log the bearer JWT or
   key. A retry needs a concrete diagnostic purpose; do not simply repeat the
   earlier two requests or reopen an expired bridge indefinitely.
4. If Apple still rejects matching configuration, prepare an Apple support case
   with redacted identifiers, environment, endpoint, library version, timestamps
   and error evidence. Sending it requires explicit owner authorization. Do not
   include a live JWT, private key, banking details or customer records.
5. Require a verified signed Production TEST and successful delivery before
   marking production authorization complete. Real purchase/restore and benefit
   grant/removal remain separate device acceptance requirements.

## Official sources reviewed

- [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification)
- [Generating JSON Web Tokens for API requests](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests)
- [Creating API keys to authorize API requests](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)
- [Apple commerce engineer response on Production/Sandbox 401](https://developer.apple.com/forums/thread/711801)
