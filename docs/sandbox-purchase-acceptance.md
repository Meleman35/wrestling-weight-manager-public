# Sandbox purchase acceptance preparation

The app billing endpoint is deployed in **Sandbox only**. The dedicated account
and exact fictional team have a bounded enrollment ending October 5 at 22:00
America/Denver (October 6 at 04:00 UTC). Production purchases remain disabled.
The endpoint has no request-selectable
production mode and accepts only verified Apple Sandbox subscription evidence.

## Selected test identity; verified and temporarily enrolled

The October 5 master handoff already selects the dedicated personal app login
`damonmele+wmtest@gmail.com`, Coach / Team Leader role, and fictional team
**WM Launch Test**, under **WM Test Organization**. The owner completed ordinary
account creation and email confirmation at 19:14 on October 5, then created the
team at 19:30. Exact Auth and team IDs were resolved privately; the account has
an active head-coach membership, current sessions and purchase authority. It is a
personal, confirmed, nonanonymous account with no ban, deletion or minor-account
restriction. No account or role was created through an administrative bypass.

The operator enrolled only that exact account/team pair until **October 5, 2026
22:00 America/Denver / October 6 04:00 UTC**, preserving other app metadata.
The mutation locked and rechecked account, team and head-coach membership,
confirmed a current session, and required live billing readiness and purchase
authority. A separate postcheck confirmed exact-team enrollment true, unrelated
team false, purchase authority true and billing readiness true. There is exactly
one enrolled account; subscriptions, purchase intents and immutable team bindings
remain zero. These are database-policy checks, not a real authenticated device
purchase or a paid benefit grant. Do not publish exact identity UUIDs or credentials
in this repository. Remove the enrollment after testing; expiry also denies access
automatically. Any extension must recheck the same identity and authority.

Do not ask the owner to recreate this account/team or enroll a real team.
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

All 26 GitHub workflows passed at PR #62 head
`ac79e309b5cdb68d32e4f7d286c5831d2db29e85`, including the full native Debug/Release
simulator build job. This is the inspected head, not a claim about later commits.
Main remains `4a5ec6c429740b56e9e5da7219ed0b254f3e31e3` / web 0.20.122; PR #62
is draft and unmerged. The matching web/cache 0.20.123 must be published and native
1.0 (9) installed before the purchase round. No public publish, native installation,
App Store submission or new Production TEST occurred during enrollment.

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
