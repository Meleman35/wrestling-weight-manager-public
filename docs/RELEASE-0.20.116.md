# Web 0.20.116 — trainer-directed care updates and in-app notifications

Release candidate for PR #52. Hosted migration and GitHub Pages publication must be verified separately; this document alone is not a deployment receipt. Related broader work remains in #51.

## User-visible behavior

The actual family route is Toolbox → Athlete Health. Accepted trainers use New Care Update, then Send to Parents / Guardians for private care or Send to Parents & Coaches for an explicitly shared participation update. Other authorized senders retain Send to Team Trainer. Sharing one new update does not expose older private notes or files.

New care updates, participation decisions and completed private attachments create generic in-app notifications for other currently authorized recipients, excluding the author. Selecting a notification opens the exact concern and highlights the specific update. It is marked read only after opening succeeds. An unread notification has bold red title text plus the word Unread; a color alone is not the status signal. Header, Athlete Health and Board Room entrypoints open the existing inbox. The team badge no longer detours through the team selector.

No health-specific lock-screen alert push, email or SMS delivery is added. Existing native badge synchronization can include eligible unread care notices; a badge update is not alert delivery. No new organization event producers, reviewer-only conversation alerts, due-review jobs or general required-action dashboard are supplied here. Normal guardian, trainer, team and clinical access controls remain separate.

## Verification and dependency review

The complete branch preparation run 36949446436 passed on source f7b03d6e2f4b9d21274e2a4275b4f5ad2629b0cc and materialized output at a22bd6146167f9af9da87ceae6257e49f902e6a7. The artifact SHA-256 is 19ea2341e3d04b534899f094dbacfe1acd7936589bd370fbbfae029df31492f5. The generated migration SHA-256 is 175211ad117f55682e3070d3cb50a13fe2e6c6556ec5ad737d4b341f08f8c02a.

Eleven new database acceptance groups and five new browser groups passed, as did the existing athlete-health database/browser, trainer-dashboard, linked-Creator navigation and public/in-app disclosure checks in that run. Broader pull-request workflows must pass on the final PR head. Fixtures are synthetic; no live account or physical device was impersonated.

An additional dependency audit identified the old SECURITY DEFINER get_communication_notifications endpoint. It now enforces the same current-care predicate as the new table-read policy. Both the existing router body and the health router body are fingerprint-checked before replacement, independently of structural catalog checks. Authenticated and anonymous execution grants are preserved or restricted explicitly; no clinical tables or media are made public.

The production deletion planner was exercised with a notification-only recipient who had not opened a clinical record. It plans only that person's own notice/identity data and leaves the underlying shared care and other recipients untouched. Clinical authors and readers with protected care audit history still receive the existing review-required result. No deletion-worker allowlist or protected clinical dependency was relaxed to make a test pass. No erasure was executed by this test.

Public Privacy and Support pages and their embedded copies are synchronized. The web index and service worker carry the same 0.20.116 version. The original source-generation checks remain enabled. Earlier preparation failures were corrected: the new support block was moved outside the previous generator's contiguous block, and the recipient-only fixture was separated from a clinical reader whose protected read-audit history correctly blocked deletion planning.

Security advisors before deployment reported existing RPC-exposure warnings and disabled leaked-password protection, plus informational locked private tables without direct policies. This is not a clean-security certification. No broad private-table policy was added, and unrelated existing public APIs were not rewritten. Reference remediation guides: https://supabase.com/docs/guides/database/database-linter and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Compare the relevant post-deployment findings before recording completion.

## Deployment and acceptance

Apply only the tested complete supabase/health-notifications.sql via the authorized migration tool, record its returned migration version in source control, and verify the stored functions, access restrictions and deletion/merge catalog afterward. The migration refuses unreviewed schema/body drift and pending deletion work. No existing care note is backfilled or resent.

After publication, use a single new labeled FOLLOW-UP on an existing fictional concern, not another duplicate concern. Send privately as the accepted demo trainer, then inspect the parent inbox and its exact destination; next test explicit participation sharing and the coach's inability to read the older private note. Keep the existing two demo concerns and all actual role acceptances intact. Do not change family sharing choices merely to manufacture a recipient.

Native build, signing settings, local recordings, real memberships, Creator ownership/link, subscription/tester grants, account deletion enrollment and Apple submission are outside this change. No Xcode rebuild is part of this web/backend release. Physical-device, external-push and wider role/action-notification tests remain separate.
