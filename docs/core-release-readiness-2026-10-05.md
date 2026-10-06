# Core release evidence and remaining acceptance — October 5

This source-review checkpoint prepares PR #62 while owner device testing and App Store Connect sign-in are paused. It does not activate subscriptions, publish the candidate, submit to Apple, or establish device acceptance. Public web remains 0.20.122. This draft prepares web/cache 0.20.123 with native 1.0 (9); building native alone still loads the published website.

## What the purchase screen can substantiate

| Item | Current evidence | Remaining boundary |
| --- | --- | --- |
| Team Pro scope and price | One team selected at purchase; restore preserves that binding. Monthly/annual prices come from StoreKit. Settled base prices remain $75 / $269.99. | Actual Apple purchase, restore and resulting access on device. |
| Practice Plans | Deployed server coverage helper protects list/read/save/delete; daily plans, blocks, copies and schedule links exist. | Covered editor use and refund/expiry removal with actual Apple evidence. Requires connection. |
| Wrestler Statistics | Deployed server coverage helper protects authorized reports/history/CSV by team, athlete, style and season. | Covered reports, unauthorized identity/team denial and refund/expiry removal. Requires connection. |
| Other core tools | Existing roster, schedule, messages, scorebooks, ordinary scale/NFC and local pilot video have their own permission/pilot rules. | Their presence is not proof that each is currently gated by Team Pro. Finish the free/paid inventory before activating customer purchases. |
| Free score-only allowance | The handoff preserves the working design of 14 matches per team per day. | This review did not establish shared/offline enforcement. Do not advertise an enforced quota or unlimited paid recording without implementation and acceptance. |
| Video | Historical owner local recording tests remain useful evidence. | Paid recording gates and a deliberate pilot transition remain unresolved. Preserve originals and current pilot access; do not sell cloud/live delivery on this evidence. |
| Deferred services | Family Video, SMS and remote reporting are excluded from launch purchasing. | October 25 is the family/video/SMS goal, not activation. Remote has a separate later schedule. |

The candidate names the two connected tools, connection requirement and ordinary role restrictions before purchase. This is not a new decision to reduce the agreed Team Pro product or declare its final benefit inventory complete. Apple production authorization and purchase activation remain disabled/pending; naming included tools does not grant access. The Plans menu now says Team Pro rather than suggesting Family Video can be purchased.

Purchase information links open embedded privacy/support and Apple's standard EULA. The native external-link rule remains limited to trusted-main-page user taps on the exact approved EULA and Zeffy URLs. The owner's October 5 App Information screenshot confirms Apple Standard License Agreement is selected; no custom agreement was established by adding this link.

## Privacy/provider reconciliation

The public source and embedded support/privacy now share October 5 copy. They describe the deployed deletion service separately from pending native interruption/local-media/preservation acceptance, and explain that deleting an app account does not cancel an Apple subscription. Deletion must not require waiting for that subscription to expire.

| Service/data | Evidence reflected in the draft | Still needed before final App Privacy answers |
| --- | --- | --- |
| Supabase | Auth, authorized app records, private files and billing/access/team binding records. | Complete purpose-specific record/file/log/backup retention and request handling inventory. |
| Apple / Render verifier | Apple purchase processing; Render checks signed transactions/notifications containing identifiers, status, dates and app account token. The verifier is not sent athlete photos, health records or message bodies. | Current provider log/retention configuration and App Privacy classification. Do not retrieve private key values for this check. |
| Hosting, support and notifications | Existing hosting, support and Apple-notification disclosures preserved. | Confirm all active delivery paths/providers and operator access against current deployment. Existing queue code is not evidence of SMS delivery. |
| Local drafts/files/video | Existing feature-dependent, account-scoped local-work disclosures preserved. | Matching native cleanup/preservation round; exported copies have separate handling. |
| Younger athletes | Existing profile/family/messaging choices are distinct from verified guardian authority and younger-child collection consent. | Resolve supported audience/regions and the required notice, verification, withdrawal and child-data process. Age rating alone does not resolve it. |
| Health/shared records | Authorized role limits and request review remain explicit. | Accurate reasons, scope and timing for retained records; no blanket shared-record exception. |

The privacy source remains candid beta information, not a finalized legal policy. The remote 240-hour and future cloud-video 30-day rules must not be assigned to ordinary weight history, messages or all records.

## Moderation evidence and gaps

October 5 read-only inspection of deployed functions, alongside the repository's `20260930214004_parent_approved_team_messaging_020105.sql`, established these boundaries. No messages were sent and no moderation records were changed.

