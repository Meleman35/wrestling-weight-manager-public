# Manual athlete merge

Team administrators can open Roster → Merge duplicate athletes, choose the established profile to keep and the duplicate to combine, review record counts, and type `merge` to confirm. This is administrative cleanup available independently of paid statistics. Nothing merges automatically from matching names.

The server verifies a confirmed personal administrator account and authorization for every linked team. Both entries must belong to the selected team and organization. It preserves the chosen athlete name, fills compatible missing fields, retains the stricter sharing flags, moves all inventoried athlete foreign keys, and rewrites exact athlete-ID references in mutable scorebooks and operational JSON. Media paths and signed/audit history remain unchanged. Scorebook revisions advance. Overlapping seasons keep the primary profile's roster settings; other season memberships move. Athlete and family sign-in accounts are never deleted.

Preview fingerprints cover both athlete rows and related records. Commit rechecks authority, takes locks, validates that fingerprint and performs one transaction. A committed audit receipt makes a same-request retry safe after connection loss. Any error rolls back the entire merge. No real athlete was merged during development.

## Cases that require review

This first release handles compatible duplicate roster profiles. It deliberately blocks cross-organization identity consolidation, a duplicate identity already shared by additional athlete rows, conflicting birthdays/contact/profile values, separate sign-in accounts, two records for the same attendance/consent/other unique item, pending parent approvals, established duplicate social/family histories, managed/test accounts and athletes appearing as opponents. It does not delete or overwrite those records to force completion. The user can choose the established profile as primary; complex identity conflicts still require a coordinated support review.

Only the supported schema inventory is accepted. A schema change pauses merges until its relationships are reviewed and the compatibility fingerprint is updated. The release adds functions only and does not change the account-deletion inventory. Internal helpers are not client executable; the authenticated wrapper always checks authority.

Merges require an online session. Pending offline operations on the requesting device must sync first. Other devices should refresh and redownload their team before adding more work; this feature does not rewrite an offline device's pending drafts. Existing family-role verification can be invalidated by the normal membership-change triggers and may need review again.

## Verification

`tests/athlete-merge-db.mjs` reconstructs the full application schema, real constraints/indexes and relevant profile/permission mutation triggers in isolated PGlite. It checks record preservation, authority, typed confirmation, stale reviews, retries, conflicting identities/attendance, established social records, family account preservation, full rollback and schema drift. `tests/athlete-merge-browser.cjs` checks phone layouts, selection/review/confirmation, blocked cases and account-switch races with synthetic records. Never use a real athlete as a destructive test fixture.
