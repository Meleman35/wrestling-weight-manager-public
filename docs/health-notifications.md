# Care-update notifications and trainer sending

Status: development candidate for issue #51. Not deployed. The hosted web baseline remains 0.20.115. Native code, live permissions, existing care records and notification preferences are unchanged by preparing this branch.

## Reported problem

The owner confirmed the actual parent route is **Toolbox → Athlete Health**. Trainer-created concerns saved but generated no notification. The initial trainer form also incorrectly said **Send to Team Trainer**, even when the signed-in user was the accepted trainer. Repeating the form created a second case rather than testing delivery. A narrow read-only check found two copies of the explicitly fictional PRIVATE NOTE 01. Both were left unchanged; no clinical or test record was deleted or replayed.

## Candidate behavior

- An accepted trainer sees **New Care Update**. The default is **Send to Parents / Guardians**, with **Send to Parents & Coaches** available when explicitly selecting a shared participation update. Parent/athlete/coach submissions retain **Send to Team Trainer**. UI copy describes visibility, not an email delivery guarantee.
- These two choices preserve the existing visibility model: private updates are available to accepted trainers, authorized family/athlete accounts, and their submitting account; participation updates also admit authorized staff. A separate coach-only channel that hides records from otherwise authorized family is not added. Selecting the shared audience affects only the new update, never previous private notes or attachments.
- Each newly saved update produces one in-app notice per other currently authorized recipient, excluding the sender. This covers concern creation, follow-up updates, participation decisions, and successfully completed private attachments. Role names alone do not grant authority. No notice is sent to a Team Mom/reviewer solely because of that position, and organization administration alone grants no private clinical access.
- The existing notification inbox/read state and badges are reused. The notice has generic copy, no child name, diagnosis, note excerpt, photo, file path or weight. An opaque recipient-owned notification ID resolves to the exact concern/update only after current-session and permission checks.
- Clicking a care notice opens and highlights that update in the concern; it is marked read only after the authorized content loads. Reading does not accept a role, clear a concern or record medical clearance. Revoked access hides the notice from the inbox and badge count and rejects the old link.
- Visible Notifications entrypoints are added to the ordinary team header, Athlete Health, and Board Room. The team-header unread badge opens the inbox without first opening the team chooser. Red bold unread titles are paired with an explicit **Unread** label; the highlighted concern update is not presented as a diagnosis or urgent severity.
- Save results distinguish a stored update with in-app notices, a stored update with no other authorized recipients, and an older backend without the new notification contract. Idempotent retries must preserve the original content and must not create repeated notifications. A deliberately new form submission is still a new concern; use a follow-up update on the existing concern instead.

## What this does not deliver

No new alert push, email, SMS, due-review scheduler, baseline notice, third-party delivery, automatic reminder or routine conversation-reviewer alert is enabled. Existing native badge synchronization still uses the shared unread count. A badge is not proof of an alert arriving on a phone. The external alert channel and native tap-to-open need a separate, consent/preference-aware implementation and signed-device acceptance. No emergency-response promise is made.

This candidate does not backfill old care updates or resend the duplicated test cases. New clinical event handling in the generic inbox needs disclosure review before release. The old privacy/help wording that there are no care alerts must not be silently contradicted by publication; update it to distinguish in-app notices from external alert delivery.

## Security and compatibility

`communication_notifications.health_update_id` points to the source update; it does not grant access. Current recipient eligibility mirrors the existing case/update read rules and also excludes deleted, unconfirmed, banned, managed, or deletion-frozen accounts. The RLS policy requires the current authenticated session for health notices. New restrictive insert/update policies prevent a broad unrelated client policy from forging a health notice. Public resolver is SECURITY INVOKER over a private authenticated implementation, without a caller-controlled recipient.

The generated migration refuses unknown structural drift or pending deletion jobs. It registers the complete structural catalog and updates only the previously reviewed athlete-merge fingerprint. Existing clinical-record deletion/merge restrictions stay intact. No new table or deletion-worker allowlist entry is required; deleting a notification cannot delete its source health update. Before deploying, recheck the live router body and source, schema, RLS policies, any delivery-worker dependencies and advisors. Inspected baseline router body SHA-256: `1ebc7e3c0121f8ed763fa017b8ef8bd50dee5ea1c264e19c32b8b3bdfe180a8c`.

## Validation and activation

The branch preparation builds deterministic source, then runs original athlete-health database/browser regressions, new recipient/privacy/idempotency/RLS tests, notification navigation tests, and trainer/Creator regressions using only synthetic fixtures. Run results must be inspected; this document is not a claim those checks passed.

Before release: review successful current-head tests and phone-sized captures, strengthen any fixture limitations, run a fresh live source/advisor read, apply the coordinated migration, record its tool-generated migration version, update disclosures, assign a paired web/service-worker version, and verify deployment. Only then test one NEW labeled follow-up update on an existing demo concern. Do not repeatedly create concerns while waiting for notifications. Keep all real accounts, current native signing, saved recordings, privacy boundaries and billing/tester state unchanged.
