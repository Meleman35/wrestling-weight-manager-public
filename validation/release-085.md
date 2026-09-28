# v0.20.85 verification

Base: commit 5a1cd63ea15b498aa549ff83ac216b5c5040a8db; supplied HTML matched Git blob cedd0270f17fd7a562e06598e9d9133d420d9770 exactly.

- Fixed roster identity; controls scroll independently. Approved photo / initials, class, latest weight, certification and existing profile/access/transfer/status actions retained.
- Numeric lineup-class sorting; missing classes last; name tie-break. Standby/Removed remains collapsed, with existing non-destructive reactivation.
- Competition eligibility is private, seasonal, coach-controlled and separate from roster status. It filters the competition roster, coach lineup board and competition RSVP list. It does not revoke team or family membership or prevent recording historical matches. No eligibility reasons are collected. This is a manual coach tool, not an AD integration or universal tournament authorization gate.
- Attendance tab in Locker Room and team athlete profiles. Practice/Duals/Tournaments defaults; configurable team categories, excused treatment and Modified treatment. Reads completed, attendance-enabled, season-counting Schedule events. Present/Late count as attended; Modified defaults to attended; excused defaults to excluded; unmarked excludes rather than treating missing records as absences. Overall is total attended / counted events, not an average of category percentages. Group events enter an individual's totals only with recorded attendance. Staff can use existing event attendance controls.
- Saved locations are team-scoped, shared between creation and editing, removable without altering existing events.
- Event edit defaults to this occurrence. Upcoming events can repeat daily/weekly/monthly, change future recurrence, or stop future repeats. Preview and confirmation required; original event ID and child records remain. Untouched future siblings can be replaced; ANY FK child record blocks replacement. Past and individually edited events remain. Concurrent event/sibling changes and repeat-save retries are guarded. Changing a legacy weekly practice generator to these repeat rules creates a fixed date set; competition-day skipping is not automatic for that new set, and the form explicitly says to review conflicts. Existing weekly practice creation remains unchanged.

Verification passed:
- 57 inline-script syntax checks.
- release-085 browser checks at 320, 390 and 768 px: scroll geometry, numeric sorting, inactive/eligibility sections, attendance arithmetic/UI, favorite filling, repeat preview/save.
- release-080 browser regression: follow flow, existing repeat creation, retry IDs, daily/monthly previews and past-event edits.
- Transactional synthetic database tests: eligibility concurrency/access/history, attendance configuration/self/guardian/stranger access, favorites, repeat conversion/stop/retry and saved-record protection. Every synthetic mutation rolled back.
- Full release-080 database rollback regression with the proposed schema: profile approval, parent controls, invitations/profile identity, follows, repeat dates/DST and event-history preservation.
- All existing script blocks except main application integration and eventEdit080Script remain byte-for-byte identical to v0.20.80. Native bridge, scoring, guardian messaging and recorder modules are unchanged.

Screenshots visually reviewed. Actual iPhone/TestFlight interaction, native BLE/scale/offline recording and third-party calendar subscription clients were not exercised in this environment.

Security advisor preflight showed existing broad legacy SECURITY DEFINER exposure warnings and disabled leaked-password protection. No unrelated security migrations applied. New tables use private schema, RLS and no direct client grants; authenticated invoker wrappers call scoped private functions. Authorization enforced server-side, not just in the UI.

Deployment status (September 28, 2026): the three backward-compatible database migrations were applied successfully, and the synthetic rollback suites passed again against the installed functions. Advisor comparison found only the four intentional private/RLS/no-direct-access tables as new informational notices; no new exposed SECURITY DEFINER warnings. Automatic approval review blocked publishing to `main` pending explicit end-user approval. The live site was checked and still reports v0.20.80. Candidate is prepared on `codex/roster-attendance-085`; do not describe v0.20.85 as live until a separately authorized publish is verified.
