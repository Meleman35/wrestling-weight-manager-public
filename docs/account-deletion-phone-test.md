# Private phone setup, v0.20.98

This separate release provides a read-only inventory in Account & Team for a
privately enrolled, verified personal account. It does not ship the unfinished
PR #25 deletion worker, access policies, invitation changes or intake UI.
`deletion_enabled` is a constant false. There is no mutation RPC.

The inventory now sits at the bottom of Account & Team, below Sign Out and above
the build footer, in a collapsed Account deletion dropdown. Its last button,
Delete Account, opens a labeled confirmation preview with a warning, Cancel,
and an exact lowercase `delete` field. Confirm deletion enables only for that
exact phrase; both the button and Enter run the same guarded submit handler.
This release always reports that deletion is unavailable and nothing has been
deleted or scheduled. The dialog prominently states this before typing. It does
not store consent, send a request, sign out, remove data, or enable erasure.
Cancel/Escape, account changes, backgrounding, lock, and refresh clear the dialog
and typed input. Returning to the sheet starts with the dropdown collapsed.

Enrollment is an expiring private row keyed by Auth user ID. No tester identity
belongs in public source. Anonymous users and ordinary authenticated clients
cannot read or change enrollment. The argument-free RPC derives the user from
verified gateway claims and additionally checks a matching live Auth session,
token expiry, confirmed email, ban/deletion state and non-managed identity.
The original RPC returns aggregate counts. The new scope RPC additionally returns
IDs/names of teams and organizations the caller administers, role-source flags,
handoff warnings and linked-record counts. Neither returns message contents,
media paths or other member identities.

The current account can refresh profile-photo references, sent-message and
uploaded-attachment counts, authored posts and their attachments, upload-owner
object counts, memberships, guardian links and organization roles. Counts overlap.
An upload-owner count is not an approved list of objects to erase. This view is
not an exhaustive personal-data inventory and does not inspect phone storage,
provider logs, backups, embedded JSON or linked-child ownership.

The administrator warning mirrors team-admin and organization-admin membership
rules and excludes inactive memberships and banned/deleted alternative users.
It is advisory. A zero does not prove a successor has accepted responsibility
or that account deletion is safe. Team closure is not authorized by this view.

The UI clears on auth notifications, app lock, background/page exit, and reopening
the sheet. Request generation, user and access-token checks reject late results.
Errors clear displayed counts. An unenrolled account sees no test card. No
inventory is persisted in local/session storage, IndexedDB or service-worker cache.

## Verification and release

Run `python3 scripts/patch-deletion-phone-test.py --check`, the existing schedule
embedding check, and both `tests/account-deletion-phone-*.cjs` tests using the
pinned `.ci` dependencies. Database tests execute this actual migration against
minimal synthetic table shapes in PGlite. Browser tests execute the actual bundle
at phone width with mocked responses. Neither is physical-phone or full deletion
acceptance. Existing schedule, parent, reviewer and offline workflows must pass
on the release head. Apply the additive default-off migration before releasing
the UI; enroll only the explicitly authorized test account with a short expiry.

## Remaining deletion work

PR #25 remains disabled. It still needs complete access/provider/session shutoff,
reviewed record and media removal, team/guardian continuity, provider absence
checks, reliable fulfillment/confirmation, and full synthetic end-to-end testing.
A separate private native preparation ZIP now contains unmounted cleanup adapters;
Apple SDK/device validation and full integration are still needed. In particular,
saved biometric credentials and account-scoped local movies are not covered by
the browser offline-store draft. Preserve the current project and signing; an
archived native ZIP is not a replacement. Showing this screen does not resolve
these release gates or establish that any data has been deleted.

## Scope choices and preservation

The bottom dropdown now separates personal deletion, administrator-role removal,
team deletion and organization deletion. See [account-deletion-scopes.md](account-deletion-scopes.md)
for the accepted semantics, new read-only RPC and organization cascade guards.
The guards preserve linked teams and athlete records by rejecting unreviewed
organization deletion. No records were erased by installing them. Every action
in this preview remains disabled; typed confirmation does not authorize work.

## Combined Delete all preview

Delete all includes the requesting person's personal account and a visible list of
currently eligible teams/organizations. All listed workspaces start checked;
people can uncheck those they are keeping. The final warning repeats only the
checked targets and explicitly preserves everyone else's personal/athlete
profiles. Retained last-admin workspaces still need a handoff. No new RPC, request,
consent or deletion is performed. The existing database preservation guards remain.

The browser suite also runs the existing account refresh path for a retained
personal profile with no memberships and a stale active team. It verifies that the
person stays signed in, keeps the same profile, clears the stale team and sees
Join a Team / Create a Team without signing up again. This is a synthetic UI test,
not a real organization/account erasure or physical-phone acceptance test.
