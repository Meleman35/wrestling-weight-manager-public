# Apple notification delivery checkpoint — October 5, 2026 UTC

## Latest recheck, 23:41–23:43 UTC

Owner screenshots confirmed matching app ID, bundle ID, active IAP key ID, issuer
and receiver URLs. One fresh Production request at 23:41:57 UTC still returned
Apple HTTP 401 with no numeric error code or TEST token. A Sandbox control using
the same live service and credential configuration succeeded: its signed TEST
verified and Apple reported first-attempt SUCCESS at 23:42:09.333 UTC, notification
ID `c3e67756-7c41-4484-af77-a5da8698e0a5`.

The bounded private diagnostic v3 matched five reviewed source files and denied
unauthenticated requests with 403. It was closed immediately as **v4**, restoring
the original 410 handler and gateway JWT verification. Source equality was
verified; the gateway now rejects unauthenticated calls with 401. Readiness remains
true; subscriptions, purchase intents, notification inbox and enrolled accounts
remain zero. All 10 focused diagnostic/connection tests passed.

Production authorization remains blocked. Later owner screenshots confirm the
Paid Apps Agreement Active and both Team Pro products Prepare for Submission;
neither status explains the 401. See `apple-production-authorization-2026-10-05.md` and the
unsent `apple-production-support-draft.md`; no working key was changed.

## Initial checkpoint, 03:50 UTC

The owner saved the Version 2 URLs on October 4 at 9:43 PM America/Denver.

| Check | Result |
|---|---|
| Render deployment | `275daac1ca45229e0e2e680f67239ae9d23b7714`, deployment `dep-db1hsngu01pc73eh8pi0`, live at 03:50:11 UTC. Existing service/plan/credentials reused. |
| Sandbox test request | Apple accepted the authenticated request. |
| Sandbox signed evidence | Apple's actual TEST JWS verified for this app and Sandbox. Notification ID `886cd9a8-4658-4f9a-ac95-5c0ec23d089a`. |
| Sandbox delivery | Apple reports `SUCCESS` on the first attempt at 03:50:40 UTC. |
| Production test request | Apple returned HTTP 401 on both initial and later attempts. No production TEST was issued. |
| Provider health | Render `/health` 200; unauthenticated `/apple` 403; startup log clean. |
| Temporary operator bridge | Five deployed files matched reviewed source. Missing capability returned 403. Replaced by closed 410 handler, version 2 with gateway JWT verification enabled. |
| Customer data | Zero subscriptions, purchase intents and notification inbox rows after testing. |
| Regression checkpoint | All 25 workflows passed at the Render source checkpoint above. |

The new operator commands permit only a test request or test-status lookup, with
bounded input, existing private authentication/concurrency/deadlines, matched
request/environment responses and redacted numeric Apple errors. Status checks
verify the returned TEST JWS and return delivery metadata only, never the raw JWS
or private keys. The temporary Supabase bridge required the private database
scheduler capability and a fixed expiry; it was closed immediately after testing.

Sandbox success proves real Apple API authentication and signed notification
delivery in that environment. It does not prove actual purchase entitlement,
renewal/refund processing, or production readiness. The production 401's cause is
not established. The app has not been released, but that alone is not documented
here as the cause. Do not rotate the working key, reroute production evidence to
Sandbox, or claim production success based on this result. Recheck App Store
Connect app/product/account status and obtain Apple support if needed.

Apple references checked October 5:
- [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification)
- [Get Test Notification Status](https://developer.apple.com/documentation/appstoreserverapi/get-test-notification-status)
- [Check Test Notification Response](https://developer.apple.com/documentation/appstoreserverapi/checktestnotificationresponse)
