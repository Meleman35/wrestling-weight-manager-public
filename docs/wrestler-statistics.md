# Wrestler statistics

The Statistics tab and athlete-profile buttons display completed scorebooks by wrestler, represented team, style and season. Career means all recorded seasons within the selected team. Related roster identities are combined only through the existing persistent athlete profile ID. Team and style data never merge implicitly.

Reports include wins/losses, win rate, points for/against, averages, finish types, scoring actions and points, period scoring, points by recorded starting position, match history and CSV export. Reports derive from saved Match Book and athlete-video scorebooks; no new athlete records or camera data are stored. Live, practice, challenge and camera-test records are excluded. Revisions and the same match ID across both scorebook sources count once. Undone events, corrections, no-contests and near-fall adjustments are handled explicitly. Unlabeled legacy points and unrecorded positions remain labeled unknown. Attempts, riding time, tournament team points and proprietary ranking formulas are not inferred.

## Paid launch boundary

As of October 5, the deployed `private.wrestler_statistics_covered(team_id)` delegates to `wm_billing.team_feature_covered`. The helper checks verified Team Pro coverage, current session and permission, payer/deletion state, expiry/refund/grace and reviewed paid-team remainder rules. Roles, client flags, recording access and Family Video do not prove Team Pro coverage.

Customer purchases remain disabled. An uncovered team receives the fictional preview. The hosted purchase route is Sandbox-only and requires short-lived enrollment for the exact account and team; enrollment alone grants no access. Real Apple purchase/restore, protected report access and refund/expiry removal still need the consolidated device acceptance. The implementation and isolated tests are not evidence of a completed customer purchase. College Pro and trial preferences are not activated entitlements.

## Privacy and maintenance

Every real request rechecks a confirmed, non-deleted, non-banned personal account and team/athlete authority. Team staff see authorized team wrestlers; linked guardians and athletes see their own. Managed recorder/shared logins and anonymous users are denied. Parent view reduces coach access. Records omit private notes and reset history. Account/team changes clear reports; outdated responses are ignored. Export escapes spreadsheet formulas.

The migration creates only functions, avoiding new personal storage and changes to the deletion inventory. There is no statistics cache or offline promise: real reports require server access; existing saved scorebooks remain the source of truth. The UI bounds reports to 5,000 matches and asks for a season beyond that bound.

Validation: `tests/wrestler-statistics.cjs`, `tests/wrestler-statistics-db.cjs`, and `tests/wrestler-statistics-browser.cjs`. The SQL test uses actual migration functions and simulated coverage in an isolated PGlite database. Never apply the synthetic adapter to production. Embed sources with `python3 scripts/patch-wrestler-statistics.py` and verify with `--check`.
