# Account-deletion availability — 0.20.118

## Scope and remaining blocker
The account-deletion entry belongs in My Account above Sign Out for signed-in personal accounts, including accounts before team setup. It must not disappear merely because the pilot is unavailable or the initial capability request fails. This release changes visibility, error/retry handling and test coverage only. It does NOT enable general account deletion, approve a pilot account, start a request, change server authority or alter native code.

The menu shows checking, unavailable, offline, error or the verified account's existing controls. Unavailable/error states show no inventory or destructive confirmation. Capability checks time out after 12 seconds; late responses cannot restore stale counts. Refresh immediately clears prior data and actions. Sign-out, lock, page exit and identity changes retain their existing cleanup guards. Existing admitted-account actions still require separate server capabilities, typed confirmation and native identity/ownership checks.

## Validation
Use scripts/prepare-deletion-availability.py and --check. The availability suite extends the existing full embedded account UI regression rather than substituting a shallow fixture. It covers initial denial/error, malformed replies, offline retry, timeout/late result, stale inventory and narrow screens. Existing cancellation, original-request recovery, another-account preservation, scoped planner/service/handler and browser tests remain required. Automated native tests use simulated transport and are not physical iPhone/Keychain verification. Successful CI, merge and Pages deployment must each be recorded separately.

## Next release gate
General activation remains held for unperformed device acceptance and protected/shared-record handling. The uploaded archive was inspected separately as native 1.0 (7); that does not identify the currently installed phone build. Preserve the working private project; do not post Swift source or credentials to this public repository. Never use the owner's primary/Creator accounts, real workspaces or durable Apple review logins as disposable deletion subjects.

Use two fresh disposable synthetic identities for cancellation/recovery and preservation, then separate synthetic team/organization fixtures for the additional destructive scopes. Do not bypass ownership guards or delete unrelated local data to force a pass. A visible unavailable entry is not a working public deletion flow or evidence of App Store readiness. Apple's guidance requires actual in-app initiation, completion handling and accurate retained-data disclosures: https://developer.apple.com/support/offering-account-deletion-in-your-app/
