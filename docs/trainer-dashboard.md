# Trainer Dashboard — web v0.20.112

A trainer-only team assignment uses a Trainer Dashboard on Home rather than the ordinary team feed. Trainers with coach or linked-family roles retain the normal Home, with an Open Trainer Dashboard shortcut. More also exposes Trainer Dashboard for the current trainer assignment. Team / Family Home returns without signing out. The Assigned Teams selector lists only already-authorized teams with that user's active Team Trainer assignment. The selected team's existing activation and authorization are reused; this does not grant school-wide care access.

The overview counts athletes awaiting trainer review, with recorded activity restrictions, with reviews due, and with missing required baselines. A count is not a diagnosis or a clearance decision. The screen states that baseline completion or an empty concern list does not establish clearance. Cards open the existing Athlete Health roster with the matching filter. Athletes & Baselines and Care Updates lead into the existing permission-checked athlete records. Care Updates is not a new direct-message inbox or a new push notification service.

Only the existing server response identifying both an assigned and accepted trainer can render counts. An assigned trainer who has not accepted sees the existing responsibility-acceptance route instead. A parent/trainer with only family data must not receive trainer counts before acceptance. Server errors render an unavailable message, not fabricated zero totals.

Team Schedule is read only, checks trainer access first, and queries the existing RLS-protected team_events table for the selected team's next twelve events. The visible title, type, start/end and location_name fields were checked against hosted metadata. There are no event writes or organization-wide calendar grants.

Private care notes, photos, guardian choices, provider releases, Sway verification and coach-shared participation updates keep their existing controls. No new health tables, storage rules, permissions, billing gate, medical decision rule or live clinical record is created or modified by this release. No native Swift file or Xcode setting is changed.

Dashboard information is held in memory only and cleared on team/account changes, app lock, background, disconnection, navigating away or opening another sheet. Returning refreshes server access; visible counts are rechecked periodically. Existing health detail views retain their own permission checks. No new offline medical cache is introduced.

Automated verification uses synthetic accounts and records. It covers trainer-only and multi-role homes, assigned-team choices, filtered health navigation, read-only schedule scope, unaccepted/revoked access, late account responses, lock and offline clearing, and phone/tablet widths. Existing athlete-health, Creator and practice-plan tests remain required. Physical Safari/iPhone acceptance is a separate check; passing browser fixtures does not prove a real trainer's device has accepted its role.

Release candidate: publish only after the generated index and service worker both report v0.20.112 and all required PR checks pass. The separately held linked-Creator change in PR 47 is not part of this web-only Trainer Dashboard release.
