# Compact notification header — 0.20.117 candidate

The owner reported that the new full Notifications button crowds the team name on iPhone. This change uses a 44-pixel bell beside Account, moves the existing unread badge onto the bell, and restores the width previously reserved beside the team switcher. The inbox, notification recipients, private/shared health permissions, read behavior and destinations are unchanged. Health and Board Room keep their labeled notification entrypoints.

Source/embedding checks run with `python3 scripts/prepare-notification-header.py --check`. The synthetic browser test checks 320, 390, 430 and 768 widths, zero/single/99+ unread states, keyboard access, independent team selection and the existing care destination/access regressions. Run results, PR merge and hosted publication require separate verification; this document alone is not proof of passing or deployment.

## Separate deletion question

The current account-deletion UI is pilot-gated: a response with enabled other than true removes the card; a failed initial capability read also leaves it hidden. General activation has not been completed by this header change. The expected admitted-account location remains My Account, after Sign Out. The reported absence is not proof that the uploaded binary is wrong or that the account is enrolled. No live account, tester enrollment, native bridge, server capability, role, safety check, deletion request or stored record is changed here.

Apple's public-release requirement remains separate: apps supporting account creation must provide an easy-to-find in-app way to initiate deletion. Do not claim release readiness from one disposable-account result, and do not enroll the owner's real or Creator account to make the button appear. The native version/build still needs actual TestFlight-screen evidence; a Locker Room screenshot does not establish it.