- `private.communication_send_message` checks thread membership/post authority, parent messaging requirements, message length, rate limits and direct-conversation blocks. It calculates a safety level but inserts the message, receipts and notification work without rejecting or quarantining a high-risk message. Flags and safety notices are an after-storage review path. This does not establish pre-publication filtering.
- `set_communication_block` supports same-team user blocking. The inspected send guard applies to direct conversations; it is not evidence of hiding that user's content everywhere in shared groups.
- `report_communication_message` requires message-view authority and records a high-severity user-report flag. Repeated reports for one message use the same conflict key and can replace the report's reporter/note while reopening it. Preserve independent report history before claiming a complete report audit trail.
- `review_communication_safety_flag` permits authorized staff to mark reviewed/dismissed/escalated with a note. This alone does not establish a staffed operator response or a safe escalation route when a report concerns those staff.
- Quiet reviewer history access and revocation are separate from filtering, reports, blocking and operator action. Do not repeat already accepted trainer/parent tests merely to demonstrate a reviewer inbox again.

Apple's user-generated-content review guidance calls for filtering, reporting with timely response, blocking abusive users and reachable contact information. Close or explicitly resolve the delivery/filtering and report-preservation gaps, then use fictional cases to verify the actual routes below. This is a readiness finding, not a claim about Apple approval or SafeSport certification.

References checked October 5:
- https://developer.apple.com/app-store/review/guidelines/ (1.2 and 3.1.2)
- https://developer.apple.com/support/offering-account-deletion-in-your-app/
- https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## Focused acceptance record

Use `launch-acceptance-batch.md` after its engineering prerequisites are ready. Do not start with reinstalling, clearing app data or repeating the isolated remote camera session. Exact current durable review accounts must come from the private review packet; no passwords belong here.

Session metadata: date/time and timezone ___; device/OS ___; installed Apple build ___; loaded web version ___; app account role ___; fictional team ___; connectivity ___. App login and Apple Sandbox Apple Account are separate identities.

| Batch / fixture | Required observation to record | Result |
| --- | --- | --- |
| Team Pro / WM Launch Test | Localized products; cancellation/pending/success; server-confirmed access; original binding through interruption/reopen/restore; no duplicate grant. | Pending |
| Paid tools / fictional records | Protected Practice Plans and Statistics work while covered; expiry/refund removes access; another team/account denied. | Pending |
| Identity lifecycle | Team/account switch, lock and background prevent stale screen/response/private-photo leakage. | Pending |
| Ordinary hardware/cards | Short existing scale/NFC/QR check; athlete PDF saved, reopened and printed at 100%. | Pending |
| Disposable deletion fixture | Cancel before intake; accepted interruption resumes; actual server and local completion; retained account files usable. Never delete durable review/purchase accounts by default. | Pending |
| Moderation / fictional conversation | Report reachable by intended role; independent report details preserved; authorized response and escalation observed; direct block and group scope truthfully shown. Record revised filtering behavior after its engineering work. | Pending |
| Reviewer / synthetic populated history | Covered history/media visible after accepted assignment; no coach/health powers; revocation denies subsequent requests. | Pending |
| Core smoke | Sign-in, familiar navigation, Offline Mat Mode, saved bouts and message safeguards. | Pending |

For a failure, record expected/actual result, role, build and connection state. Retest only affected paths. Remove short-lived Sandbox enrollment after acceptance and clean only designated disposable fixtures through the reviewed process.

## Owner-dependent items

October 5 18:35–18:44 America/Denver screenshots confirm the Paid Apps Agreement,
bank account and W-9 Active; DSA verification In Review; both annual/monthly Team
Pro products and their group Prepare for Submission. Later 18:55–19:04 screenshots
confirm both exact product IDs, durations, U.S. prices ($269.99 annual / $75 monthly)
and English (U.S.) localizations. Monthly shows App Store only and multiseat Not
Allowed; annual's saved correction remains unconfirmed. Both review screenshots
remain empty. See `apple-production-authorization-2026-10-05.md` for the detailed
evidence. Preserve the completed agreement/bank/tax setup.

The owner's signed-in Mac screenshots confirmed app identity, saved receiver URLs and matching active IAP key metadata. A bounded Production recheck at 23:41 UTC still returned 401; a fresh signed Sandbox TEST delivered successfully. The diagnostic is closed at v4. Complete the remaining annual purchase-option and trader-status checks without recreating completed banking or key setup. The dedicated account was confirmed at 19:14 and WM Launch Test created at 19:30 America/Denver. Verified exact-team Sandbox enrollment expires at 22:00; no purchase or paid benefit was created. Once the matching web/native candidate is ready, run one prepared device round. See `sandbox-purchase-acceptance.md`. No owner password or private key is needed in chat.

## Verification of this preparation

Local checks passed for public and embedded launch information, subscription presentation and responsive purchase/restore screens, account/team lifecycle rejection, and web-update recovery with unsaved-work preservation. The four presentation unit tests passed. Native source identity/resource checks and generation checks passed. Screens were inspected with fictional data. These are automated/source checks, not a real Apple purchase or native installation. Full native builds and current-head CI are recorded separately in GitHub.
