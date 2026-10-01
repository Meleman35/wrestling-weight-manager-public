# Linked personal access to the Creator workspace

Status: held development change, not live account linking. No hosted migration, real access grant, billing activation, native build or main-branch publication is performed by the preparation workflow.

The existing dedicated Creator identity remains the owner. One separately reviewed personal Auth identity can be linked privately. That personal account retains normal team onboarding and navigation and opens the same workspace from More → Creator Dashboard or Account & Team → Creator Dashboard. Return to Team closes the dashboard without changing the signed-in account, selected team, season, memberships or staff permissions. The dedicated owner continues to land on its standalone Creator home.

## Server authority

`private.creator_accounts` remains a singleton owner row, with one nullable `linked_user_id`. There is no public link/unlink action, email allowlist, signup hook, role-based self-enrollment or client override. Provisioning requires operator review of the exact confirmed personal Auth identities. No real identifiers are embedded in source, migrations or tests.

Every operation checks the current grant, confirmed/non-banned/non-deleted actor, live session, owner account status, managed-login exclusions and deletion freezes. Both logins serialize changes on the same workspace row. Older clients are denied linked access unless they use the new navigation protocol; the protocol itself does not grant authority. The original owner remains backward compatible.

Existing drafts remain anchored to the owner. The existing `created_by` field serves as the legacy owner field; successful mutations record the actual authenticated login separately in `creator_offer_events.actor_id`. Both authorized logins see shared drafts and trial settings. Revision checks and identical-create retry handling remain in place. Audit display labels distinguish this login, the owner and the linked personal login without exposing account identifiers.

The new access gives no additional team, athlete, medical, weight-history or message access. All drafts remain unredeemable and all trial settings remain awaiting billing. Family Video, Team Pro, practice-plan coverage and tester grants are unchanged.

## Account deletion and coordinated release

The linked identity is a foreign key with ON DELETE SET NULL. Deleting or unlinking the personal identity preserves the Creator owner and owner-held drafts; its own audit rows follow the existing personal deletion policy. Deleting the owner removes its workspace and owned drafts, but does not delete the linked personal identity.

The actual deletion planner needs the reviewed `private.creator_accounts.linked_user_id` nullable edge in its deployed worker policy. Do not activate the link with an old worker policy. The structural catalog and athlete-merge fingerprint must be refreshed together; unknown schema drift and pending deletion jobs block the migration.

Before release: refresh main and the live catalog; finish automated and browser checks; deploy the coordinated schema/function and worker-policy update without starting a deletion; record the tool-generated migration version in source control; bump the web/service-worker release together; publish and verify the resulting files; then provision only the privately reviewed identities and verify both access modes. Never enroll either real account in a deletion pilot. Physical phone acceptance remains separate from browser tests.

## Verification

`python3 scripts/prepare-creator-linked-access.py` generates the SQL, source embedding, reviewed deletion-policy edge and compatibility test. `--check` verifies consistency. The branch-only preparation workflow runs the existing Creator tests, new linked-access database/browser tests, the reconstructed-schema deletion/merge compatibility test, and existing athlete-health/practice-plan regression tests before materializing generated source on the development branch. Pull-request checks are read-only.

All automated account, health, offer and team data are synthetic. The tests do not connect to hosted Supabase, send email, create real accounts, or prove physical-device behavior.

The Trainer Dashboard proposal in `docs/trainer-dashboard-proposal.md` is separate design work; it is not implemented by this Creator change.
