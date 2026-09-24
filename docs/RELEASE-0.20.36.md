# Wrestling Manager 0.20.36 — organization structure

The 0.20.35 navigation upload was verified in GitHub main commit 07ab1fe754e4397226c50d37339eb28ec9b012a4 and on the live Pages site. Both matched SHA-256 a703ee1ad1b27cd1876be000d63c8d537ac26f0675691f76a8185d8d406079a4.

## Shipped scope

Clipboard → Organization now includes Positions and Affiliate directory. Positions support vacant/custom posts, WAWA/association/club/school/district templates, multiple adult appointments, reporting hierarchy, division scope and explicit existing operations access presets. Titles do not grant access. Existing organization administrators manage assignments. New adult assignments require administrator attestation; known minor, unknown-age athlete, shared-device and unrelated accounts are rejected. This is an administrator attestation, not external identity/age verification. Athlete-representative posts remain unassignable.

Affiliates support add/edit/archive/reactivate, separate membership and voting review, administrator-only contact fields, explicit existing team/organization links, immutable revisions and recorded rule notes. Reactivation resets review. Directory links do not create team management, membership or roster access. Team links must already be managed or approved; organization links are limited to other organizations the actor administers. Other organizations can continue using the existing approved team-affiliation flow.

## Important correction to the prior handoff

Live inspection found an earlier governance migration already deployed: 19 positions, one adult assignment, and 55 directory entries. All 55 entries had been marked eligible by default. No meetings or ballots existed. This release preserved all entity IDs and the existing adult assignment, captured baselines, made the directory unreviewed and ineligible pending explicit review, and disabled the incomplete meeting/delegate/voting entrypoints. Existing position access assignments were not automatically expanded.

## Database migration

- Source: supabase/migrations/20260924191649_organization_structure_02036.sql (created by Supabase CLI; timestamp aligned with the applied server migration).
- Applied migration: 20260924191649, name organization_structure_02036, project vfocpoyexnjsjpxhhyqr.
- SQL SHA-256: 2aaa6e1be0046cd6017d6ab371d2d8d62dcab74080724818b5a3470f01c91519.
- Extends private.organization_positions and private.organization_affiliates.
- Adds private.organization_structure_versions and private.organization_structure_requests.
- Adds private.gov_adult_candidate, gov_structure_context and gov_structure_v2; replaces the existing organization_governance dispatcher and gov_can_manage_structure authority check.
- Public API name and p_request argument remain unchanged. Anonymous execution and legacy helper execution are revoked. Private tables deny direct application-role access; authenticated calls go through the checked private implementation.
- Each write requires a UUID request identifier; replaying identical content returns the same result. Altered-payload replay is rejected. Organization row locks serialize mutations; existing-record writes require the expected revision.

## Validation

- 33 inline JavaScript syntax checks; 4 preservation checks (37 total).
- 22 isolated PostgreSQL/PGlite test scenarios, including permissions, tenant boundaries, adult guards, hierarchy cycles, stale revisions, archive/reactivation, history and replay.
- 14 complete-page Chromium checks with an isolated mocked backend, including 390px phone / 1024px tablet, retry preservation, late responses, escaped content and retained navigation.
- Anonymous REST call denied with HTTP 401.
- 13 checks against the deployed authenticated public RPC with all temporary rows and audit/request/history records rolled back.
- Postflight counts: 19 positions, one assignment, 55 unreviewed affiliates, 131 baseline/revision snapshots, zero saved test requests, zero meetings and ballots.
- Security advisors: no new WARN findings. Four new INFO notices are the intentional RLS-with-no-policy private tables, accessible only through checked functions. Existing warnings are outside this slice. [Advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

No real Apple/Safari/TestFlight device test or simultaneous independent database-session race test was performed. The stale-write and replay paths were exercised; full multi-session ballot concurrency remains a future release gate. No Apple binary was built or uploaded. Mat Mode, invitation/email code, contract records/signatures, native bridges and unrelated scripts were preserved.

## Next slice

Meeting workspace and secret ballots remain unavailable until the explicit governing-rule configuration, electorate snapshots, secretary/minutes permissions, confidential projections and concurrency/secrecy tests from the handoff are implemented. The legacy meeting functions remain as inaccessible implementation material, not a production voting system.

## Rollback

Restore the 0.20.35 index.html to remove the new screens if needed. Keep the additive schema, review markers and history; do not re-enable the old governance dispatcher or infer eligibility from the historical directory. A database rollback requires a reviewed forward migration, especially after genuine edits begin.

