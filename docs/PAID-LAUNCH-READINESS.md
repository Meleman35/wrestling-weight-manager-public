# Paid launch workboard

Updated September 25, 2026. This is an implementation workboard, not a customer price list or a claim that the app is ready to charge customers.

## Product boundaries

- One annual subscription covers one stable team ID. Authorized coaches, parents and athletes share its benefits. Accounts do not carry paid team access to newly created teams.
- Team names, head coaches and seasons can change without changing the paid team. Existing team service levels can represent JV/varsity or age groups within that program; creating a separate team does not share coverage.
- Keep TestFlight free. The server pilot setting is deliberately enabled in this draft. It applies to the pilot app, including its web view; the browser cannot claim to be TestFlight to obtain access.
- Core communication, parent controls, athlete privacy and authorized reads of saved records stay available on Free. Paid access never grants a new role or permission.
- $199/team/year was discussed as a working price, not a configured product. Final price, renewal terms and launch feature list remain to be approved before checkout is built.
- SMS usage and any external-provider charges need explicit pricing. Do not promise unlimited SMS or include an unapproved USA Bracketing service in a paid offer.
- A school/organization bundle would need a fixed number of assigned team slots. No organization billing or transferable team license is implemented here.

## Components and next work

| Component | Free boundary | Proposed Full Year addition | What exists / what remains |
| --- | --- | --- | --- |
| Accounts, roles and family links | Personal accounts, team membership, linked guardians, privacy controls | Shared team coverage | Existing access system; new team-plan projection tested in 0.20.44. Complete account deletion and lifecycle handling before public launch. |
| Messages / Whistle | Core chat, important announcements, safeguarding and ordinary notifications | Scheduling and advanced delivery tools | Existing chat, scheduling UI, reactions and inbox. Separate premium scheduling from always-free safety paths and verify every server write path. |
| Schedule and attendance | Events, reminders, RSVP and basic attendance | Season reporting, attendance analysis and bulk workflows | Existing event and attendance tools. Audit reports, finish missing reports, and attach server checks to paid actions. |
| Roster and seasons | Basic roster and family access | Imports, administrative workflows and season rollover tools | Roster import and team service levels exist. Verify roster rollover, shared-athlete history and paid write boundaries. |
| Goals and profiles | Personal goals, accomplishments, sharing controls | Coach reporting and progress analysis | Goals/accomplishments built in 0.20.40. Reporting scope and premium checks still need work. |
| Weight Room | Basic permitted weight entry and supported scale use | Team trends, bulk workflows and exports | Existing scale/kiosk, trends and official-sheet tools. Device-only official sheets still require export before reinstall; do not advertise governing-body submission. Decide exact paid boundaries and test on iPhone/iPad and scales. |
| Forms and agreements | Receive, sign and retain permitted copies | Template authoring, assignments and administration | Editor, signatures and saved PDF records exist. Connect paid authoring checks without blocking family signatures, medical access or previously signed records. |
| Equipment | View existing permitted inventory and export it | Add, issue, return and remove inventory | Connected and enforced in 0.20.44. Existing module tracks aggregate quantities; individual athlete assignments, due dates and replacement charges are additional work. |
| Files and photos | View permitted team files and profile sharing | Advanced team file administration | Existing file module now opens from Clipboard. Define paid storage/administration boundaries and verify upload limits. |
| Mat Mode and Match Book | Basic scoring access | Saved team records and reporting | Existing scoring, match records and native/offline paths. Preserve offline behavior; define paid save/sync/export handling and verify native code. |
| Tournament Day | Basic manual information and safe athlete views | Team tracking and eventual background alerts | 0.20.42 manual board is published; 0.20.43 preferences and private alert drafts remain an unpublished dependency. Real phone delivery and USA Bracketing ingestion are unfinished. |
| Recruiting | Basic profile and privacy controls | Team recruiting reports and exports | Profiles are present. A complete paid recruiting workflow has not been verified or implemented by this draft. |
| Organization / officials | Existing authorized access during pilot | Future organization/event license | Meetings, voting and organization tools exist. Separate licensing, team slots and officials pricing remain future work. |

## Work completed in 0.20.44

1. Private subscription records keyed by team ID; unique provider subscription reference prevents reuse across teams.
2. A trusted-SQL event applicator with duplicate-event detection, revision checks, team row locking and atomic audit writes. It has no browser or service-role execution grant and is not a payment verifier.
3. Server-derived paid, pilot and Free access; term start/end, cancellation, expiration, past-due and revocation behavior.
4. Team Plan in Clipboard → Settings and Account. It clears stale results after account/team/lock changes and cannot accept local payment flags.
5. Equipment is the first integrated premium component. Its underlying private resource function checks access on every mutation. Authorized reads and CSV export remain available after expiration; the original staff checks still apply.
6. Clipboard Equipment and Files open their real modules. Inventory CSV export escapes spreadsheet formulas.

**Enforcement coverage is currently Equipment only.** The presence of a team subscription does not mean every proposed paid module is protected. Keep the pilot enabled and checkout unavailable until the remaining paid routes, direct table policies, background jobs and native paths are covered and tested.

## Launch blockers, in order

1. **Finish free/paid boundaries and server enforcement.** Work through Forms, roster imports, attendance/reporting, scheduled messages, saved match workflows and team administration. Test both existing paid data and new writes after expiration. Preserve safeguards and role checks on every plan.
2. **Complete account lifecycle.** The current privacy page explicitly says the full in-app account-deletion process is unfinished. Build the verified deletion flow, ownership handoff, shared-child record handling and retention/export behavior; replace beta policy text with approved launch documents.
3. **Select and implement the purchase route.** Confirm annual pricing and the Apple/web sales model. Build verified receipts or signed webhooks, environment/product validation, purchase-to-team assignment, restore, duplicate-purchase prevention, renewal/cancellation, refunds and reconciliation. Add a reviewed replacement/transfer flow that never leaves two teams covered. The private event applicator is only the final database step.
4. **Finish tournament delivery if included at launch.** Apply the 0.20.43 draft only through its release procedure. Add send-time authorization, freshness, quiet-hour handling, delivery retries and inbox/badge integration before enabling phone alerts. USA Bracketing requires the partner approval, credentials, payload contract and sandbox described in Damon's request.
5. **Prepare production operations and native release.** Resolve commercial hosting, monitoring, support, data recovery and the live security-advisor baseline. Verify the actual Xcode project, native purchase/restore behavior if applicable, device access, account deletion, offline scoring and exports. Build and submit a new release through App Store Connect; this workspace does not contain the Mac Xcode project.

Apple's current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) cover subscriptions in 3.1.2, other purchase methods in 3.1.3, and account deletion in 5.1.1. Organization-paid access does not by itself establish eligibility for the enterprise exception. The distribution and customer model must be evaluated before implementing checkout. Checked September 25, 2026; recheck before submission.

## Release sequence

Keep these changes in draft while the app remains in TestFlight. Review 0.20.43 first, then 0.20.44. Before a web deployment, apply the pending migrations in order, validate the hosted APIs and run security advisors. Do not disable the pilot simply because a TestFlight build expires: ending pilot access is an explicit launch operation after billing, data-access and device checks pass.

No production subscription, invoice, purchase product, charge, external message or USA Bracketing request was created by this work.
