# Apple server notification setup

The separate receiver is deployed and the authenticated reconciliation schedule
is active. This step connects App Store Connect to those endpoints; it does not
enable purchases or release the app. Real signed Apple delivery remains unverified.

App: **The Wrestling Manager**, Apple ID **6815511370**, bundle
`com.damonmele.wrestlingmanager`.

In App Store Connect, open the app's App Information and App Store Server
Notifications settings. Configure **Version 2** for both environments:

| Environment | Server URL |
|---|---|
| Production | `https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-apple-notifications/production` |
| Sandbox | `https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-apple-notifications/sandbox` |

Save both URLs. Do not add `/reconcile`: that route is for the private scheduler.
No shared secret, database credential or Apple private key belongs in these URL
fields. Do not share those private values in screenshots or chat.

After saving, use Apple's test-notification API to request a signed TEST delivery
and inspect its delivery status. A test-notification request is an App Store
Server API operation; saving a URL is not proof that Apple delivered a notification.
The receiver already accepts correctly verified TEST notifications without
granting access. The current Render verifier does not yet expose a test-request
operation; add a narrowly authorized operator path before using its server key
for that request, or use an existing authorized Apple API client.

Completed checks:

- Deployed receiver files match the reviewed source exactly.
- Production and Sandbox private scheduler probes each returned HTTP 200, idle.
- Missing worker authorization and browser-origin requests return HTTP 403.
- Non-POST, empty and invalid signed requests cannot create paid access.
- Empty inbox/subscription tables and zero pending deletion jobs after probing.
- Database readiness, account-deletion safeguards and restricted roles remain in place.

Still required: signed Apple TEST delivery, real sandbox purchase/restore and
renewal/refund/expiry acceptance through the native app, plus the remaining core
device checklist. The notification host has no user purchase route.

Apple references checked October 5, 2026:
- [Enter server URLs](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications)
- [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification)
