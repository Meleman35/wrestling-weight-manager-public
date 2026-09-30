# Account deletion access integration — draft only

September 29, 2026 evening Mountain / September 30 UTC. Continue PR #25 on top of
main `78b2e648a4fc5094e2e9f41eb64bfde7db1627e1` (v0.20.94). The schedule fix and
released parent/reviewer work are preserved. No production changes, real messages,
account deletions, grant changes or native edits accompany this work.

## What changed

The earlier current-caller predicate was not connected to request paths. This pass
adds an import-only isolated installer and connects the actual member and organization
invitation handlers to a fresh caller-bound access RPC before privileged side effects.

`scripts/account-deletion-access-scope.json` records a read-only catalog-name snapshot:
76 currently client-accessible public tables plus the two draft deletion tables;
three public invoker views; Storage objects and two multipart tables; and
`realtime.messages`. No user values, addresses, identifiers, tokens, keys, function
bodies or private native source were copied into the manifest. Names describe the
reviewed access surfaces, not approval to erase their records.

`scripts/account-deletion-access-integration.cjs` installs 82 restrictive policies
in a supplied isolated database. It requires the existing draft predicate and
deletion schema, retains every existing row-ownership policy and grant, and adds
both USING and WITH CHECK. A restrictive policy alone never grants a row.
The three views must already have `security_invoker=true`; the installer does not
rewrite them. View functions and underlying private dependencies still need review.

The installer validates public table and column-level grants, expected views,
existing RLS, reserved-name collisions, and the existing global authenticator
pre-request setting. New/missing public surfaces, owner-executed or materialized
views, database-specific hook overrides, and unexpected hooks require review.
It never guesses how to replace another hook. All mutations occur in one
transaction; interrupted installation rolls back the policies, RPC and role change.
Reinstallation stops for inspection instead of replacing a prior guard silently.

The composed PostgREST hook preserves the existing team-login/recorder guard.
The new `public.account_deletion_check_access()` RPC is argument-free, invoker,
authenticated-only, and returns only the current caller's Boolean result. It does
not expose Auth rows, choose an arbitrary account, or grant roles.

The two invitation handlers forward the original caller token with the publishable
key to this RPC. Exact JSON `true` is required; denial, missing RPC, unexpected
body, network failure or timeout stops subsequent privileged work. Member invitations
recheck before Auth link generation (including fallback), parent capability issuance,
and email submission. Organization invitations recheck before email submission.
Recipient selection, consent/role checks, fixed templates, secret handling and
provider idempotency keys remain in place. Anonymous parent-browser operations are
not converted to JWT operations by this change.

**Deployment dependency:** these handler edits fail closed if the new RPC is absent.
Do not deploy them alone. This installer is intentionally not a migration and is
guarded by an isolated-test marker. A reviewed production migration and coordinated
backend/Edge rollout are still required. The marker is accident prevention, not
an authorization boundary. Do not set it in production or supply a production DB.

## Verification

Run with the pinned `.ci` dependencies:

```sh
NODE_PATH=.ci/node_modules node tests/account-deletion-access.cjs
NODE_PATH=.ci/node_modules node tests/account-deletion-access-integration.cjs
NODE_PATH=.ci/node_modules node tests/team-recorder-login.cjs
node tests/member-invitation-email.cjs
node tests/organization-invitations-email.cjs
node tests/parent-browser-handler.cjs
```

The integration test installs the policies and role setting, then routes synthetic
requests through the configured hook. It demonstrates two sessions losing reads,
queued inserts/updates/deletes, invoker-view access, and Storage/multipart row
access at phase 1. Another account retains allowed writes and shared history.
Blocked work and paused fulfillment do not restore access. Missing Auth identity
still blocks an old token after job unlinking. Actual invitation handlers call the
installed SQL RPC through an injected HTTP transport; deletion/ban changes between
stages stop later side effects. Every email/Auth/provider response is synthetic.

This is PGlite with real draft migrations and recorder guard bodies, catalog-name
fixtures with minimal columns and synthetic ownership policies, and a SQL request
harness. **It is not a full production-schema copy or a hosted PostgREST, JWT,
Auth, Storage, Realtime, Edge or physical-device acceptance test.** Existing access
fixtures were extracted into a shared helper without changing their assertions.
CI retains exact-head reports; historical test reports are not release proof.

## Remaining gates

- Finish actual RPC/private-function/view dependency review. The read-only inventory
  found 278 public and 248 private functions; many are privileged. The PostgREST
  hook does not cover direct privileged calls or service credentials.
- Cover anonymous parent-browser/calendar capabilities, managed login creation,
  notification/SMS workers and all deployed Edge functions. Fourteen Edge function
  metadata entries were listed; their complete bodies were not audited in this pass.
- Verify sign-in, refresh/session/provider revocation, cached channel authorization,
  signed URLs, public media and all provider-side copies. Storage row policies are
  not physical object deletion, and multipart policies need hosted-service acceptance.
- Drain/reconcile requests already in progress. A fresh check narrows the window
  but cannot atomically revoke a provider request after it has been authorized.
- Complete personal/shared-data ownership, sole-admin continuity, child/guardian
  preservation, native/browser cleanup, retention/restore treatment, completion
  delivery and worker operation. The worker's global revocation evidence remains
  unchanged; this installer never returns it.
- Run the full synthetic lifecycle against a production-shaped isolated schema and
  actual provider/device paths before enabling deletion or deploying these handlers.

## Documentation checked

Supabase sessions and API/Realtime security guidance remain the references in
`account-deletion-access.md`. The current changelog index and linked July 14
Realtime restriction were read: policies on `realtime.messages` are still allowed;
the installer does not modify provider-owned Realtime tables or functions.
The September 25 PostgreSQL minor-release advisory concerns ltree, legacy PGP
ciphers, floating-point GiST and custom operators; this change introduces none.

- https://supabase.com/changelog/realtime-schema-locked-down-against-modification
- https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes
- https://supabase.com/docs/guides/auth/sessions
- https://supabase.com/docs/guides/api/securing-your-api
