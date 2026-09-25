# Wrestling Manager 0.20.40

Adds a **Goals** tab beside Team Board, Trophy Case and Team in Locker Room. It uses the same server-backed goals as Clipboard and the athlete/profile buttons. Coaches can enable goals and configure categories through **Locker Room → Goals → Coach goal settings**. Existing team settings are preserved.

Athletes and linked parents can edit active goals, mark a goal accomplished, and choose **Set a new goal**. A gold star and “Goal accomplished!” appear after a confirmed save. Replacement clears that goal slot and retains the accomplishment text in history. Unchecking an incorrect completion retracts its star and permits editing. Existing completed goals receive an unknown-date history entry when next saved/replaced; no completion date is invented.

Active teammates, coaches and existing team leaders can view goals; linked parents see their own children. A linked parent can explicitly enable **Show these goals on my athlete’s profile**. This is off by default and includes current goal text/completion marks and future edits. The profile must also be shared. Accomplishment history, removed template slots and internal goal metadata are excluded from the broader profile projection. **What others see** uses the same filtered projection. Revoked guardian authority suppresses that approval's projection.

## Schema and authorization

Applied server migration: `20260925022527_athlete_goal_accomplishments_02040.sql`.

- `private.athlete_goal_accomplishments`: original goal text/category, server completion time/actor, retained history and correction/retraction state.
- `private.athlete_goal_profile_sharing`: per-team/per-athlete opt-in, approving parent, revision and update time.
- Both tables have RLS and no direct PUBLIC/anonymous/authenticated table access. Guarded existing RPCs remain the entry points; the new projection helper has direct execution revoked and an empty search path.
- Goal writes use the existing team settings lock plus expected settings/goal revisions. Replays and stale writes cannot generate duplicate accomplishments. Profile-sharing changes serialize first creation and check the expected sharing revision.
- `private.wrestling_profiles_request` is preserved except for adding the filtered shared-goals field to profile views. Existing profile blocking, discoverability and preview rules still apply.
- Existing account/team switching invalidates goal requests. Unsaved goal edits show a warning; failed or lost responses retain the writing and allow reloading server state. A lost response does not trigger a false celebration.

## Verification

- 35 embedded JavaScript syntax checks and 35 preservation comparisons outside the goals module's explicit integration points. Embedded goals source matches `src/athlete-goals.js`; the profile RPC's existing body is preserved apart from its new projection. Digest: `validation/goals-source.json`.
- 15 isolated PGlite database test groups: revisions, retries, replacement history, correction, teammate/parent/coach scope, tenant separation, profile opt-in/off, template removal, blocked/private profiles, revoked guardian authority and denied direct table/helper access.
- Eight whole-page Chromium groups at phone/tablet widths using the real SQL RPC bodies in PGlite. Covers the Locker Room tab, completion celebration, replacement, lost-response recovery, correction, sheet/tab reuse, parent sharing and profile preview. Screens inspected locally. The test environment lacks some existing app emoji fonts; the new gold accomplishment star renders as a text symbol.
- Ten connected-server checks through the authenticated database role: completion, stale-save rejection, replacement, teammate visibility, parent scope, profile projection, tenant separation, direct-table denial, direct-helper denial and guardian revocation. Every synthetic fixture was rolled back. Before/after counts of users, organizations, existing goal settings and saved goals matched. No test account login credentials, invitations or sessions were created.
- Security advisor: the two new private tables report the expected informational [RLS enabled with no direct policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), consistent with RPC-only access and revoked table grants. Existing project-wide warnings are outside this change.

At commit preparation the server migration and live database checks are complete. Frontend publication must be verified against the GitHub Pages workflow and exact live file digest. No native code, Apple upload or actual Safari/device testing is included. Existing login/invitation behavior, Mat Mode, meetings/voting, signed agreements and unrelated modules are preserved. Real team goal settings and athlete profile-sharing choices were not changed by this release.

Run local checks with Node, Playwright/Chromium and PGlite available:

```sh
python tests/check-goals-source.py
node tests/goals-db.cjs
node tests/goals-browser.cjs
```

`PGLITE_MODULE` and `CHROMIUM_EXECUTABLE_PATH` may identify installed dependencies. The browser suite intercepts network requests. `tests/goals-live-rollback.sql` requires the installed migration and a privileged test runner; it creates synthetic fixtures only inside an explicit rolled-back transaction.
