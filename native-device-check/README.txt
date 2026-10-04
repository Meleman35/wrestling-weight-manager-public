REMOTE SCALE CHECK — BUILD 6

Continuous local camera + American Scale test. Nothing is uploaded, charged,
or saved to the Photos library. Automatic mode keeps only the latest test photo. NFC mode keeps the lowest
result and matching photo per test card (up to 20 cards / 20 MiB total).
Your Wrestling Manager app and athlete records are not used.

INSTALL
1. Extract this ZIP into a fresh folder and open
   native-device-check/RemoteScaleCheck.xcodeproj directly.
   Do not drag the files into another Xcode project.
2. Select RemoteScaleCheck and your physical iPhone or team iPad. Keep your
   existing developer team and the separate .remotescalecheck bundle identifier.
3. Product > Run (Debug). Confirm Build 6 on the home screen.

TEST A CONTINUOUS SESSION WITHOUT NFC
1. Connect the American Scale, tap Done, and open camera & scale check.
2. Check camera setup once. Use an adult in athletic clothing; confirm the
   whole person, both feet and scale are visible. Keep the camera/scale fixed.
3. Tap Start continuous test. Step on and hold still. The camera shows settling
   progress and takes the photo AS SOON AS THE WEIGHT IS STABLE.
   There is no additional countdown.
4. Wait for "Photo complete — step off the scale." Step off fully.
5. With NFC mode OFF, after one fresh empty-scale response the camera opens for Test athlete 2
   automatically. Step on again. No Done tap or setup repeat is needed.
6. Repeat a third time. Each attempt has a new fictional athlete/capture ID.

Capture still requires three fresh readings over at least one second within
0.2 lb; movement resets this stability check. Near-zero drift up to 1 lb is treated
as an empty scale, never as an athlete's weight. If it seems slow, report the
elapsed seconds and settling progress shown at the top. Hold still through
"Taking photo" until the success message appears.

TEST NFC CARDS AND REWEIGHS
1. Connect the American Scale and your GoToTags / ACS NFC reader on the home
   screen, then enable "Use NFC cards for this test".
2. Use an existing programmed Wrestling Manager athlete card. This test reads
   only; it never writes a card or looks up a real athlete profile.
3. Check framing once and start. Remove any card left on the reader, then tap
   when prompted. Cards become numbered fictional test athletes for this session.
4. Step on, wait for the photo, then step off. After the scale is empty the app
   prompts for the next card automatically. No Done or repeated setup is needed.
5. Tap the same card for another attempt. A lower stable weight replaces that
   card's selected result/photo. An equal or higher weight keeps the prior result.
6. A different card gets its own result. Start a new session to clear the local
   card mapping and results. Closing/backgrounding clears everything.

No body-weight change is needed to test replacement: use safely placed test
objects of different weights on the platform, with the camera showing the test.
Tournament rules and server authorization are not exercised by this local test.

SCALE UPDATE CHANGE
Live notifications remain available while weight changes. If the scale goes
quiet, the app requests fresh readings. A metadata/partial response restores
live notifications instead of keeping them disabled through a weight-update gap.
The three-reading / one-second stability check is unchanged. If a delay remains,
report the status text and elapsed time; the camera screen now also shows the
transport status when weight updates pause.

CONTROLS
- Cancel in the camera ends the session while retaining camera setup.
- End test session keeps the setup and the latest preview until cleared.
- Clear test photo and setup removes the preview and requires new setup.
- Recheck setup after physically moving the camera or scale.
- Closing/backgrounding clears pictures and setup. The test session lasts five
  minutes; start a new one from the same check screen to retain setup.

CHECKS
- Stay on the scale after a photo: it must not make a second capture.
- Step off before the weight stabilizes: no photo should be taken.
- Turn off the scale before capture: the session must stop without a photo.
- Background or close the screen: pictures/setup clear; reads stop.

This isolated test automatically numbers fictional athletes. Production QR/NFC
scanning must resolve actual authorized roster athletes; it is not exercised
here. Server submissions, receipts, offline delivery and exports are separate
integration checks. Tell us whether three consecutive attempts work and how
long the photo takes after the weight becomes stable. Status text is enough.
