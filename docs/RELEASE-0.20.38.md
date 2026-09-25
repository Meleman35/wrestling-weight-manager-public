# Wrestling Manager 0.20.38

Prepared September 25, 2026 UTC for Damon Mele.

## Changes

- Organization → Meetings & minutes: create a meeting, explicitly authorize an adult secretary and optional chair, agenda, roll call, quorum rule/counts, discussion, motions/recorded decisions, action owners/deadlines, start, cancel, and adjourn.
- Drafts are restricted to organization administrators and the assigned meeting secretary/chair. Only the administrator or secretary can edit. Only administrators assign meeting access. A position title or SafeSport entry grants none of these permissions.
- Board adults and affiliate names are snapshotted at creation; multiple positions for the same adult produce one roll entry. Existing directory membership/eligibility reviews remain separate. A quorum threshold requires a recorded governing rule. No 50% default or automatic majority/tie outcome is used.
- Autosave uses the existing authenticated organization RPC. Organization locking, mandatory revision checks and actor/request IDs protect updates and retries. A rejected validation can be corrected; an uncertain response is retried with its original request ID. Saves in progress queue later edits. Errors remain visible. User navigation flushes pending edits or stays on the editor on failure; a conflict offers the saved copy for comparison before an explicit discard/reload.
- Adjournment atomically publishes **UNAPPROVED MINUTES** to users authorized by the existing organization/approved-affiliate access rules. Recording actual approval requires its date, decision reference and confirmation. Corrections require a reason and publish a new unapproved revision. Previous published versions remain intact.
- Executive notes are stored in a separate restricted table. The published minutes projection and version history never include that column. The request log stores a fingerprint/result, not the document or executive text. Audit entries contain action/revision metadata only.
- My profile → **What others see** promotes the existing server-filtered preview into a visible tab. It represents the shared profile seen by other signed-in members; separate restricted team/family permissions are not simulated. Undiscoverable profiles show a private-profile explanation. Owner tools and private family fields are excluded. Preview links cannot reopen owner tools.

## Database deployment

Applied to `vfocpoyexnjsjpxhhyqr`: `20260925001745_organization_meetings_02038.sql`.

Migration SHA256: `deff91c2369a230f098cabff7775d0deb31e47cd042b80ad0614c6e298391e50`.

- Extends `private.organization_meetings` with `workspace`, `approval`, and `minutes_version`; reuses existing attendance and minutes-version tables.
- Adds `private.organization_meeting_confidential` and `private.organization_meeting_requests`.
- Adds the `private.meeting038_*` helpers and guarded request function; routes only `meeting_*` actions through it from the existing organization dispatcher. Existing structure APIs remain available; legacy meeting/voting APIs remain blocked.
- Enables RLS and revokes direct anonymous/authenticated access on all five meeting tables. Helper execution is revoked. The guarded request function is executable only by authenticated callers and checks personal-account eligibility and tenant/record authorization internally.
- Post-migration test transactions rolled back. Database still had 19 positions, 55 affiliates, zero meetings/versions/ballots after testing. No test meeting, membership fixture, notes or profile edits were retained.
- Security advisors: warning counts unchanged (2 anonymous-function findings, 180 authenticated-function findings, 1 leaked-password-protection finding). Five informational RLS-without-policy findings were added for intentionally inaccessible private tables; access is through the guarded RPC, not direct table policies.

## Verification

- 34 JavaScript syntax checks and 34 existing-script preservation checks. Only meeting integration and the intended profile view/handler change; account creation, invitations, staff editor, other permissions, contracts, Mat Mode and native bridge scripts are preserved.
- 22 isolated PostgreSQL/PGlite checks: adult/tenant guards, title-only access denial, restricted draft access, idempotency, stale revisions, complete reload, snapshot integrity, quorum/rule validation, zero-ballot handling, publication, approval/correction history, affiliate revocation, secret-note exclusion and direct-access denial.
- 14 mocked-backend whole-page Chromium checks at tablet and 390px phone widths: meeting creation, save/reopen, offline navigation protection, retries, corrected validation, lost responses, typing during a save, conflicts, adjournment, revisions, reader projection and profile tabs/private fields. Screenshots visually inspected.
- 8 live authenticated SQL checks passed both before deployment in a rollback transaction and after migration; 2 live profile projection checks passed with all test changes rolled back.
- `validation/meetings-source.json`, `meetings-db.json`, `meetings-browser.json`, and `meetings-live.json` contain the results.

## Web release and limits

Baseline: main commit `97a41fe9987555b3c4be6b3d9a047eb877899f8d` (0.20.37), index blob `c0b3492d01aa8cf0fb33b8331ea7b6a7436ac94d`.

0.20.38 index: 5,370,032 bytes; Git blob `37b86675407c53819f7714cec2c48810131bf6e7`; SHA256 `21f80bf6928f9866fb16ac2c46536e71352dc84b3a61fb53e0d060f9e27ae18a`.

Web deployment follows this source commit through the repository's GitHub Pages workflow. Verify the live index against the SHA256 above and check the Actions deployment result. Deployment verification is reported to Damon after publishing.

No Apple binary was uploaded. Actual Safari/TestFlight/device behavior is not yet verified for this release. Background browser/OS termination can interrupt a save; only the visible server-confirmed saved state means persistence is confirmed.

This release records meeting decisions; it does not collect electronic or anonymous ballots. Governing rules/digital-voting authorization still need to be supplied before that later feature. The server uses a row lock for serialization; a live race between two separate production client sessions was not run. School/district and WAWA position/affiliate features from 0.20.36 remain intact. Hosting migration and automated offsite database/media backups remain deferred.

If a web rollback is needed, restore the prior index while preserving this additive database migration and any minutes created after release. Do not drop the new tables or rewrite published versions to roll back the interface.
