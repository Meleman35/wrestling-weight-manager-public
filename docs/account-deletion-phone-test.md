# Private phone setup, v0.20.95

This separate release provides a read-only inventory in Account & Team for a
privately enrolled, verified personal account. It does not ship the unfinished
PR #25 deletion worker, access policies, invitation changes or intake UI.
`deletion_enabled` is a constant false. There is no delete button or mutation RPC.

Enrollment is an expiring private row keyed by Auth user ID. No tester identity
belongs in public source. Anonymous users and ordinary authenticated clients
cannot read or change enrollment. The argument-free RPC derives the user from
verified gateway claims and additionally checks a matching live Auth session,
token expiry, confirmed email, ban/deletion state and non-managed identity.
Only aggregate counts for that user are returned; no message contents, media
paths, recipient identities or team names are disclosed.

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
Phone cleanup also needs the actual current scanner-patched native project:
saved biometric credentials and account-scoped local movies are not covered by
the browser offline-store draft. Preserve the current project and signing; an
archived native ZIP is not a replacement. Showing this screen does not resolve
these release gates or establish that any data has been deleted.
