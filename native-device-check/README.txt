REMOTE SCALE CHECK — SEPARATE DEVELOPMENT APP

This installs a separate app named Remote Scale Check. It does not replace
The Wrestling Manager, sign into your account, upload, charge, or save photos.
It uses the same camera/capture models and American Scale BLE code as the draft.

1. Open native-device-check/RemoteScaleCheck.xcodeproj.
2. Select the RemoteScaleCheck scheme and your iPhone or team iPad.
3. Under Signing & Capabilities, select your existing Apple developer team
   if Xcode asks. Keep the separate .remotescalecheck bundle identifier.
4. Choose Product > Run (Debug). Do not Archive or submit this test app.
5. Tap Connect American Scale, connect it, then Done.
6. Open camera & scale check. Take a setup test picture with an adult subject
   in athletic clothing. Confirm face, singlet, both feet and scale are visible.
7. Start a test weigh-in, step on and stand still. The photo takes after a
   continuous stable countdown. Confirm the displayed pounds and full frame.

TRY THESE ONCE
- Portrait and landscape on the iPad, and at least one iPhone capture.
- Setup cancel, adjust/retake and confirm.
- Step off during the countdown: it should reset until stable again.
- Disconnect the scale: it must not produce a successful stale-weight capture.
- Background the app during the camera view: pictures/setup must clear.
- Clear the test: picture disappears; setup is required again.

Use an adult test subject; this is not a tournament or real athlete workflow.
The fictional athlete bypasses credential lookup only in this isolated test.
QR/NFC resolution, account authorization, offline uploads, server acceptance,
billing and director exports are separate integration checks.

Share only whether these checks pass and the first failure. You do not need to
send photos of an athlete. Keep your working Wrestling Manager project intact.
