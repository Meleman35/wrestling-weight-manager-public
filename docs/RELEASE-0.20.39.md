# Wrestling Manager 0.20.39

Private board/club ballots and deletable test meetings, built from verified main commit `f74ba2ba1d92b59d47d316c3332f79bac05aa2b5` (0.20.38). The exact frontend digest is in `validation/voting-source.json`.

## Using the test meeting

Open Clipboard → Organization → Meetings & minutes → **Voting test meeting**. Start the meeting, select **Private voting**, open the saved **TEST ONLY: approve a sample proposal** draft, review the sample rules, and open voting. Each of three fictional clubs has **Simulate test vote**. Close the round to reveal combined totals. New rounds can test amendments or different policies.

The prepared meeting is scheduled and its ballot remains a draft; no votes were cast for the owner. The earlier cancelled meeting was marked as a test, with its workspace unchanged. Both are restricted to meeting leaders. Use **Delete test meeting**, then type `DELETE`, to remove a test meeting, its ballots, notes and minutes versions. Only an organization administrator can delete, and this action cannot delete an official meeting. A minimal deletion audit/receipt remains. New test meetings automatically include three fictional clubs, without changing real organization positions or affiliate eligibility.

## Server schema and authority

Applied in order on the connected project:

1. `20260925010744_organization_private_ballots_02039.sql`
2. `20260925011134_private_ballot_meeting_list_fix_02039.sql`
3. `20260925011527_release_private_ballots_02039.sql`

The first migration adds `organization_meetings.is_test` and five private RLS tables:

| Table | Stored data |
| --- | --- |
| `organization_secret_rounds` | Motion, version/series, meeting, frozen rules/electorate totals, status and closed aggregate result |
| `organization_secret_participants` | Frozen seat identity/name, attendance, current adult delegate and submitted boolean; no choices or cast times |
| `organization_secret_delegations` | Historical delegate-to-seat association preventing a person moving seats to cast twice |
| `organization_secret_totals` | Round ID and three aggregate integer counters only; no individual ballots |
| `organization_secret_requests` | Administrative request idempotency receipts; casting is excluded |

Tables deny direct anonymous/authenticated access. The existing `public.organization_governance` RPC routes `ballot_*` through the guarded `private.vote039_request` and `meeting_*` through `private.vote039_meeting`. Helpers use an empty search path and have public execution revoked. Legacy meeting/voting functions remain inaccessible. The old direct meeting writer is revoked to prevent bypassing the open-ballot/adjournment interlock.

Ballots require a personal account with a matching current Auth session, no current ban, and the existing nonshared-account rules. Voters must be eligible adults assigned to the round; opening requires a leader's explicit adult/delegate and governing-rule attestations. Meeting chair/secretary or organization admin controls rounds. A title by itself grants no access. Authenticated-role tests supply claims at the database boundary; they do not fabricate a usable JWT or sign anyone in.

## Ballot rules and secrecy

Board seats are individual people; club seats have one designated adult delegate. The round snapshots eligibility/attendance before opening. Official club rounds also require confirmed active membership and separately reviewed voting eligibility in Affiliate directory. The historical directory alone cannot authorize a ballot. Later affiliation edits do not rewrite an open round.

Rules must explicitly provide attendance quorum, minimum submitted ballots, approval numerator/denominator and comparison, denominator basis, abstention treatment, tie behavior, governing-rule reference and electronic secret-voting authority. No official default is assumed. Zero votes or no substantive For/Against votes yield no decision; unmet turnout yields no quorum. A configured tie may require a separate new round but does not open one automatically. Amendments/revotes are new rounds with a reason.

All mutations lock the organization row, then their round/meeting records, in a consistent order shared with meeting writes. A cast atomically spends the seat and increments exactly one aggregate counter. Retry, another device or a delegate substitution cannot mint another vote. Replacing a delegate preserves the seat's submitted status and earlier seat associations. Close and cast serialize; adjournment is blocked while any ballot is open. Closed aggregate results are included in the minutes snapshot, while executive notes retain their separate restricted storage.

The chair can see participation but no running choice totals or individual choices. Submitted choices are cleared from the UI. Casting produces no choice receipt, choice hash, application cast audit entry, localStorage entry or per-voter choice record. Only closing reveals combined totals. Cancelled totals remain hidden.

**Threat model:** application-level secrecy from other application users, including the chair. Database/infrastructure administrators can inspect requests, aggregate-counter changes, transaction logs or backups. Small or unanimous results can permit inference. This is not cryptographic, independently verifiable or infrastructure-anonymous voting. Test simulation is available only on unassigned seats in test meetings.

## Verification and deployment record

- 35 embedded JavaScript syntax checks, 34 script-preservation comparisons and exact source/embedded-module equality.
- 29 PGlite/PostgreSQL groups covering authorization, session validity, tenant separation, ineligible voters, rule validation, hidden projections, retries, substitutions, immutable rounds, outcomes, test visibility/deletion and direct-table/helper denial.
- 11 whole-page Chromium checks at phone/tablet widths using the actual guarded SQL functions through PGlite, including lost-response recovery, polling, sample votes and deletion. Images inspected locally.
- Five real multi-transaction PostgreSQL scenarios on the connected server: same-seat double-submit, cast/substitution race, cast/close race, rollback/retry, and concurrent distinct seats. Aggregate totals matched submitted seats in all cases. Separate temporary organization/accounts/sessions had no passwords, login tokens, emails or invitations; all temporary rows were removed afterward. Details: `validation/voting-live.json`.
- Anonymous and malformed-session HTTP requests both returned 401.
- Security advisor review: the five new private tables intentionally have RLS with no direct policies/grants; they are accessible only through guarded definer functions. Existing project-wide advisor warnings were not changed as part of this release.
- The official-opening release gate remained false until the database, browser and concurrency checks passed. The final migration enables opening subject to all organization-specific checks.

At commit preparation, all three server migrations were applied and the owner's test meeting/sample draft were saved. The frontend is ready for GitHub Pages publication; success must be verified from the workflow and live file digest after this commit. No Apple upload, Safari/device validation or hosting migration is included. Native bridges, Mat Mode, login/invitation code, signed agreements and existing organization structure code remain preserved.

Run local checks with Node, Playwright/Chromium and PGlite available:

```sh
python tests/check-voting-source.py
node tests/voting-db.cjs
node tests/voting-browser.cjs
```

`PGLITE_MODULE` may point to an installed module and `CHROMIUM_EXECUTABLE_PATH` to Chromium. Tests create isolated in-memory databases; they do not use production credentials. Browser network requests are intercepted. They load the first two migrations to verify the initial release gate, then enable it only inside the isolated fixture when testing official ballots.
