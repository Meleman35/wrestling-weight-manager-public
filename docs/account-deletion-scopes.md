# Separate deletion scopes

Product decision: administrator access, personal identity, teams and organizations
are separate choices. Never interpret one as consent to delete the others.

| Choice | Intended effect when fully enabled | Must preserve |
| --- | --- | --- |
| Remove my administrator access | Remove the selected direct team or organization administrator role; hand off sole administration first | Personal account/profile/sign-in, other people, workspace data, other memberships and roles |
| Delete my personal account | Revoke this identity and remove its personal profile/data and memberships across **all** teams and organizations, including inactive ones | Everyone else's personal and athlete profiles, linked children's profiles, teams/organizations unless independently selected |
| Delete a team | Close only the selected team and remove/review its team-only memberships and records | All personal accounts/profiles, shared athlete identity, other team/organization memberships and records |
| Delete an organization | Close only the selected organization and remove/review its organization-only memberships and records after handling linked teams/athletes | All personal accounts/profiles, shared athlete identity, other memberships; linked teams until explicitly selected or transferred |
| Delete all | Combine the requesting person’s personal-account deletion with the explicitly listed and checked team/organization closures | Every other person’s account/profile, linked children, unchecked workspaces, unrelated memberships and shared athlete identities |

These preservation rules apply even when a person has no other team, no other
organization, or has not claimed their athlete profile. A workspace administrator
does not own its members' personal identities. A parent deleting their own account
does not authorize deleting a child's profile. Billing never gates personal
account deletion or these safety controls.

“Administrator account” is implemented as an administrator **role** on an existing
personal account. A direct team role and inherited organization authority can
coexist. Removing the direct role alone cannot promise to remove inherited access.
Removing organization administration must review all teams dependent on it.

## Current release: enrolled administrator removal; erasure still unavailable

v0.20.99 connects **Remove my administrator access** to a real server transaction
for the existing privately enrolled phone tester. The other four choices remain
previews: there is no deployed personal, team, organization or combined erasure
worker. `deletion_enabled` stays false. A separate `actions.administrator` capability
enables only the role RPC; it cannot activate any erasure scope.

The RPC derives the caller from Auth, repeats the verified-session/enrollment gate,
requires exact `delete`, and locks membership changes before checking authority and
administrator continuity. Confirmed, active, non-managed alternatives are required;
an invitation alone does not count. Removing a direct team role may proceed while
the caller retains organization administration. The result explicitly says that
inherited access stays.

Team head coaches become assistant coaches. Existing assistant-coach or manager
participation keeps unrelated permissions while `team_admin` is removed. Multiple
memberships cannot overwrite guardian/athlete roles or collide with an existing
active assistant-coach row. An inactive assistant-coach conflict blocks for review
rather than being reactivated. Organization removal deletes only the caller's
organization administrator membership; direct team memberships remain.

Role changes and a private per-caller request receipt commit together. Retrying
the same request returns its original receipt, including after a later regrant;
it cannot repeat the old removal or target a different workspace. Receipts contain
no other person's identity or credentials and cascade with the requesting account's
eventual deletion. The phone refreshes membership access after success and drops
late responses after account changes. Existing role-approval triggers still run.

This completes one server action, **not the account-deletion project**. Installing
the migration changes no real role or account. A fresh explicit confirmation is
required to invoke the role action.

### Earlier preview and preservation guards

v0.20.98 provides five distinct preview choices in the existing bottom dropdown.
Team/organization/role actions require an explicit server-returned target. Delete
all starts with all currently returned administrative workspaces checked, displays
that complete list, and allows exclusions. The final dialog lists the requesting
person’s personal account and the exact checked workspaces. Selecting Delete all
is an explicit combined choice; it does not authorize deleting other people. A
personal-only account can preview personal deletion; administrative actions are
disabled when no matching targets exist. Each warning explains what stays and
what the eventual action affects. In v0.20.98 all confirmations remained default-off,
required exact lowercase `delete`, and created no requests, consent, jobs or data writes.

The existing argument-free `account_deletion_scope_preflight()` reuses the existing
private enrollment and live-session check. It returns only the current caller's
administrative workspace IDs/names, direct/inherited role flags, handoff warnings,
and linked-record counts. It does not disclose other members' identities. A
returned option is **not** an execution grant. Existing `phone_preflight` remains
unchanged for older clients. Both APIs are read-only.

Two existing foreign keys allowed organization deletion to cascade into `teams`
and `athletes`. The new migration changes those relationships to `ON DELETE
RESTRICT`, without deleting or modifying rows. An organization with either kind
of linked row now cannot be deleted until a reviewed operation preserves or
rehomes that data. Do not restore cascades to make deletion “work.” This change
may cause a pre-existing direct organization delete to fail, intentionally.
The snapshot guard checks the expected old constraint definitions before changing
them; schema drift must be reviewed, not silently overridden.

