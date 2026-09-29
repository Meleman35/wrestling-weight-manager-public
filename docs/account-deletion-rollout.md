# Account deletion — disabled draft, not launch complete

Prepared September 28–29, 2026. This branch does not change `index.html`, sign-in, membership access, the native app, or production Supabase. No real account is deleted or disabled.

## Implemented and tested locally

- Migration `20260929052714_account_deletion_intake_draft.sql`: an authenticated, owner-only request and status API, RLS, restricted insert columns, immutable request timestamps/deadlines, idempotent receipts and a default-off switch.
- `src/account-deletion.js`: a standalone confirmation/status component. It distinguishes a received request from completed deletion, handles a lost response/retry, links Apple subscription management, and discards stale responses after invalidation. It is not mounted in the live app.
- Eight PostgreSQL checks pass in PGlite 0.5.8 with synthetic users, including RLS and privilege failures. Seven DOM checks pass in jsdom 26.0.0. No production migration was applied. These are not Apple-device tests.

Run with pinned dependencies installed outside the repo:

```sh
npm install --prefix /tmp/wm-deletion-test --no-audit --no-fund @electric-sql/pglite@0.5.8 jsdom@26.0.0
NODE_PATH=/tmp/wm-deletion-test/node_modules node tests/account-deletion-intake.cjs
NODE_PATH=/tmp/wm-deletion-test/node_modules node tests/account-deletion-ui.cjs
```

## Apple requirement and why this stays disabled

Apple requires in-app initiation of account deletion. Ordinary apps cannot require a support email or phone call. Manual fulfillment can be acceptable if a timeframe is disclosed and completion is confirmed. Deactivation alone is insufficient; associated personal/user-generated data must be addressed, subject to lawful retention. Subscription management is separate.

Source: https://developer.apple.com/support/offering-account-deletion-in-your-app/

This is an intake implementation, not an erasure implementation. A button that merely stores requests cannot make the app launch-ready unless the fulfillment process works. The draft uses a 30-day maximum operational target, frozen as a deadline on each receipt; Damon must be able to meet that target before activation. It is not a claim about every jurisdiction's legal deadline.

## Read-only inventory findings

The follow-up [dependency review](account-deletion-dependency-review.md) adds a read-only catalogue query and offline planner. It expands the direct references below into a dependent-table graph, distinguishes potential cascade paths, and keeps tables outside that graph explicitly unreviewed. It never generates or executes erasure operations.

The current schema has 176 foreign keys referencing Auth users or public profiles, including 70 without a cascade/null action. Shared team, organization, match, medical, guardian, social and video records require deliberate handling. This is a first-level dependency inventory, not a completed erasure graph. A blanket cascade would risk other people's records; deleting only Auth can fail and can leave personal content behind.

Supabase documents that user deletion does not invalidate an already issued JWT, and owned Storage objects can prevent Auth deletion:
https://supabase.com/docs/guides/auth/managing-user-data

## Fulfillment work required before enabling

1. **Scope and identity.** Bind to the authenticated personal account; verify identity/intent without requiring a separate support request. Handle team-device credentials separately. A guardian's own account and a request about a child are different scopes; child-data requests need verified authority and applicable consent/retention rules.
2. **Ownership and continuity.** Identify sole team/organization administrators and provide continuity without making another coach's cooperation an indefinite barrier to deletion. Do not erase another guardian, athlete, team or organization merely because a departing account created it.
3. **Data map.** Classify each table and media bucket by ownership, shared content, legally required records and de-identification feasibility. Cover posts, messages, attachments, photos, videos, invitations, push tokens, calendar tokens, exports, analytics/provider copies and logs. Shared user-generated content is not automatically exempt from deletion.
4. **Revocation.** Stop new writes/delivery from the target account, revoke sessions and provider credentials, and enforce the deletion state server-side for still-valid access tokens. Preserve access for unrelated testers. If Sign in with Apple is enabled later, revoke its tokens too.
5. **Resumable erasure.** Use a per-request job ledger and provider object IDs. Retry each step safely; use Storage APIs for physical files rather than deleting only metadata. Do not mark complete while an external object deletion failed. Never run a generic mass cascade over current users.
6. **Device state.** Invalidate bridges, clear that account's cached records/keys/outbox on the next contact, and handle device-local recordings/exports with an explicit user-facing export/removal decision. Do not wipe unrelated users' saved work. Already offline devices require a bounded authorization policy and cleanup on reconnection; do not promise remote erasure while a device is unreachable.
7. **Retention and backups.** State exact retained categories, purpose, authority and schedule. Backups need expiry and a restore-time deletion ledger; no indefinite catch-all retention. Legal retention is an exception requiring a basis, not a blanket product preference.
8. **Confirmation and operations.** Confirm completion through an approved channel, monitor deadlines, and support failures/escalation. Keep only the minimum receipt/audit data justified by the policy.
9. **Acceptance.** Test synthetic coach, parent, athlete and shared-team accounts, multiple guardians, media, sole admin, old JWTs, reconnect, provider failures, retries and backup restoration in an isolated environment. Prove unrelated accounts still sign in and retain their records.

## Integration gate

Only after fulfillment passes: mount the component in Profile → Account → Delete Account for all personal accounts, including users without a team and users with an active subscription. The adapter must call `invalidate()` on sign-out, account switch, app lock and kiosk/managed-login changes; supply authenticated RPC and the current account; prevent entry from locked/shared device contexts. Update the standalone and in-app privacy text together. Then enable the server switch deliberately. Never hide an incomplete deletion path behind a claim of compliance.

No billing, child-consent, or access restrictions are activated by this branch.
