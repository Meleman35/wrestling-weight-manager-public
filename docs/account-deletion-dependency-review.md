# Account deletion dependency review — read-only tooling

The intake draft still does not erase data. This follow-up adds a catalogue query and offline planner to help implement fulfillment without guessing which shared records belong to the departing account.

## What the tooling does

`scripts/account-deletion-inventory.sql` reads PostgreSQL catalogue metadata for tables and foreign keys in `auth`, `public`, `private` and `storage`. It returns table/column names, JSON columns, ordered composite-key mappings, delete actions and constraint state. It does not read application record values, Storage object names, credentials or function bodies. It creates no schema objects and is not a migration.

Save the returned `inventory` object as a private JSON file, then run:

```sh
node scripts/account-deletion-plan.cjs /absolute/path/catalogue-inventory.json > /absolute/path/dependency-review.json
```

The Node script has no database/network client, account target, SQL generator or execution mode. It distinguishes:

- Every dependent table reachable from either account root, regardless of foreign-key delete action.
- Tables with a path made entirely of `CASCADE` links from either root. This means possible propagation if those root rows are removed; it does not count affected records or authorize deletion.
- Restrictive links, `SET NULL`/`SET DEFAULT`, embedded JSON, context columns such as team/athlete IDs, and tables outside that dependency direction.

Every table stays `UNREVIEWED`; `execution_ready` always remains false. Unknown/missing constraint metadata causes an error. Cycles terminate and composite-key order is retained. A fingerprint changes with inspected column/constraint metadata so a future reviewed plan can detect drift. It does not fingerprint trigger bodies, policies, views, external systems or all database semantics.

## Current review findings

September 29 catalogue run before reviewer installation: 217 tables and 480 foreign keys in the four selected schemas. There are 176 direct references to the account roots. The dependent-table graph spans 154 tables and 287 relationships: 109 cascade, 71 set-null, 96 no-action and 11 restrict. Fifty-four non-root tables have an all-cascade path from an account root. These are schema counts, not people/records affected by any specific deletion.

The other 63 tables cannot be dismissed. In particular, athlete profiles, private medical/contact/identity records and athlete credentials sit outside this incoming-dependency traversal. Some are connected through athlete and guardian/member associations in the other direction. Deleting login/profile rows therefore does not establish that all of a person's athlete data has been removed. Conversely, a parent leaving must not automatically erase a shared child's record.

Do not infer ownership from `created_by`, cascade behavior or a matching column name. Explicitly distinguish self-owned athlete records, parent-managed child records, a coach's authored content and shared team history. Data copied into JSON, text, files or provider systems requires additional review.

## Required fulfillment decisions

For each table or provider, the next adapter needs: the verified identity/authority lookup; exact scoped row predicate; how to handle shared records; erasure/redaction or narrowly justified retention; media/provider object resolution; retry key; and completion evidence. Link-table parent records need their own authority checks. A deletion request for a parent's account is not automatically a verified request to erase every linked athlete.

After classification, exercise a resumable worker against synthetic coach/parent/athlete families and shared teams. Prove that unrelated accounts, memberships and media remain usable. Session revocation, still-valid access tokens, physical Storage deletion, device cleanup, backups and completion notices are separate requirements. The worker must not run from the browser or expose a service key.

Supabase documentation confirms that deleting Auth alone does not invalidate existing JWTs and owned Storage objects can prevent user deletion: https://supabase.com/docs/guides/auth/managing-user-data

## Verification

`tests/account-deletion-plan.cjs` covers shared cascades, blocked propagation, null/default actions, unlinked tables, metadata drift, cycles, composite keys, malformed metadata and the absent execution mode. It also runs the actual catalogue query in a read-only PGlite transaction with synthetic account values, verifying that those values are absent from output and the rows remain unchanged.

```sh
NODE_PATH=/path/to/dependencies/node_modules node tests/account-deletion-plan.cjs
```

Use the pinned PGlite dependency in `.ci/package.json`. Results are written to `validation/account-deletion-plan.json`. No production migration, feature switch, native source or tester permission is changed.

## Integration with current main

The deletion branch now incorporates released parent-browser and reviewer work. [The additional data map](account-deletion-reviewer-parent-map.md) identifies reviewer approvals, browser capabilities and non-account guardian records that fulfillment must handle. The metadata planner remains read-only and every disposition remains unreviewed.
