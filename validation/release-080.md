# v0.20.80 verification

- Removed Arrange tiles and Clipboard customize buttons; all registered movable groups use the existing long-press edit bar, with iOS callout/text-selection suppression and keyboard entry.
- Individual team follows are requested as a personal profile, accepted by team leaders, and separate from team-to-team follows. Existing team-only and follower-team audiences remain unchanged. An explicit all-followers audience and additional parent preference control individual sharing.
- Invitation acceptance only links the existing athlete. Synthetic acceptance verifies that signup identity does not overwrite coach/parent-seeded name, contact, grade or gear.
- Team-profile ordinary details now follow the same profile parent policy. Direct minor updates cannot bypass approval. Name/contact remain protected; stale drafts do not replace newer saved information.
- Open Mat and other event types support daily, selected weekdays, monthly and an inclusive end date. Server expands wall-clock dates with an IANA time zone, preserving 6 PM across daylight-saving changes. Retries return the same batch. Existing weekly practice series retain their season and competition-day behavior.
- Past and upcoming events edit in place. Attendance and RSVP IDs remain attached. Edited generated practice occurrences become individual exceptions. Concurrent stale edits are rejected.

Passed: 53 inline-script syntax checks; release-080 browser checks; Locker Room layout, Clipboard navigation, profile controls and social-079 browser regressions; combined invitation, profile-controls, social-079 and release-080 database rollback suites. Synthetic accounts only; no actual invitations, messages or posts sent.

Shared coach dual-lineup planning remains the next requested feature; it is not part of this release. App Store submission remains pending Apple access and launch requirements.