These two constraints are targeted safeguards, not proof that every deletion
trigger, function, retained record or media path is fully covered. No organization
or team deletion worker is enabled by this release.

## Delete all and people left without a team

Delete all includes the requesting person's account; it preserves everyone else's
account. It never means all users, all athlete profiles, all storage, or all teams
that the person merely belongs to. A personal-only account uses Delete my personal
account; the combined option is disabled without an administrative workspace.
An empty combined selection cannot proceed. Refreshing roles resets the selection,
and changing any included workspace closes and clears the typed confirmation.

A retained personal account with no active team uses the existing sign-in/setup
path. It keeps its identity and reaches Join a Team / Create a Team without a new
signup. The setup text now says that explicitly. Existing invitation, role and
server permission checks continue to apply; workspace removal does not confer
administrator rights to create or join anything. People with surviving memberships
continue to use those memberships. No future erasure operation may revoke all
members' Auth sessions as part of team/organization closure.

For a future combined execution, authorize every target separately and bind the
reviewed target set to the confirmed request. Deduplicate teams reachable both
directly and through an organization. Never expand that set later to new teams or
new members. Explicitly selected child teams may be closed as separate scoped
steps before closing their organization. Unselected teams and shared athlete rows
must instead be preserved/re-homed. Keep the RESTRICT guards. Last-admin handoffs
are needed for surviving workspaces, not workspaces explicitly being closed.

The combined operation needs durable per-scope progress and safe retry behavior;
it must not report global success when only some steps finish. Revoke the deleting
person's access and complete shared-record preservation before final Auth removal.
It must route only the requesting person's identity to personal/device cleanup.
These combined-erasure requirements remain unimplemented; v0.20.98 adds the preview and
regression coverage, with no server mutation or worker activation.

## Required execution boundary

The unfinished worker/intake in draft PR #25 is personal-account work only. Do not
route team, organization or role choices into its Auth-user erasure adapter. Do
not reuse an old personal-account confirmation as consent for workspace closure.
The new native PIN/biometric/offline cleanup adapter is also **personal identity
only**: role or workspace removal must not erase a user's login credentials.

Before enabling mutation:

1. Capture a versioned, explicit scope, authenticated actor, exact targets and
   fresh typed confirmation. Recheck authority, live session, memberships and
   last-administrator continuity inside the locked execution transaction. Client
   claims, local storage, creator/uploader fields and preview results are not grants.
2. Scope plans must enumerate their own records and independently identify shared
   records. Team/org plans must have zero personal/Auth/global-athlete identity
   deletions, including profiles belonging only to that workspace. Reject unknown
   ownership and retain/rehome linked athlete rows before organization closure.
3. Last administrators must transfer responsibility to an eligible accepted adult
   or separately choose workspace closure. An invitation alone is not acceptance.
   Account deletion must never silently close a team/org; a reviewed Delete all
   list is explicit authorization for only its selected workspace scopes. Role removal should
   preserve non-admin participation where applicable; the final role mapping is
   implemented for the enrolled role handler above; identity erasure remains unfinished.
4. Organization plans must explicitly handle every linked team and athlete row.
   Preserve teams by default; any team closure requires its own reviewed scope, either separately
   or explicitly included in the combined confirmation. Rehoming must preserve other affiliations and histories.
5. Personal plans must cover the deleting person's identity everywhere, while
   preserving other people and their shared history. Shared records may need
   anonymization instead of cascading removal. Linked children are independent
   people; guardian continuity needs review.
6. Finish provider/session revocation, record/media removal, durable retries,
   bounded local cleanup, absence verification and truthful completion receipts.
   Test two people sharing multiple teams/organizations, people with only one
   membership, unclaimed profiles, role changes during confirmation, multi-device
   retries and all existing access entry points before release.

## Verification limits

The v0.20.99 tests execute the role migration, actual production permission/role-
approval trigger bodies and the multi-role unique index with synthetic rows. They
cover privilege denial, continuity, multiple memberships, receipt privacy, retries,
later regrants, rollback and preserved personal/shared records. Chromium exercises
the bundled phone flow, including ambiguous responses, pending controls and account
switching. No production mutation is invoked to test a real person's role.

PGlite executes the real two migrations against synthetic catalog-shaped tables.
It checks caller isolation, direct/inherited roles, last-admin warnings, personal-
only access and foreign-key preservation of cross-team athlete records. Chromium
checks the actual web bundle at phone width using synthetic responses. These are
bounded regression checks, not live erasure, full-schema or physical-phone tests.
