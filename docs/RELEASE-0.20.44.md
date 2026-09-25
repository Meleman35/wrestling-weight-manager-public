# 0.20.44 — Team plan foundation and inventory access

Draft based on `work/tournament-alerts-043` at `625c65619e40fa0288fc953e80cd07d7b53f08b7`. Published main remains 0.20.42. The 0.20.43 migration is still a prerequisite and was not applied by this work.

## Why

The app has no team billing records. A future coach-level paid flag would let a subscription follow the coach into unrelated teams. Also, Clipboard Equipment and Files still open placeholder messages despite existing resource modules.

## Changes

- Bind one subscription to one team ID and one unique provider reference. A second team starts without a paid subscription. Renaming a team or replacing its coach preserves coverage on that team.
- Add private, RLS-enabled settings, subscriptions and an event ledger. Billing events require trusted database execution, validate time ranges, reject changed replays and stale revisions, and write the subscription plus ledger atomically. Existing team rows serialize first grants. No provider signature or receipt validation is claimed.
- Expose only an authenticated, permission-checked team-plan projection. It excludes payment references, denies managed logins/unrelated teams, rechecks family access and distinguishes pilot access from an actual subscription. Cancellation retains an otherwise valid term; past-due, revoked, expired and future terms do not grant paid access.
- Add Team Plan to Account and Clipboard Settings. Purchases are unavailable. No price has been hardcoded or product created. Late responses cannot overwrite another team or account; errors clear previous status, and locks close the screen.
- Connect Equipment and Files to existing modules. Equipment mutations enforce plan access in `private.wm_resources`, retaining original staff checks. Free/expired teams can read permitted inventory and export CSV; formula-like text is escaped in exports.
- Keep the pilot enabled by default. Only Equipment is connected to the new premium check in this draft; see `PAID-LAUNCH-READINESS.md` for remaining components and launch blockers.

## Validation

- 17 isolated SQL groups exercise team separation, account/guardian revocation, permissions, replay/conflict handling, cancellation/expiration/renewal, denied raw access and direct helper bypass attempts.
- 11 whole-page Chromium groups use the actual new SQL and captured resource functions with synthetic accounts. They cover phone layout, plan states, stale responses, managed/kiosk changes, inventory writes, CSV download and Files navigation.
- 8 existing navigation/copy browser groups, 6 tournament-preference browser groups and 13 communications browser groups passed.
- 390px phone screenshots inspected. All 41 inline scripts parse; clean-base and repeated builds are reproducible.
- Native-facing `app.js`, `styles.css`, `mat-mode.html`, `auth-confirm.html`, privacy and support files are unchanged.

Tests use PGlite 0.5.8, Playwright 1.62.1 and Chromium 138 in this workspace. Set `NODE_PATH` to the installed PGlite/Playwright modules and `CHROMIUM_EXECUTABLE_PATH` when using a custom browser. Run:

```sh
python scripts/build-launch-044.py
node tests/team-plan-db.cjs
node tests/team-plan-browser.cjs
node tests/navigation-042-browser.cjs
node tests/tournament-alerts-043-browser.cjs
node tests/communications-041-browser.cjs
```

## Deployment and limits

New migration: `20260925173201_team_plan_foundation_02044.sql`, generated with Supabase CLI 2.118.0. **Not applied to hosted Supabase.** It refuses to overwrite the existing resource function if its body has changed since capture. Rebase that function and revalidate if this guard fails; do not bypass the guard.

No web publication, native archive, purchase, payment webhook, provider request or background delivery job was made. True concurrent database sessions, payment-provider verification, iOS CSV export, StoreKit purchase/restore and a new physical-device run remain unverified. Do not treat the synthetic event applicator tests as successful real payments.

The hosted security advisor was read without changing production. Existing advisory groups remain: private RLS tables intentionally lacking client policies; anonymous/authenticated executable definer functions; and leaked-password protection. This is not a clean production-security signoff. Remediation references: [RLS policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [anonymous definer execution](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [authenticated definer execution](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Run the advisor again after any approved hosted migration.

The September 25 Supabase changelog was checked. Its Postgres minor-release notice concerns ltree/btree_gist indexes, legacy pgcrypto ciphers and custom operators; this migration introduces none of those. No database upgrade was performed.
