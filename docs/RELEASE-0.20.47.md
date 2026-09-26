# 0.20.47 — camera scoring, saved videos and fall results

The private recording test exposed a sticky camera panel that covered scoring controls, a preview that did not follow rotation, and saved videos hidden behind a collapsed section. An unrelated injury-award control also appeared during ordinary NFHS wrestling.

This release adds a full-screen camera workspace with the existing scorer controls over the picture. Red and green/blue scoring stays at the edges; the clock, Stop & save video and Undo remain accessible. Fall / pin stays visible for both wrestlers and opens the existing final-result dialog with that winner and Fall selected. It requires confirmation; cancelling does not finish the match. Additional controls remain in More controls. No scoring engine or point values changed.

NFHS injury-stoppage awards appear only in their eligible injury/HNC timeout. The existing overtime control names its next stage. When the existing NFHS regulation/overtime conditions permit advancing, that same control appears beside the camera clock, beginning with Sudden victory (OT). Custom event rules retain their custom overtime control.

Saved videos is available directly in the scoped Match Book and scoreboard. A successful save opens the current-match replay list and explains that the clip is inside this app. Earlier takes can be found without reopening the original match. Device/team/account ownership and deletion protections remain enforced.

## Native companion

Native source revision 5 is delivered privately in the existing Xcode ZIP. It puts the camera behind the transparent web controls, hides the shell navigation bar while the camera is open, updates preview rotation, and sets the movie's orientation immediately before recording. Choose portrait or either landscape direction before tapping Record; the interface stays in that orientation until the take finalizes. Closing the camera restores the web appearance and normal orientation support.

The web adapter checks a native camera_overlay capability. Earlier native builds retain the compatible bounded preview and receive the saved-video and fall fixes. Install revision 5 to use native camera overlays. Existing movies and account data remain in the same app container; do not uninstall.

Native Swift and package code remain outside this public repository. No Xcode/Apple SDK is available in the development workspace. Swift grammar checks do not establish compilation or physical-device behavior.

## Verification

- 15 synthetic native-message UI groups, including four viewport sizes, real scoring control clicks, fall confirmation/cancellation, saved-video reopening, sudden victory, and injury-only visibility.
- 11 existing native-message compatibility groups were run during implementation; the new capability is opt-in.
- 11 browser MediaRecorder/OPFS groups with actual capture and synthetic media: recording, offline stop, saved replay, restart, account/team isolation, recovery and write failure. Landscape screenshot is synthetic test media.
- 8 existing navigation groups; core score-timeline checks; unchanged shared scorer and Mat Mode; idempotent embedding; 45 inline scripts parse.
- Five video Swift files plus the modified ContentView pass grammar parsing. Physical iOS capture, native layering/rotation, final-file playback and Xcode compilation await device acceptance.

## Test flow

1. Build/run native revision 5 with the existing bundle ID/signing and installed app data.
2. Reopen the app, choose the approved pilot team and personal account, then Locker Room → Match Book · score & record → Test scorebook.
3. Confirm filming permission, Open camera, turn the phone sideways, then Record privately.
4. Start/stop the clock, award/undo points, try Fall / pin and confirm/cancel the result. Use More controls for the remaining scorer actions.
5. Stop & save video, then Saved videos → Replay & export. Close/reopen Match Book and find the same clip under Saved videos on this device. Export important test footage before removing app data.
6. Test both landscape directions and portrait in separate takes. Verify framing, audio, final orientation and replay before wider testing.

No database migration or pilot grant change is required. The existing device-only/test-only pilot remains scoped as previously activated; cloud upload and live streaming remain off. No TestFlight submission, notifications or purchases occurred. Reverting this web release restores the prior UI; existing recordings remain in native storage.
