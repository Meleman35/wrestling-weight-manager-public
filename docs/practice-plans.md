# Coach practice plans

Practice & Competition → Practice Plans opens the monthly coaching workspace. A scheduled practice has a Practice Plan button that loads its existing plan or prefills a new one using the team's timezone. Coaches can write a daily focus, optional start time and target length, and ordered activity blocks with minutes and instructions. Running times and the total update as blocks change. A saved plan can be copied to a new date; the copy receives a new ID and does not inherit the scheduled-event link. The schedule, attendance, RSVP and notifications are never changed by a plan save or delete.

## Paid feature

Every real list, read, event, save and delete checks `private.practice_plans_covered(team_id)` on the server. As of October 5, the deployed adapter delegates to `wm_billing.team_feature_covered` through the shared statistics coverage helper. Verified Team Pro billing is connected; a client flag, role, Creator access or video pilot does not grant coverage. An uncovered team sees a clearly labeled fictional sample instead of a free editor.

Customer purchases remain disabled. The hosted route accepts only genuine Apple Sandbox evidence for an explicitly enrolled account and exact team during its short enrollment window. Enrollment alone grants nothing. Actual purchase, restore, refund/expiry and real-device editor acceptance remain pending. College Pro and the seven-day trial preference are not activated entitlements; Family Video does not unlock team coaching tools. Synthetic coverage belongs only in isolated tests.

## Authorization and storage

Plans are shared by the team's active head and assistant coaches, managers with team-admin permission, and organization administrators through the existing staff predicate. A confirmed, non-banned, non-deleted personal account and a current Auth session are required. Athlete, parent, trainer, team-mom, managed and anonymous contexts cannot access plans solely through those roles. No new invitations or messages are sent.

`private.practice_plans` has RLS and no direct client table privileges. A narrow invoker RPC delegates to an empty-search-path private router. Event links are same-team practice events, unique per event; cross-team IDs are rejected. Bodies and blocks are bounded and validated. Plans can be saved with zero blocks as a draft. A plan supports 40 blocks, up to 240 minutes each and 720 minutes total. Saved revisions reject concurrent stale edits. A retry of the identical request returns the original result; a retry after a later revision cannot overwrite it.

Drafts are held only in memory, with an unsaved indicator and explicit save. Closing the sheet retains an unsaved draft for the same account/team; closing the app loses it. Identity, team, role, app-lock or server authorization changes clear private content. Offline saves are rejected, not queued. Reloading a plan to resolve an edit conflict requires confirming the loss of the unsaved draft. Notes are escaped on render.

Plan deletion leaves the scheduled practice. Event deletion unlinks its plan. Team deletion deletes team plans. Personal coach deletion nulls authorship and preserves shared team work; other people's personal profiles are untouched. The migration refreshes the entire reviewed deletion catalog and exact athlete-merge fingerprint, and registers the deletion freeze trigger. The deletion worker policy explicitly enrolls team plan deletion and nullable authorship edges.

## Practice review and athlete sharing candidate

The Locker Room shows up to three current/upcoming plans and the most recent
prior practice for authorized coaches. Each block can be marked completed or
for review next practice, with a private follow-up note. These are explicit
saved edits using the same retry and revision protections as the plan.

Coaches can open historical months, start a new plan with selected unfinished
or review activities, or review a previous practice while editing another plan.
Completed moves can be selected for retention practice. Copied activities get
new IDs, unchecked completion/review flags and editable durations. Their original
practice stays saved; new plans start with athlete sharing off.

“Allow athletes to view this plan” is an optional per-plan coach setting,
off by default. Active personal athlete accounts on the same covered team can
list/read only shared plans through a separate read-only RPC. They receive title,
date, start/target time, focus and ordered activity instructions, never coach
notes, completion/follow-up fields, authorship or unpublished plan metadata.
Parents, trainers and managed team logins receive no new access. Every request
rechecks current membership, session, paid coverage and the sharing setting.

The Locker Room refreshes while visible, clears on identity/role/lock/offline
changes, and shared-plan readers recheck every 30 seconds. Changing a sharing
setting cannot retract screenshots or exported copies.

Apply the new CLI-created migration only after review; it adds one default-false
boolean column and review fields inside the existing block JSON. It preserves
private RLS storage and the deletion freeze, and refreshes the complete deletion
catalog and exact existing athlete-merge fingerprint atomically. Historical
migrations are unchanged.

    python3 scripts/assemble-practice-review.py --check
    python3 scripts/patch-practice-plans.py --check

This is a proposed change, not evidence of deployment or real-device acceptance.

## Verification

`tests/practice-plans-db.mjs` exercises actual RPC code in isolated PostgreSQL, including paid/trial loss, authorization, session validity, retries, revisions, date/time rules and foreign-key deletion behavior. `tests/practice-plans-compatibility.mjs` applies the complete migration atop the reconstructed schema and invokes the actual deletion planner. Browser tests exercise free preview, paid editing, timings, copying, failed connections, stale edits, permission changes and 320/390/768px layouts. No real customer account or team is created, edited or deleted by validation.

Rebuild with `python3 scripts/assemble-practice-plans.py` and `python3 scripts/patch-practice-plans.py`; both accept `--check`.
