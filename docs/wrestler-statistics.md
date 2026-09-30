# Wrestler statistics

The Statistics tab and athlete-profile buttons display completed scorebooks by wrestler, represented team, style and season. Career means all recorded seasons within the selected team. Related roster identities are combined only through the existing persistent athlete profile ID. Team and style data never merge implicitly.

Reports include wins/losses, win rate, points for/against, averages, finish types, scoring actions and points, period scoring, points by recorded starting position, match history and CSV export. Reports derive from saved Match Book and athlete-video scorebooks; no new athlete records or camera data are stored. Live, practice, challenge and camera-test records are excluded. Revisions and the same match ID across both scorebook sources count once. Undone events, corrections, no-contests and near-fall adjustments are handled explicitly. Unlabeled legacy points and unrecorded positions remain labeled unknown. Attempts, riding time, tournament team points and proprietary ranking formulas are not inferred.

## Paid launch boundary

Paid subscriptions are not connected in this app. `private.wrestler_statistics_covered(team_id)` intentionally returns false until the verified Team Pro entitlement service replaces this adapter. Roles, client flags, recording access and family-video coverage do not prove Team Pro coverage. No subscriptions, billing, trial grants or existing pilot access are changed.

Until that integration is complete, the released UI offers only a clearly labeled fictional preview. The real reporting endpoint, calculations and UI are implemented and tested with synthetic paid coverage. Real team statistics are not activated yet. Connect paid coverage, test expiration/refunds/restores, and optionally authorize a named test pilot before promising paid launch readiness. The feature is Team Pro; Family Video does not independently unlock team coaching statistics.

## Privacy and maintenance

Every real request rechecks a confirmed, non-deleted, non-banned personal account and team/athlete authority. Team staff see authorized team wrestlers; linked guardians and athletes see their own. Managed recorder/shared logins and anonymous users are denied. Parent view reduces coach access. Records omit private notes and reset history. Account/team changes clear reports; outdated responses are ignored. Export escapes spreadsheet formulas.

The migration creates only functions, avoiding new personal storage and changes to the deletion inventory. There is no statistics cache or offline promise: real reports require server access; existing saved scorebooks remain the source of truth. The UI bounds reports to 5,000 matches and asks for a season beyond that bound.

Validation: `tests/wrestler-statistics.cjs`, `tests/wrestler-statistics-db.cjs`, and `tests/wrestler-statistics-browser.cjs`. The SQL test uses actual migration functions and simulated coverage in an isolated PGlite database. Never apply the synthetic adapter to production. Embed sources with `python3 scripts/patch-wrestler-statistics.py` and verify with `--check`.
