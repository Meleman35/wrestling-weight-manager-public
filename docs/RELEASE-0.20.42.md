# 0.20.42 — Team Join, Clipboard customization and Tournament Day

September 24, 2026 (America/Denver). Built from main `c469a483ac33b1840ee32292bb537e050d028879`.

## Using this release

- Team Join: the selected team's URL stays visible. Copy Link confirms success inside the sheet; denied/unavailable clipboard access falls back to a selected, manually copyable field. Local native-page URLs resolve to the public join page. A delayed response from another team cannot replace the current link. No invitation behavior or permissions were changed.
- Clipboard → Customize Clipboard: reorder main categories and their nested tools, or hide/restore them, using the existing account layout preferences. Press-and-hold also recognizes both levels. Account and its Settings category remain available. Legacy Toolbox order/visibility carries forward until a category is customized. Permission checks and actual records are unaffected.
- Schedule → Tournament Day, or Clipboard → Practice & Competition → Tournament Day: choose a scheduled tournament. Its event detail also has Open Tournament Day. Coaches can set up a manual board, enter/update bouts, mats, division/weight, status, queue order, estimated start, a result/correction note and a bracket reference URL. Repeated displayed bout numbers and duplicate names do not merge identities.
- Parents: Tournament Day → What my athletes can see. Choose full details, upcoming bout without opponent, or mat/bout number only. Parents retain full access to their own linked child. Coaches retain authorized team access. Default athlete visibility is upcoming information without opponents; only linked parents can change it. Settings follow the same athlete record across teams.
- Try sample tournament: synthetic wrestlers, changing clock, mat moves, delayed starts, readiness statuses, unknown time, stale updates, and alert previews. It never writes team records or sends notifications.
- Scoring & weigh-in tools opens existing Mat Mode, Match Book and official weigh-in sheets under their existing permissions. These records are not automatically associated with a provider bout or submitted to USA Bracketing.

## Data and permission boundary

The additive migration creates four private, RLS-enabled tables and a public invoker RPC backed by a private, explicitly authorized function. Direct table reads and private helper execution are denied to clients. No service keys, provider passwords or credentials are embedded.

Each request checks the signed-in account, team, active roster and family link. Athlete replies omit restricted fields entirely, with restricted views limited to the next active bout. Opponents, brackets and results are not present in the mat-only or upcoming response; mat-only also excludes ETA, status, division and weight. Removed family/roster access fails on the next request. Clients keep board data only in memory, clear it on context changes or hiding the page, discard obsolete responses and revalidate on refresh/focus. No new exports, profile sharing or push payloads contain tournament data.

Updates use stable internal UUIDs and optimistic revisions. Stale edits and duplicate create retries cannot silently overwrite another save. Manual timestamps older than ten minutes are marked out of date; missing ETA remains unknown. Times are stored as absolute timestamps and displayed in the workspace's event timezone. Manual datetime entry explicitly uses the device's timezone.

## Validation

- 8 whole-page Chromium navigation/copy checks: acknowledged copy, rejection/manual fallback, unavailable Clipboard API, team-switch race, saved category/tool order and visibility, refresh persistence, press-and-hold and account/role separation.
- 11 isolated SQL test groups using the actual migration: identity, write conflict, viewer projection, parent authority, hidden-field absence, coach access, results, tenant separation, raw-table/helper denial and revoked access.
- 8 whole-page Chromium tournament checks backed by those SQL functions: coach editing, new division, parent setting, athlete restriction, demo alerts, stale/unknown timing, phone/desktop layout, account-switch races.
- 7 alert reducer groups: 60/30/15/10/5 minute thresholds, deduplication with restored state, reschedules, mat changes, status changes, older updates, late arrival, unknown/stale/past estimates and mat-only text.
- 13 existing communications browser checks passed, covering cross-team counts, inbox routing, wrestling reactions and invitation reminders.
- The 0.20.42 source check rebuilt exactly from the committed 0.20.41 baseline, verified idempotence and parsed all 39 inline scripts. The older 0.20.41 snapshot-equality test is superseded for this release.
- 12 live database checks passed using synthetic users without email, passwords or sessions in one rolled-back transaction. No real invitations, notifications, athlete records or team events were changed.
- Security advisors: existing warning counts unchanged (2 anonymous-definer notices, 181 authenticated-definer notices and the existing password-protection notice). Four new informational no-policy notices are intentional: the private raw tables deny direct client access, with data returned only by the permission-filtered RPC. See [Supabase's RLS advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Test commands use the installed Playwright and PGlite runtime. Browser screenshots were inspected at 390px and desktop widths. Damon confirmed the requested iPhone checks for Team Join copying, Clipboard customization and the tournament demo working on September 25, 2026. Automated simulated web-view checks remain separate from that user device confirmation.

## Deployment and remaining integration work

Damon explicitly approved publishing 0.20.42 on September 24, 2026. The reviewed release is published through PR #1. The additive database migration below is already installed and does not alter existing features or records.

Migration `20260925033022_tournament_foundation_02042.sql` was applied once to project `vfocpoyexnjsjpxhhyqr`, with rollback-only validation afterward. No earlier migrations were reapplied.

USA Bracketing is **not connected**. The adapter has an explicit unavailable provider implementation pending approved authentication, identifiers, payloads, ETA semantics and delivery limits. Full bracket rendering, verified external profile linking, supported live feeds, official results import, scoring/weigh-in writes and certification/hydration remain later work.

Alert code is a deterministic simulation reducer. No background scheduler or production notification delivery is enabled. A future server worker must persist delivery keys across devices, recheck viewer visibility at send time, and handle supported provider revisions; an open browser timer is not the production delivery design.

Build with `python scripts/build-tournaments-042.py`; modules are embedded in the self-contained index. The build is idempotent. Existing app.js, styles.css, mat-mode.html, authentication callback, native source, signing identity, NFC/scale integrations and saved records are preserved. Apple build 1.0 (1) is unchanged; no native archive/upload was performed.
