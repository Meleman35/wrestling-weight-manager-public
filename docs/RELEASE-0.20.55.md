# Web 0.20.55 — completed-match video controls

An iPhone recording showed a previously completed test scorebook with “Saved result: Fall,” no active camera, and Saved videos (0) for the currently selected account and team. The result and stop buttons appeared actionable even though neither operation was available in that state.

The completed match now labels its disabled Finish match action “Result recorded.” When no recording is active, the native Stop & save button is hidden. Disabled video buttons use a visibly muted style. The recording panel is hidden on a completed match after recording ends; an active recording remains accessible to Stop & save even if the result is finalized during the take. Saved videos remains available from Match Book.

This is a presentation change. It neither deletes nor migrates footage, changes account/team scoping, or alters native recording and save behavior. Zero takes on one account/team does not establish whether an earlier take exists under another scope or an earlier web origin. Do not clear app storage or uninstall while investigating it.

Verification: all 47 inline scripts parse, video-pilot-core tests pass, diff whitespace check passes. Physical-device control states and any earlier video recovery remain to be checked.
