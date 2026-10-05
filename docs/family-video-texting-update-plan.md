# Family Video and texting update goal

Damon approved Team Pro and the core app as the first release on October 4, 2026 at 9:08 PM America/Denver, deferring Family Video with a three-week goal. At 9:10 PM he included texting in that update. Target: **October 25, 2026**. This is a development/release goal, conditional on acceptance and Apple's review; it is not a public availability promise.

Nationwide remote weigh-ins remain a separate later-update workstream. This decision does not automatically assign their launch to October 25.

## First release

- Offer only Team Pro monthly and annual products. Preserve the approved $75/month and $269.99/year prices; actual purchase screens use StoreKit metadata.
- Keep Family Video out of launch navigation and purchase preparation. Retain its implementation and regression tests for the update.
- State that Family Video and texting are not included yet. No unlimited cloud storage, SMS or live-streaming benefit is implied.
- Finish signed Apple billing, notification/reconciliation scheduling, Team Pro acceptance and the consolidated device round before activation/submission.

## Three-week work plan

| Window | Work | Evidence required |
| --- | --- | --- |
| October 5–11 | Complete the core release; finish the Family Video paid-access design and texting provider setup. Inventory existing video and Twilio code, decide storage/SMS allowances and costs, and identify required private owner setup. | Accepted core candidate; precise update benefits and spending limits; server-only provider configuration. |
| October 12–18 | Connect paid video operations and delivery channels while preserving guardian permissions, recorder authorization and notification preferences. Add storage/usage enforcement and reliable delivery/retry behavior. | Cross-account/athlete/team isolation; expired/refunded subscription denial; consent and opt-out enforcement; duplicate/retry and provider-failure checks. |
| October 19–25 | Run one combined update device/provider acceptance round, finish listing/privacy/review materials and submit the accepted update. | Actual Apple sandbox purchase/restore/refund results, authorized recording/playback, approved text delivery and reply/opt-out tests, usage accounting and final build checks. |

## Family Video acceptance

- Preserve approved pricing: $10/month or $75/year, covering up to two selected canonical linked athletes across teams.
- A subscription never replaces an accepted guardian relationship, recording consent, event permission or authorized recorder assignment.
- Replace pilot-only availability with a deliberately tested paid rollout. Verify that an authorized recorder can record a covered athlete without granting Team Pro to the whole team.
- Decide and enforce cloud storage limits, supported upload/playback behavior, file retention/deletion and failure recovery before selling the plan. Never advertise undefined unlimited storage.
- Verify canonical family selection, duplicate roster/profile merges, account changes, cancellation, expiry and refunds. Extra-athlete discounts and live streaming are not silently included.

## Texting acceptance

- Complete the existing Twilio integration; verify the current account, sender/registration requirements and provider configuration when doing that setup. No external texts are authorized merely by this roadmap.
- Obtain the owner's decisions on included SMS usage, overage behavior and a hard spending limit before activation. Count provider-billed message segments, not just app messages.
- Respect current recipient permissions, explicit opt-in, guardian controls, category preferences and quiet hours; implement verified inbound webhooks and opt-out handling before any live campaign.
- Test opted-out/blocked recipients, changed phone numbers, invalid signatures, duplicate callbacks, undelivered messages, retries and replies using designated consenting test recipients.
- Avoid exposing private athlete/health content on lock screens. Text delivery is not an emergency-response guarantee.
- Update the app's availability/pricing disclosures only when the real accepted service and usage limits match them.

Track code and acceptance in the existing repository and PR workflow. Do not recreate Apple agreements/banking, the Render Apple verifier or the restricted database credential; those setup steps already passed.
