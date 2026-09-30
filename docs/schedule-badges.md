# Schedule badge baseline — v0.20.94

Damon reported that the installed Mac app showed 74 Schedule alerts when signing in on a new device or switching teams, matching the existing practice dates. This focused correction does not change events, practice recurrence, native code, billing, video access or the separate account-deletion draft.

## Cause and correction

The old `navSeenAt('schedule')` returned zero when its account/team localStorage key was missing. `updateBottomNavBadges()` then counted every returned event whose updated/created timestamp was greater than zero. A first device/team load therefore treated an existing season as new. The old loader also captured `opsTeamId` only after awaiting the team-events query, allowing an old team's response to be associated with a newly selected team.

`src/schedule-badges.js` now establishes the existing numeric account/team marker from the latest timestamp in the first successful current schedule response. It does not initialize from an empty loading placeholder or a failed request. A successfully loaded empty schedule stores an explicit zero so a later event can still count. Valid preexisting markers are preserved, not bulk-cleared. Subsequent rows newer than that marker still count, including practice changes. Opening Schedule acknowledges loaded timestamps rather than a device-clock time. A response completing while Schedule is visible is acknowledged; background refreshes do not continually mark changes read.

Each load captures account, team, season and a request generation before either asynchronous query. Invalidated, superseded, old-team and old-account responses/errors cannot replace the current schedule or update its baseline. Activation and account changes reset the in-memory snapshot and clear the displayed Schedule count while the new schedule loads.

## Boundaries

This remains a device-local last-viewed indicator using `wm_nav_seen_schedule_<account>_<team>`. It does not introduce server-backed schedule read-state synchronization between phones and Macs. A fresh device begins quietly from its available initial schedule. The existing message/notification synchronization remains unchanged.

Only the existing numeric marker is persisted; no event titles, event lists or new account-linkage keys are stored. If persistence fails, a memory-only fallback keeps this badge usable for the current page session. Restarting without persistent storage necessarily creates a new initial baseline. The legacy timestamp-based indicator counts available rows with newer `updated_at`/`created_at` values; it is not a durable change log and does not add deleted-event/cancellation notifications or recover history that the server did not return. Existing organization-calendar fallback behavior is unchanged.

The component is embedded in `index.html`, not downloaded as an additional runtime dependency. `sw.js` changes only its shell version. No service-worker data purge, app uninstall, native project replacement or clearing of drafts/videos is needed. A cached older shell can continue showing the old behavior until it updates.

## Verification

- `python3 scripts/patch-schedule-badges.py --check` verifies the exact committed embedding and version. Without `--check`, this is an idempotent local packaging command, not deployment.
- `node tests/schedule-badges.cjs` runs 17 synthetic groups against the exact component and actual embedded `loadSchedule`, including the old 74-event negative control, first/fresh-device baselines, legacy markers, genuine newer rows, team/account/season switching, overlapping responses, failed loads, visibility, localStorage failures, and inline-script syntax.
- `NODE_PATH=.ci/node_modules node tests/schedule-badges-browser.cjs` runs six actual bundled-UI Chromium groups at desktop and phone widths with synthetic API replies and no production writes. It checks the rendered badge, real Schedule-button acknowledgement, reload, team changes and a delayed response.
- The dedicated final regression workflow is read-only. During preparation, a temporary branch-only packaging step committed only the generated index and worker after the focused tests passed; that write step was removed before review. PR checks independently retest the committed bundle.

The initial focused run was 36648897890. Use PR checks for final-head status; a historical successful run is not a substitute. Existing parent, reviewer/messaging and offline suites also need to pass before release. Automated browser tests do not establish installed Mac/iPhone/iPad acceptance.

## Installed-app acceptance

After the app has loaded web build v0.20.94, use existing authorized accounts and do not alter a real schedule just for this test. Confirm that a first team/device load and team A → B → A do not show the whole existing season as alerts, that all practice dates remain on Schedule, and that opening Schedule clears its actual pending change count. Verify a genuine edit/new-event alert later using an explicitly authorized synthetic test team. Do not merge or activate account deletion as part of this fix.
