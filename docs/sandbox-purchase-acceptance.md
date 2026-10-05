# Sandbox purchase acceptance preparation

The app billing endpoint is deployed in **Sandbox only**. No account is enrolled,
and production purchases remain disabled. The endpoint has no request-selectable
production mode and accepts only verified Apple Sandbox subscription evidence.

## Selected test identity; creation pending

The October 5 master handoff already selects the dedicated personal app login
`damonmele+wmtest@gmail.com`, Coach / Team Leader role, and fictional team
**WM Launch Test**. A read-only Auth lookup on October 5 found no account at that
exact email; account creation and team authority are not yet established. Do not
ask the owner to choose the identity again. The owner must complete ordinary
account creation and email confirmation without sending passwords or codes to
chat. Then the operator must resolve the actual account/team IDs and verify
current authority before adding short-lived, exact-team server enrollment.
Do not create an account through an administrative bypass or enroll a real team.
This does not create an Apple Sandbox Apple Account; that separate Apple account
may be needed on the device.

Use a dedicated app account because the first Team Pro purchase binds its
purchaser to one team, including future restores. Sandbox acceptance records
must not accidentally bind an ordinary purchaser to a disposable test team.

Enrollment uses server-managed `auth.users.raw_app_meta_data.wm_billing_sandbox`
with an exact team UUID list and millisecond expiry. Clients cannot set it using
profile fields, JWT claims or request parameters. Enrollment grants no paid
benefit on its own. It is checked again after Apple waits and inside billing
transactions, including against the stored team on restore.

## Build and device round

Use the current main app candidate in `native-app/Wrestling Manager Xcode App.xcodeproj`,
scheme `Wrestling Manager`, version 1.0 (9), after its current CI passes. Keep the
normal scheme's StoreKit Configuration unset for Apple's real Sandbox. The
separate Local StoreKit simulation is not accepted by this hosted service.

The candidate requires the server capability's environment to match StoreKit's
verified `AppTransaction.shared` environment and bundle ID before configuring the
purchase bridge. A production app or Xcode-local transaction cannot activate this
sandbox-only route. Older native activation code rejects the new capability
shape, so it fails closed until updated. This device behavior still needs actual
acceptance; SDK compilation is not proof of a working device flow.

Once enrollment, the matching web candidate and native build are ready, use the
single checklist in `launch-acceptance-batch.md`: Apple product/pricing loading,
cancel/pending/completed purchase, restart/network recovery, restore, account and
team isolation, refund/expiry removal, protected practice/statistics behavior and
existing core app checks. Use fictional records and designated test accounts.

After testing, remove enrollment and use the reviewed deletion/cleanup workflow
for disposable records. Do not alter real customer subscriptions or bypass
immutable purchase bindings. Production activation remains a separate verified
release step, blocked while the production API returns 401.

Apple references:
- [App transaction environment](https://developer.apple.com/documentation/storekit/apptransaction/environment)
- [Sandbox and TestFlight testing](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)
