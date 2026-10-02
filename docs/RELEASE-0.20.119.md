# Web update status — 0.20.119

My Account now has App updates and Check for updates. It checks only the same-origin public service-worker version with no credentials or cache reuse. Newer versions advise saving work, finishing recording/sync and closing all app windows/tabs before reopening. It distinguishes web versions from Apple-native builds. It never reloads a page, activates a waiting worker, clears app data or starts an account operation.

Offline, failed, older, malformed and timed-out responses do not claim the app is current. Checks stop on account-sheet closure, background and page exit; late replies cannot replace the current status. There is no new polling loop, remote telemetry, push notice or backend change. A cached screen from before this release cannot show this newly added control until it has loaded the release once. This feature reports version availability, not native build identity or deployment/acceptance of every feature.

Automated validation uses the full embedded app with synthetic responses and a separate timeout/lifecycle harness. It checks current/newer/older status, version ordering, retry/offline/error, malformed responses, cancellation, preserved typed input/drafts and narrow layouts. Physical iPhone acceptance and general deletion activation remain separate release gates.
