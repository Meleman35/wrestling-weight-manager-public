# Paid team coverage when a purchaser deletes their account

Decision needed before production billing/deletion integration.

Verified production finding: scoped_deletion_schema_hash and the current deletion catalog enumerate public/private schemas. The new wm_billing schema is outside that inventory. Do not deploy it without explicit deletion handling.

Current candidate behavior: deleting/frozen purchaser accounts suppress both team and family subscription access. A personal-account deletion could therefore interrupt a whole team's paid tools even if another authorized administrator remains.

Recommended team behavior for approval:
- Personal account deletion continues immediately; never require cancellation or an administrator transfer to complete deletion.
- Show Apple's subscription-management link and explain that deleting the app account does not cancel Apple billing.
- An existing paid team's access continues only through the already verified paid expiry/grace boundary, subject to current team permissions and team/organization deletion.
- Do not extend this team grant from future renewals after purchaser deletion. A remaining authorized admin can arrange the next subscription.
- Family athlete coverage ends when its owner account is deleted.
- Remove personal profile/guardian links. Retained team access state must be explicitly minimized and covered by the final privacy/deletion design; no indefinite financial retention is authorized by this proposal.

Alternative:
- End both Team Pro and Family Video access as soon as the purchaser deletes their account, even if another team administrator remains.

Implementation after the owner chooses:
1. Update entitlement/deletion policies and notice together.
2. Register every wm_billing table in the deletion workflow; reject unknown schemas/tables during preflight.
3. Test deletion with paid team, remaining admin, expired/refunded purchase, family slots, queued notifications and simultaneous delivery.
4. Re-run deletion acceptance and billing CI before deployment.

Apple reference:
https://developer.apple.com/support/offering-account-deletion-in-your-app/

Private signing key: owner reports APPLE_IAP_PRIVATE_KEY successfully saved in Supabase October 3, 2026. Its presence/signing validity has not yet been verified by a deployed runtime. Never fetch or display it.
