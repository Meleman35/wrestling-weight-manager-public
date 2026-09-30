# Native deletion integration — draft

The live Safari flow has passed its enrolled-account test. This branch adds the web half of a native deletion integration. It is **not a native release**. Do not merge until the private Xcode counterpart builds and the device acceptance below passes; bump the web/service-worker version at that point.

The new app handler receives the original immutable request, verifies the signed-in identity against the fixed Auth endpoint, shows its own destructive confirmation, and persists a device-only Keychain journal before starting the existing server job. It resumes through the original receipt and independently verifies server completion before removing reviewed account-owned local video, biometric sign-in and profile PIN data. Old app builds keep the Safari-only restriction.

The browser controller waits for native cleanup confirmation, clears only the matching account's offline slots, drafts, PIN record, preferences and matching login hint/token, then acknowledges completion. A durable native completion receipt permits retry after the acknowledgement response is lost. Another account's session, saved data and active scoreboard stay intact.

## Gates and boundaries

- The new Swift sources remain private. The public repository contains no native ZIP, signing data or native source.
- Swift syntax parsing and Foundation fixture execution are not an Apple SDK build, Security/Keychain verification or a WKWebView device test.
- Shared legacy Mat Mode records, unscoped share files and unknown saved-login ownership block native intake. No blanket WebKit, UserDefaults, Keychain or filesystem wipe is used. Resolving these records for general release remains separate work.
- Existing server enrollment, last-administrator, shared-profile and unreviewed-data checks remain enforced. This branch neither enrolls new accounts nor expands server deletion support.
- Exported Photos/Files copies and data on another physical device require their own handling. Do not claim that this build cleans every device or external copy.
- A new test account must be deliberately enrolled after creation; the previous Safari test identity no longer exists. Never enroll or delete a real primary account to perform this test.

## Acceptance before activation

1. Build the complete private Xcode draft for iOS/iPadOS and the supported Catalyst target. Preserve signing, the tested scanner file, the scale package and the actual next-unused Apple build number.
2. On a controlled test device, use only a disposable enrolled identity. Verify the native confirmation email and exact selected workspaces. Cover cancellation, an interrupted request and restart, and completion after sign-out.
3. Test matched and unknown Keychain ownership, locked-device failures, profile PIN cleanup, local video across teams, busy/canceling video operations and another account's retained data. Confirm shared Mat Mode and unsupported files block before any server request.
4. Run the bundled web browser regression and inspect real provider/database completion for the disposable request. Verify a stale token cannot access data.
5. Reconcile any Apple build/device findings, rerun checks, bump the web version and make a deliberate scoped enablement decision. Do not simply remove the old-native guard.

Automated web integration fixtures live in `tests/account-deletion-native-client.cjs`. They execute the actual controller with a simulated native transport and do not substitute for the private Swift or phone tests.
