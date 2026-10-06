# Apple support case draft — not sent

Agreement and subscription statuses were confirmed in owner screenshots on
October 5. This draft is ready for owner review and contains no private key, JWT,
credentials or customer data. Sending requires explicit owner authorization.

**Subject:** App Store Server API TEST notification returns Production 401 while Sandbox succeeds

We are preparing The Wrestling Manager, app Apple ID `6815511370`, bundle ID
`com.damonmele.wrestlingmanager`. Version 1.0 is Prepare for Submission. We need
to validate Production App Store Server Notifications V2 before enabling paid
customer access.

App Store Connect shows the Paid Apps Agreement Active, effective October 3,
2026–September 18, 2027. The payout bank account and U.S. tax form are also Active.
Digital Services Act trader verification is In Review. The Team Pro subscription
group and both its annual (1 year) and monthly (1 month) products show Prepare for
Submission; neither product has been submitted for review. Both are level 1.

The same deployed service uses Apple's official Node App Store Server Library
3.1.0, the same In-App Purchase key, issuer and bundle configuration for both
environments. App Store Connect shows the key active (key ID ending `P822`,
issuer ending `dd26a549`); its full metadata matches our configured values. The
library constructs fresh ES256 JWTs with the app bundle, issuer,
`appstoreconnect-v1` audience and five-minute expiry. No raw JWT or key is included
in this case.

At `2026-10-05T23:41:57.791860Z`, a request to Production
`POST https://api.storekit.apple.com/inApps/v1/notifications/test` returned
HTTP 401. Our adapter reported no numeric Apple error code and no test token.
Two earlier requests on October 5 also returned 401.

A control request at `2026-10-05T23:42:08.158061Z` to the equivalent Sandbox API
was accepted. We verified Apple's returned signed TEST for this app and Sandbox.
Get Test Notification Status reported SUCCESS on the first delivery attempt at
`2026-10-05T23:42:09.333Z`, notification ID
`c3e67756-7c41-4484-af77-a5da8698e0a5`.

The app's Production and Sandbox notification receiver URLs are both saved and
match our separately configured routes. App ID, case-sensitive bundle ID, key ID
and issuer were checked against owner screenshots on October 5. No private key
was regenerated or revoked. Production payments remain disabled, and no
Production TEST was issued by the failed request.

Please identify whether an app/account authorization condition prevents this
app's Production TEST request, and the supported correction. If further
diagnostics are required, please specify safe request metadata to collect. We
have not established that the unreleased app status causes the 401.

Full public key metadata can be provided privately to Apple if requested. A later
owner screenshot confirms annual product ID
`com.damonmele.wrestlingmanager.teampro.annual`, duration 1 year and U.S. price
$269.99, matching our configuration. The annual review screenshot is still empty;
monthly product details are being checked separately. We do not assume incomplete
review materials explain the Production API authorization failure.
