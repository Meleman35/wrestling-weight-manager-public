# Coach practice plans

Practice & Competition → Practice Plans opens the monthly coaching workspace. A scheduled practice has a Practice Plan button that loads its existing plan or prefills a new one using the team's timezone. Coaches can write a daily focus, optional start time and target length, and ordered activity blocks with minutes and instructions. Running times and the total update as blocks change. A saved plan can be copied to a new date; the copy receives a new ID and does not inherit the scheduled-event link. The schedule, attendance, RSVP and notifications are never changed by a plan save or delete.

## Paid feature

The user explicitly requires paid access. Every real list, read, event, save and delete checks `private.practice_plans_covered(team_id)` on the server. This delegates to the existing closed Team Pro statistics coverage adapter. Billing is not connected: production coverage remains false, with a clearly labeled fictional sample instead of a functioning free editor. There is no client override, automatic trial start, creator override or video-pilot inheritance.

Connect the common adapter to verified Team Pro/College Pro entitlements and eligible active seven-day full-feature trials when billing is implemented. Family Video alone does not unlock team coaching tools. Validate purchases, restores, refunds, expiry, revoked coverage and trial eligibility before activating customer access. Synthetic paid/trial coverage exists only in isolated tests, never in this migration or production data.

## Authorization and storage

Plans are shared by the team's active head and assistant coaches, managers with team-admin permission, and organization administrators through the existing staff predicate. A confirmed, non-banned, non-deleted personal account and a current Auth session are required. Athlete, parent, trainer, team-mom, managed and anonymous contexts cannot access plans solely through those roles. No new invitations or messages are sent.

`private.practice_plans` has RLS and no direct client table privileges. A narrow invoker RPC delegates to an empty-search-path private router. Event links are same-team practice events, unique per event; cross-team IDs are rejected. Bodies and blocks are bounded and validated. Plans can be saved with zero blocks as a draft. A plan supports 40 blocks, up to 240 minutes each and 720 minutes total. Saved revisions reject concurrent stale edits. A retry of the identical request returns the original result; a retry after a later revision cannot overwrite it.

Drafts are held only in memory, with an unsaved indicator and explicit save. Closing the sheet retains an unsaved draft for the same account/team; closing the app loses it. Identity, team, role, app-lock or server authorization changes clear private content. Offline saves are rejected, not queued. Reloading a plan to resolve an edit conflict requires confirming the loss of the unsaved draft. Notes are escaped on render.

Plan deletion leaves the scheduled practice. Event deletion unlinks its plan. Team deletion deletes team plans. Personal coach deletion nulls authorship and preserves shared team work; other people's personal profiles are untouched. The migration refreshes the entire reviewed deletion catalog and exact athlete-merge fingerprint, and registers the deletion freeze trigger. The deletion worker policy explicitly enrolls team plan deletion and nullable authorship edges.

## Verification

`tests/practice-plans-db.mjs` exercises actual RPC code in isolated PostgreSQL, including paid/trial loss, authorization, session validity, retries, revisions, date/time rules and foreign-key deletion behavior. `tests/practice-plans-compatibility.mjs` applies the complete migration atop the reconstructed schema and invokes the actual deletion planner. Browser tests exercise free preview, paid editing, timings, copying, failed connections, stale edits, permission changes and 320/390/768px layouts. No real customer account or team is created, edited or deleted by validation.

Rebuild with `python3 scripts/assemble-practice-plans.py` and `python3 scripts/patch-practice-plans.py`; both accept `--check`.
