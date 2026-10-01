# Enrolled native deletion phone pilot

The owner reported a successful Apple build of the private Scale & NFC Cleanup Xcode project on September 30, 2026. Physical-device acceptance is still pending. This change makes that acceptance test reachable from the live app; it is not general native-deletion activation.

The web controller builds on draft PR #35. New native requests require a fresh `account_deletion_scope_preflight` response for the exact signed-in subject and chosen scope. The existing private, expiring tester enrollment and all worker authority, schema, shared-record and administrator-handoff checks remain in force. No account identifiers, emails or enrollments are embedded in this release. Server configuration and public enrollment permissions are unchanged.

The app's native bridge independently authenticates the account, presents its own confirmation and persists the immutable request before server intake. Completion requires matching server proof and native cleanup confirmation; only then does the web controller clear the matching account and acknowledge. Recovery uses the original receipt even after Auth deletion or enrollment expiry. Older native builds are blocked on both start and recovery, with no browser-only fallback inside the app.

My Account is now reachable from team setup so a disposable account need not join a real team. Account deletion stays at the bottom of that sheet.

## Phone acceptance

1. Keep the working Xcode project backup. Run the successfully built private app on the phone.
2. Sign in with only the deliberately enrolled disposable account. Verify its email. Do not enroll or delete a primary or Creator account.
3. From team setup, open My Account, expand Account deletion, and choose the personal account. Review counts. Exercise cancellation first; verify the account still works.
4. Start again, type `delete`, and verify the native confirmation names the same account and intended scope. Confirm on the phone. Resume the same request if the response is interrupted.
5. Require both server completion and app cleanup confirmation. Verify the deleted identity, sessions, selected records/files and the matched local data are gone, while other accounts' data remains. A login failure alone does not prove all cleanup.

Unknown Keychain ownership, shared legacy Mat Mode records, unscoped share files and busy video operations must continue to block intake rather than erase unrelated material. Exported Photos/Files copies and other physical devices are outside this device's cleanup. Do not remove blockers by wiping someone else's data.

Cancellation, interruption/relaunch, matched and unknown saved-login ownership, local recordings, profile PIN, locked-device failures and retained data for another account remain physical-device release checks. A single empty-account test is only the first acceptance case. General native activation remains disabled pending those checks.

Automated tests exercise the actual controller and full embedded app with a simulated native bridge. They do not claim Apple SDK, Keychain, filesystem or physical-device verification.
