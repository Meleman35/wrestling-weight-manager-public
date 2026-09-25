# Wrestling Manager 0.20.41

Unread notifications now remain visible across teams and organizations. The top-right team selector shows the total, each team has its own tappable unread badge, and Messages points out updates in other teams. Opening an update switches to its team before routing. A filtered inbox marks only that team's updates read. Current-team rendering no longer overwrites the global count.

Messages support one saved reaction per person and message. Tap **React** or press and hold a message to choose wrestling and team emoji, including 🤼 💪 🔥 🏆 🥇. Tap the selected reaction again or choose **Remove my reaction** to remove it. Counts refresh across open conversations. Reactions use the existing personal account, team, thread, blocking and parent-control permissions; read-only guardian mirrors can view reactions. Deleted messages and safety simulations cannot receive reactions. A private event history records changes. Reactions do not generate separate push alerts.

Signup, confirmation, resend and join screens remind recipients to check Junk or Spam for confirmation emails, invitations and team codes. The reminder also travels with invitation emails and shared invitation text. Copy Link continues to copy a clean URL.

Validation:

- 13 whole-page Chromium checks at 390px width passed, including cross-team routing, more than 200 unread rows, filtered read state, account changes, long press, replace/remove and recovery from a lost save response.
- 10 isolated SQL test groups passed, including parent restrictions, blocked conversations, revoked access and private-table denial.
- Live database validation passed 11 checks using synthetic users without credentials or email. The transaction rolled back; no synthetic organizations remain and no delivery functions were called.
- All 36 inline JavaScript blocks passed syntax checks. Rebuilding from version 0.20.40 is reproducible and idempotent. Mat Mode, authentication callback, app.js and styles.css are unchanged.
- Supabase security advisor reviewed. The new private tables intentionally deny direct access; the signed-in security-definer RPC intentionally enforces permissions before accessing them. See [RLS guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) and [RPC guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Build verification is recorded in `validation/communications-041-source.json`; live checks are in `validation/reactions-live.json`. Migration filename matches the applied Supabase version (CLI scaffold created before application).

This is a web release. Physical iPhone/TestFlight behavior and actual email delivery were not tested. Existing native badge delivery remains in place.
