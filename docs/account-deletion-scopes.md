# Separate deletion scopes

Product decision: administrator access, personal identity, teams and organizations
are separate choices. Never interpret one as consent to delete the others.

| Choice | Intended effect when fully enabled | Must preserve |
| --- | --- | --- |
| Remove my administrator access | Remove the selected direct team or organization administrator role; hand off sole administration first | Personal account/profile/sign-in, other people, workspace data, other memberships and roles |
| Delete my personal account | Revoke this identity and remove its personal profile/data and memberships across **all** teams and organizations, including inactive ones | Everyone else's personal and athlete profiles, linked children's profiles, teams/organizations unless independently selected |
| Delete a team | Close only the selected team and remove/review its team-only memberships and records | All personal accounts/profiles, shared athlete identity, other team/organization memberships and records |
| Delete an organization | Close only the selected organization and remove/review its organization-only memberships and records after handling linked teams/athletes | All personal accounts/profiles, shared athlete identity, other memberships; linked teams until separately selected or transferred |

These preservation rules apply even when a person has no other team, no other
organization, or has not claimed their athlete profile. A workspace administrator
does not own its members' personal identities. A parent deleting their own account
does not authorize deleting a child's profile. Billing never gates personal
account deletion or these safety controls.

“Administrator account” is implemented as an administrator **role** on an existing
personal account. A direct team role and inherited organization authority can
coexist. Removing the direct role alone cannot promise to remove inherited access.
Removing organization administration must review all teams dependent on it.

## Current release: preview plus database preservation guards

v0.20.97 provides four distinct preview choices in the existing bottom dropdown.
Team/organization/role actions require an explicit server-returned target. A
personal-only account can preview personal deletion; administrative actions are
disabled when no matching targets exist. Each warning explains what stays and
what the eventual action affects. All confirmations remain default-off, require
exact lowercase `delete`, and do not create requests, consent, jobs or data writes.

The new argument-free `account_deletion_scope_preflight()` reuses the existing
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
   Account deletion must never silently close a team/org. Role removal should
   preserve non-admin participation where applicable; the final role mapping is
   still to be implemented and reviewed.
4. Organization plans must explicitly handle every linked team and athlete row.
   Preserve teams by default; any team closure requires its own reviewed scope and
   confirmation. Rehoming must preserve other affiliations and histories.
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

PGlite executes the real two migrations against synthetic catalog-shaped tables.
It checks caller isolation, direct/inherited roles, last-admin warnings, personal-
only access and foreign-key preservation of cross-team athlete records. Chromium
checks the actual web bundle at phone width using synthetic responses. These are
bounded regression checks, not live erasure, full-schema or physical-phone tests.
