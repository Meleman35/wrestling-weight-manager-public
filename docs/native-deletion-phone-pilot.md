# Enrolled native deletion phone pilot

The owner reported a successful Apple build of the private Scale & NFC Cleanup Xcode project on September 30, 2026. The first disposable personal-account deletion has now completed on the device, with server completion independently checked. This is one acceptance case, not general native-deletion activation.

## Verified progress — October 1, 2026 UTC

The owner reported the app's account-and-record deletion completion message. Read-only server checks found the personal deletion job completed at 04:22:09 UTC, no remaining Auth identity or sessions for the disposable test account, and both the primary and Creator accounts still present. This confirms the tested personal-account path; it does not establish every data-heavy, interruption, or shared-team case. Device cleanup confirmation was observed by the owner, not independently inspected with Apple device tooling here.

Private native fixes used during that test added scoped test-Mat-data clearing behind PIN and typed confirmation, and corrected biometric authentication context handling for Keychain cleanup. Preserve that working Xcode project and its current signing/build settings. The older full-project archive alone does not include all of these follow-up fixes.

Web v0.20.111 routes plain Mat Mode links to the installed app's existing Offline Mat Mode screen. The browser scorebook now shows an empty-history message and cannot export an empty list. Active web sessions retain their exit-PIN route, including when the native shell is present. This web update does not require another Xcode build. On the next device check, open Mat Mode from sign-in and Account and confirm that the Offline Mat Mode screen appears; an already-active web session must be exited with its PIN first.

## Pilot boundaries

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
