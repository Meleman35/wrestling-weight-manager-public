# Care notifications — deployment evidence and remaining acceptance

## Backend installation

The authorized Supabase migration action returned `success: true` for `health_update_notifications_020116`. A separate `list_migrations` call returned the provider-generated version **20261002011334** with that name. The matching file in `supabase/migrations/` reuses the exact blob from `supabase/health-notifications.sql`, not a manually reconstructed migration. Its SHA-256 is `175211ad117f55682e3070d3cb50a13fe2e6c6556ec5ad737d4b341f08f8c02a`.

The final read-only preflight at **2026-10-02 01:11:50 UTC** found the reviewed original health/router function fingerprints, matching deletion catalog, no pending deletion jobs, and no existing care-notification column. The applied transaction includes those dependency guards and refreshes the full structural catalog and exact merge fingerprint atomically. No role assignment, old-note backfill, demo-case deletion, real clinical update, billing change or native build was submitted by this deployment operation.

**Verification limitation:** the subsequent combined read-only function-body/policy/trigger verification request was blocked by the tool safety check before execution. It returned no database result and was not retried through another channel. The successful migration and its recorded version establish installation; they are not an independent post-deployment comparison of every stored function or a signed-in end-to-end test. Do not claim that comparison passed.

The separately planned post-deployment security-advisor run completed at **01:14:53 UTC**. It reported the same warning categories/counts as before installation: 110 informational private tables with RLS/no direct policies, 2 anonymous SECURITY DEFINER RPC warnings, 183 authenticated SECURITY DEFINER RPC warnings, and disabled leaked-password protection. These are existing findings, not a clean-security certification. No broad private-table policy or unrelated privilege change was added to silence them.

## Source and automated verification

Branch preparation run **36949446436** passed all source/syntax, eleven new database acceptance groups, five new browser groups and the existing athlete-health, trainer, Creator and public/in-app disclosure suites. It materialized the candidate at **a22bd6146167f9af9da87ceae6257e49f902e6a7**. All **16** applicable PR workflows subsequently passed on **da5c7347dcc4a6672464bc46344cc7c1ae9dbd3a**. This commit adds only the exact recorded migration and this evidence note; current-head PR results and publication are checked separately.

The tests use synthetic isolated databases/browser fixtures. The legacy SECURITY DEFINER notification inbox now uses the same care-access check as table reads, and the actual deletion planner distinguishes a notification-only recipient from a clinical author/reader with protected audit history. No clinical preservation rule was loosened. See `docs/RELEASE-0.20.116.md` for scope and test details.

## Publication and real-account acceptance

The frontend candidate is web **0.20.116**, paired in `index.html` and `sw.js`. A merge or successful source test is not a GitHub Pages deployment receipt; confirm the publication run independently before directing a user to test the new interface. This file records backend installation, not a future publication success.

After publication, first verify the expected trainer-facing buttons. Then send **one new, clearly fictional follow-up on an existing demo concern** privately to Parents / Guardians. Check the saved confirmation, the parent's in-app notice, its exact concern/update destination and read-state. Then test a separately labeled participation update and confirm the coach cannot see the older private note. Preserve both previously created demo concerns; do not resend historical notes to create alerts.

Health-specific lock-screen alert pushes, email and SMS remain unimplemented here. Native badge synchronization is not alert delivery. Wider organization event producers, due-review reminders and unresolved-action indicators remain in issue #51. Do not treat this release as completion of every role/notification or App Store acceptance requirement.
