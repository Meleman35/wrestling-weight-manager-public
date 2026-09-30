# Account deletion fulfillment draft

September 29, 2026. This adds executable worker infrastructure and a reviewed reviewer/parent capability-revocation slice. It is **not a complete production deletion implementation**. Nothing here is deployed, scheduled, mounted in the app, or enabled. No real account was erased or disabled.

## Implemented

The CLI-created migration `20260929190649_account_deletion_fulfillment_draft.sql` adds an independent default-off fulfillment switch and service-only private job/object ledgers. Queue insertion takes a durable request ID and derives the subject from that receipt; a client cannot choose another target. Workers claim one job with a 60-second lease. Every transition checks the lease, expected phase and configured release. A replacement worker fences out stale acknowledgements. Bounded batches yield immediately; transient failures use capped exponential backoff, while missing scope/verification evidence blocks automatic retries. Receipt deadlines never reset.

| Phase | Required result before advancing |
| --- | --- |
| Review | Current schema, reviewed account scope/continuity/retention, prepared confirmation channel |
| Revoke | Sign-in blocked, refresh sessions revoked, old-token access denied, managed access revoked, deliveries stopped |
| Inventory | Complete reviewed object manifest, committed before any object deletion |
| Media | Every exact object physically removed through its provider API and absence verified |
| Records | Personal records erased, other people's shared records preserved |
| Auth | Hard deletion and independently confirmed missing account |
| Verify | No scoped personal data/external objects remain; shared records preserved; restore ledger recorded |
| Confirm | Completion delivered through the prepared idempotent channel |

`scripts/account-deletion-worker.cjs` is import-only and requires all adapters explicitly. It has no credentials, network defaults, executable CLI or production scheduler. The ledger uses a dedicated service database connection; no public worker RPC is exposed. All SQL functions are invokers, with fixed empty search paths and execution revoked from public/anon/authenticated. Evidence flags are assertions by **trusted server adapters**, not cryptographic proof or client authorization. Production adapters must earn these assertions through independent checks; copying the synthetic fixture adapters is not a production implementation.

`scripts/account-deletion-supabase-adapters.cjs` implements the narrow Storage/Auth SDK contracts. Storage removal addresses one manifest object, calls the Storage API, then requires an independent metadata absence check. It never deletes Storage metadata using SQL or empties a bucket. Auth removal uses `deleteUser(id, false)`, verifies with `getUserById`, and treats only the documented missing-user error as absence. A 403, timeout, empty response or provider error is not successful deletion. The server runner must pin its SDK, configure request timeouts, and pass an independent catalogue reader; that runner is not yet supplied.

## Reviewer and parent access slice

The leased revocation phase removes reviewer assignments where the departing account is either reviewer or approving administrator. It revokes parent-browser permissions and links for guardian relationships bound to that account, and for verifications issued by the departing coach; it removes those verification rows. This closes the case where a permission outlives its verification. It does not silently transfer reviewer approval/acceptance, delete the child, delete other guardians, or toggle project-wide settings. Personal fields in revoked parent rows are still phase-4 erasure work. These statements use actual current reviewer/parent table definitions in the isolated regression.

This is a capability slice, not global account revocation. RLS, security-definer RPCs, Storage, Realtime, Edge functions, email/browser tokens, offline bridges and managed logins must all be reviewed before the full revoke adapter can return success.

## Crash and retry contract

External calls cannot share a database transaction. A timeout/crash can follow successful provider deletion but precede the checkpoint. Every adapter must therefore be idempotent, use immutable manifest IDs, and honor the passed abort signal where supported. Notification delivery must use the request ID as its idempotency key and prepare its delivery destination before erasure; do not resolve it from a removed Auth account. The worker checks its lease before each operation and before accepting results. This prevents later phases after lease loss; it does not promise exactly-once external calls or recall an already in-flight request.

After all phases, the receipt is marked completed, subject linkage is nulled in receipt/job, and object paths are removed from the job ledger. These steps do not by themselves anonymize retained timestamps or establish a lawful audit/backup retention policy. Policy version/fingerprint and minimal operational receipt remain pending that policy. Blocked jobs require reviewed repair; there is deliberately no blind client retry/reset/skip-phase endpoint. Pausing fulfillment prevents new claims and checkpoints, but cannot cancel a provider call already in flight.

Use `scripts/account-deletion-queue-status.sql` for a read-only report of overdue, nearly due, blocked and unqueued requests. Scheduling, alert delivery and operational ownership remain activation gates.

## Current inventory and release gates

The read-only September 29 catalogue refresh found **226 tables and 497 foreign keys** in auth/private/public/storage, including **181 direct account-root references** and 160 related tables. Its structural fingerprint was `330abc0f0f6afea1641f0a9f7620d8f21510d32fc907c27b0d10445a8c796dc2`. This snapshot excludes these undeployed draft migrations and can change as other work ships; it is **not** an approved execution fingerprint. The planner does not hash function bodies, policies, triggers, views, provider state or ownership semantics. A release review must cover those separately and refresh the deployed catalogue before configuring fulfillment.

Still required before enablement:

- Explicit row-level erasure/minimization and shared-owner disposition across the complete schema, JSON snapshots, organization records, guardians without Auth accounts, media/versioned objects and external providers. `created_by` and Storage uploader ownership do not by themselves establish permission to erase a shared record. Child-data deletion remains a separate verified scope.
- A server-enforced access gate covering every relevant surface for stale JWTs and asynchronous jobs, plus a bounded policy for outstanding signed media URLs. Auth deletion alone does not revoke already-issued access tokens.
- Real database/provider/notification adapters, version-pinned server runner, release reconciliation, operational alerting and a reviewed restore-time deletion ledger/retention schedule. Versioned Storage objects, multipart uploads, moved/shared objects and external video must be explicitly inventoried; missing adapters block the worker.
- Account-specific device/outbox/cache cleanup, reconnect handling and testing on the physical iPhone/iPad without erasing another person's work. Preserve native revision 20 and TestFlight Build 4 until a separate tested change is ready.
- Isolated end-to-end production-schema tests with synthetic coach/sole-admin, parent, athlete and multiple-guardian accounts; old-token denial, provider failures, media, continuity, restore, and unrelated-account access. Then mount the UI, synchronize privacy text and deliberately enable intake/fulfillment.

## Validation

Run `NODE_PATH=.ci/node_modules node tests/account-deletion-fulfillment.cjs`. It uses PGlite PostgreSQL with production reviewer/parent table definitions and synthetic Auth/record/provider adapters. It tests privilege denial, default-off gates, request binding, duplicate requests, stale-worker fencing, capability cleanup, durable manifests, lost media acknowledgements, retries/backoff, schema drift, foreign-subject manifests, missing stale-token proof, residual data, notification failure, pause and SDK error handling. It does **not** prove the missing production gates above.

Sources checked September 29, 2026: [Supabase user management](https://supabase.com/docs/guides/auth/managing-user-data), [Storage deletion](https://supabase.com/docs/guides/storage/management/delete-objects), [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/). The current Supabase changelog and relevant PostgreSQL minor-release advisory were reviewed before implementation; this draft introduces none of the advisory's affected ltree, legacy PGP cipher, float GiST or custom-operator features.
