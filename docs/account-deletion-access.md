# Account deletion: current-caller access prototype

September 29, 2026. **Unwired, isolated-test prototype in draft PR #25. Not a production access shutoff or a release migration.** No live hook, RLS policy, Auth account/session, team login, billing flag, video grant or native file is changed. The deletion worker remains disabled and unmounted.

## Implemented code

`scripts/account-deletion-access-draft.sql` defines three functions only. It requires an explicit isolated-test fixture marker and the existing deletion draft schema; it is deliberately outside `supabase/migrations`. The marker prevents accidental application, not a security boundary. Do not configure it in production. A reviewed release migration must later be created through the Supabase CLI, after integration/acceptance gates are met.

- `private.account_deletion_access_allowed()` is argument-free and read-only. It checks the current caller's Auth user, matching registered session, session deadline, ban/deletion state, token expiry and existing deletion job. A pending request or phase-0 review does not itself revoke access. Once reviewed work advances to phase 1, all that subject's sessions are denied, including newly created ones. Pausing fulfillment, retries and blocked jobs cannot reverse the denial.
- `private.require_account_deletion_access()` raises a generic permission error on denial; it does not disclose another account's state.
- `public.account_deletion_pre_request()` composes with the **existing** `public.enforce_team_login_request()`. It does not replace that function or change the configured hook. Existing recorder/managed-login restrictions therefore remain a separate prerequisite.

The private Boolean reader is the sole new SECURITY DEFINER function. Its limited purpose is reading otherwise inaccessible Auth/job state without exposing those tables. It has no target-account argument, no dynamic SQL, an empty fixed search path and no writes. Execution is revoked from PUBLIC/anon; authenticated callers can obtain only their own yes/no result. The assertion and public composition wrapper are invokers. No authorization decision uses user-editable metadata.

The verified gateway must validate token signature, issuer and audience before installing request claims. The helper additionally checks role, subject consistency, expiry and session ownership. It is not a JWT verifier, and the synthetic SQL tests do not prove cryptographic or hosted-gateway behavior. Backend/schema errors propagate; they do not turn into successful authorization.

No additional durable identity marker is introduced. Existing worker completion removes job linkage only after verified Auth removal; a missing Auth user/session continues to reject the old token. This does not resolve backup restoration, receipt retention, or the earlier device marker's retention requirements.

## Verified baseline used for design

A metadata-only production query on September 29 confirmed `pgrst.db_pre_request=public.enforce_team_login_request` and the relevant `auth.users`/`auth.sessions` column shapes. It also confirmed the current managed-login access and resource checks. No account values were read. This is a targeted schema/function check, not a complete production authorization audit.

The regression loads actual intake/fulfillment draft migrations, actual reviewer/parent table definitions, and the existing managed-login guard function bodies from repository source. Other Auth, team-login and application tables are deliberately minimal synthetic fixtures; this is **not** a complete production-schema test.

## Integration and limits

A pre-request function covers PostgREST only. It does not automatically protect Storage, Realtime, anonymous browser-token endpoints, Edge Functions using service credentials, or other server workers. Installing these functions alone enforces nothing on those surfaces.

The tests demonstrate the **restrictive** RLS pattern on synthetic application and Storage tables: AND the additional guard with existing row authorization, for both USING and WITH CHECK. A restrictive rule does not grant access on its own, and must not replace an ownership/role policy. No such production policies are installed here.

A deliberate negative-control test proves that an unguarded SECURITY DEFINER routine can still bypass row policies. The composed request check prevents that body from executing on the guarded test route, but this does not protect arbitrary direct calls, owner-executed views, privileged jobs or service-role calls. Each actual entry point needs reviewed wiring and acceptance evidence.

All checks observe a database statement snapshot. A request that already read authorization before the deletion transition may still finish; the prototype does not drain in-flight operations or provide a cross-provider write barrier. Those operations must be quiesced/reconciled before inventory/erasure. Browser memory, old offline screens, previously issued signed media URLs and cached Realtime authorizations are not recalled by this predicate. Session presence/not_after checks do not independently implement every configured Auth inactivity or maximum-lifetime rule.

The prototype does **not** ban users, terminate Auth sessions, revoke refresh/provider tokens, revoke parent-browser links, stop notifications, remove records/media, disconnect live channels, or clean native devices. Existing worker flags such as `stale_tokens_blocked` MUST NOT be earned from this component alone. No worker adapter returns global revocation evidence from it.

Anonymous/service callers retain their existing endpoint checks. That is compatibility preservation, not proof that alternative credential paths are safe. Sign-in/refresh prevention, managed credential continuity, signed-URL expiry limits and full service-provider coverage remain release gates.

## Regression coverage

Run `NODE_PATH=.ci/node_modules node tests/account-deletion-access.cjs` using the repository's pinned lockfile. The new `Account deletion access regressions` workflow also runs the existing full `team-recorder-login.cjs` suite. It has read-only repository permissions, no production credentials and no deployment steps. Results are retained as `deletion-access-results`, including `validation/account-deletion-access.json`. The PR records verified run IDs and the tested commit; syntax checks alone are not a database-test pass.

Fourteen regression groups cover inert installation, two-device sessions, malformed/mismatched/expired claims, private-table/argument/activation denial, removed/expired sessions, banned/deleted identities, reviewed deletion cutoff and new sessions, pause/retry behavior, real managed/recorder guard composition, restrictive RLS and queued writes, the Storage-policy pattern, an unguarded-definer negative control, privilege/search-path/backend-error checks, and old-token denial after synthetic Auth removal/job unlinking. Shared records and unrelated accounts are preserved in the fixture.

These are PGlite tests, not hosted PostgREST/Auth/Storage/Realtime/Edge or physical iPhone/iPad/Mac acceptance. The existing launch, parent and offline workflows must also pass on the same PR head before any broader claim about regressions.

## Next integration gates

1. Inventory all actual entry points, row policies and owner-executed views; map verified-user, managed-login, anonymous-token and service-worker paths separately. Review helper ownership and least privilege before release.
2. Wire checks into the real PostgREST hook composition, applicable restrictive policies and privileged server paths without breaking recorder/parent flows. Validate all deployed Auth/session claims on synthetic accounts in an isolated full-schema environment.
3. Implement and independently verify sign-in/refresh/provider revocation, in-flight work handling, channel/URL bounds and stopping deliveries. Integrate that complete evidence with the leased worker; do not weaken its phase-1 checks.
4. Finish reviewed record/media scope, sole-admin continuity, retention/restore, device cleanup, confirmation and runner operations. Keep deletion disabled until full end-to-end and distributed-device acceptance succeeds.

## Primary documentation checked September 29

- Supabase sessions: https://supabase.com/docs/guides/auth/sessions
- Supabase API security (PostgREST-only pre-request scope): https://supabase.com/docs/guides/api/securing-your-api
- Supabase Realtime authorization: https://supabase.com/docs/guides/realtime/authorization
- PostgreSQL row security, including restrictive policies and owner/BYPASSRLS behavior: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- Supabase changelog: https://supabase.com/changelog

The Markdown changelog endpoint was not readable through the documentation browser; the HTML changelog was reviewed instead. The current PostgreSQL minor-release advisory concerns ltree, legacy PGP ciphers, floating-point GiST and custom operators; this prototype introduces none of those features. The Realtime schema restriction does not authorize schema modifications here; no Realtime objects are changed.
