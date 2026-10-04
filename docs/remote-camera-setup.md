Remote verification framing includes the athlete's face, singlet, both feet and
the scale in a single image while the athlete is standing on the scale. Place the
scale on a firm, level floor and secure the device far enough away to keep the
complete athlete/scale visible. Use a private area; exclude other athletes from
the frame. The purpose is a director's human review, not body analysis or
automatic identity/clothing verification.

The native candidate requires camera setup before its first scan:
1. The authorized operator opens prepareCamera on the capture host.
2. A full-frame camera preview shows a framing border and instructions.
3. The operator takes a temporary test photo and reviews the actual image.
4. Confirm complete framing, adjust/retake, or cancel. The test photo stays in
   memory, is discarded on completion/cancel, and is never queued or uploaded.
5. New QR/NFC scans are blocked until setup is confirmed. Normal weigh-in photos
   still require fresh stable BLE weight, consent and the allotted window.

Both the camera preview and test-image review use aspect-fit display to prevent
screen cropping from hiding feet or the scale. The existing 1280px normalization
preserves the entire image and strips metadata. Setup instructions are also shown
in the operator's remote reporting screen.

Setup confirmation lasts only for that capture host/session. The app coordinator
must call invalidateCameraSetup when the operator moves/repositions the device or
scale, and offer a visible Recheck camera setup action. Background/lock/logout
closes the host and clears confirmation. A setup test is not accepted evidence.

Status: native candidate, not installed in the live app. The app coordinator must
call prepareCamera before scanning and keep the existing QR/NFC/scale routes.
Physical acceptance needs an iPad/iPhone, scale, an adult test subject in appropriate
athletic clothing, portrait and landscape, cancel/retake, lock during preview and
review, and confirmation that the actual saved frame includes head and feet.
Use test subjects/fixtures for development, not production athlete records.
