# 0.20.43 draft — Tournament alert choices and background preparation

Built from published main `82e89ca2ec9cd3f28ed205e19ce3a9d28fb62eb4`. This draft is not deployed. The live web release remains 0.20.42, whose Team Join, Clipboard customization and tournament demo checks Damon confirmed working on September 25, 2026.

## User-visible changes

Tournament Day → My tournament alert choices saves 60/30/15/10/5 minute reminders, readiness statuses and assignment/estimate changes for the signed-in account and selected team. All saved choices default off. Revision checks prevent a second device from silently overwriting newer choices; Reload saved choices recovers conflicts. Switching accounts or teams clears the controls and ignores delayed responses.

The sample tournament uses saved choices when present. Without a saved preference, it keeps its original sample defaults so the demonstration remains useful. Sample controls change only the preview. Consumed countdowns and readiness statuses do not replay when a setting is enabled midway through a sample session. Finished bouts no longer produce assignment-change previews.

The interface explicitly states that delivery is not active. This version does not make phone, inbox, SMS or email alerts available.

## Server preparation

The additive migration creates private, RLS-enabled preference, state and draft tables. A public invoker RPC accesses only the current user's authorized team preferences. The existing Tournament Day access boundary still rejects unrelated and managed accounts. Raw tables, recipient helpers and worker execution are denied to clients.

`private.prepare_tournament_alert_drafts()` is a bounded database batch intended for a future cron job. It persists consumed countdowns and readiness statuses per recipient/team/bout, locks due preference rows with `FOR UPDATE SKIP LOCKED`, and commits preparation and state changes together. It selects the next active bout per athlete in each tournament. Revision and timestamp checks reject older snapshots; unknown, expired, future-dated or stale timing cannot produce countdown drafts. Changes require fresh data.

Explicit recipient checks cover active rosters, staff and administrator permissions, linked family, athlete visibility and paused team notifications. Draft payloads omit names, opponents, brackets and results. Mat-only recipients receive assignment fields only. Drafts expire after at most two minutes, and changes to preferences, visibility, membership, source revision or the next bout invalidate pending work on preparation; saving choices immediately clears that account/team's drafts.

**No cron job, Edge Function deployment, inbox insertion or delivery queue write is included.** The SQL function is not connected to the existing communications dispatcher. Drafts are private preparation records, never permission to send. Production delivery must separately recheck authorization and current bout data immediately before sending, apply existing quiet hours, handle retries per device and update inbox/badge routing. Provider delivery cannot promise exactly-once transport solely from these database deduplication keys.

## Validation

- 13 isolated database groups using the actual migration SQL: saved choices, revisions, validation, tenant boundaries, timing thresholds, durable deduplication, reschedules, readiness reversals, privacy, revoked access, roles and client denial. Synthetic inbox/delivery tables remain empty.
- 6 whole-page Chromium groups backed by SQL: saved choices, conflict recovery, sample choices, account/team separation and delayed-response disposal. The 390px phone layout was visually inspected.
- 4 preference-aware reducer groups, plus all 7 previous alert reducer groups.
- All 8 existing tournament browser groups and all 13 existing communications browser groups passed.
- Rebuilt the self-contained HTML twice from the published baseline with identical bytes; syntax-checked all 40 inline scripts. Existing join-copy, Clipboard navigation, notification inbox, native-facing assets and authentication callback remain byte-for-byte unchanged.

Build: `python scripts/build-tournament-alerts-043.py`. New checks are `tests/tournament-alerts-043-{db,browser,reducer}.cjs` and `tests/tournament-alerts-043-source.py`; fixture-backed checks use PGlite and Playwright.

## Before publishing this draft

Migration `20260925043538_tournament_alert_preferences_02043.sql` has **not** been applied to the hosted project. Review and apply it once, validate against synthetic rollback-only data and run the security advisor before publishing the web bundle. Do not reapply the existing 0.20.42 migration. No production records, functions, schedules or settings were modified during this draft's preparation.

USA Bracketing remains pending. Apple/TestFlight build 1.0 (1) is unchanged.
