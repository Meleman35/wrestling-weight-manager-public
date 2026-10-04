REMOTE SCALE CHECK — BUILD 4

Continuous local camera + American Scale test. Nothing is uploaded, charged,
or saved to the Photos library. Only the latest test photo is held in memory.
Your Wrestling Manager app and athlete records are not used.

INSTALL
1. Extract this ZIP into a fresh folder and open
   native-device-check/RemoteScaleCheck.xcodeproj directly.
   Do not drag the files into another Xcode project.
2. Select RemoteScaleCheck and your physical iPhone or team iPad. Keep your
   existing developer team and the separate .remotescalecheck bundle identifier.
3. Product > Run (Debug). Confirm Build 4 on the home screen.

TEST A CONTINUOUS SESSION
1. Connect the American Scale, tap Done, and open camera & scale check.
2. Check camera setup once. Use an adult in athletic clothing; confirm the
   whole person, both feet and scale are visible. Keep the camera/scale fixed.
3. Tap Start continuous test. Step on and hold still. The camera shows settling
   progress followed by a TWO-SECOND countdown once the weight is stable.
4. Wait for "Photo complete — step off the scale." Step off fully.
5. After two fresh empty-scale readings, the camera opens for Test athlete 2
   automatically. Step on again. No Done tap or setup repeat is needed.
6. Repeat a third time. Each attempt has a new fictional athlete/capture ID.

Capture still requires three fresh readings over at least one second within
0.2 lb; movement resets the countdown. Near-zero drift up to 1 lb is treated
as an empty scale, never as an athlete's weight. If it seems slow, report the
elapsed seconds and settling progress shown at the top. Hold still through
"Taking photo" until the success message appears.

CONTROLS
- Cancel in the camera ends the session while retaining camera setup.
- End test session keeps the setup and the latest preview until cleared.
- Clear test photo and setup removes the preview and requires new setup.
- Recheck setup after physically moving the camera or scale.
- Closing/backgrounding clears pictures and setup. The test session lasts five
  minutes; start a new one from the same check screen to retain setup.

CHECKS
- Stay on the scale after a photo: it must not make a second capture.
- Step off during the countdown: the countdown must reset.
- Turn off the scale during a countdown: the session must stop without a capture.
- Background or close the screen: pictures/setup clear; reads stop.

This isolated test automatically numbers fictional athletes. Production QR/NFC
scanning must resolve actual authorized roster athletes; it is not exercised
here. Server submissions, receipts, offline delivery and exports are separate
integration checks. Tell us whether three consecutive attempts work and how
long the photo takes after the weight becomes stable. Status text is enough.
