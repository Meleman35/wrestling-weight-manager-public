# Data Retention and Deletion Policy — Product Draft

**Draft for implementation and legal review. Do not publish as a final promise until the backend enforces these rules.**

## Principles

1. Keep data only while needed for the stated product, safety, legal, accounting, or dispute-resolution purpose.
2. Use shorter retention for higher-risk youth information.
3. Separate account deletion from deletion of records that legitimately belong to a team/organization or another guardian.
4. Delete or irreversibly de-identify data when the purpose expires unless retention is legally required.
5. Tell users what is retained and why.

## Proposed operational schedule

| Data type | Proposed default |
|---|---|
| Unaccepted invitation tokens | Expire automatically; purge shortly after expiration |
| Auth/session tokens | Provider/session lifecycle; revoke on logout/security event/deletion |
| Failed/abandoned signup metadata | Purge after a short operational window |
| Profile photos superseded/rejected | Purge after review/rollback window |
| Private messages/attachments | Retain while account/team relationship requires them, subject to safety/legal hold and deletion rights |
| Match videos | Product-controlled retention; family/team policy must be explicit before cloud rollout. Temporary uploads/orphans purged quickly |
| Weight/weigh-in history | Retain only for team/athlete operational/history purpose; guardian/user deletion rules must distinguish shared competition records |
| Medical/clearance documents | Minimum necessary period tied to season/legal need; then delete securely unless law/policy requires longer |
| Signed contracts/forms | Retain for contract/legal/audit period disclosed to user |
| Team attendance/results | May remain as legitimate team records after a member leaves, with unnecessary personal fields removed where feasible |
| Security/audit logs | Limited security/fraud window, then delete/de-identify unless legal hold |
| Billing/tax records | Statutory/accounting retention period |
| Support requests | Support/dispute window, then purge/de-identify |
| Deleted-account identifiers | Minimal suppression/security record only where necessary; do not keep the full deleted profile |

## Deletion workflow

1. User starts Delete Account from Account/Privacy settings.
2. Re-authenticate or otherwise verify control of the account.
3. Show consequences and distinguish:
   - personal-account deletion;
   - child-profile request;
   - shared family/team records;
   - organization-owned records;
   - subscriptions.
4. Create a deletion job with auditable status.
5. Revoke active sessions/tokens and disable sign-in promptly.
6. Remove/de-identify profile, contact fields, photos, posts, private media and other deletable user-generated content.
7. Apply child/guardian scope rules.
8. Remove unused storage objects and derived thumbnails/caches.
9. Notify processors where deletion must propagate.
10. Preserve only legally/operationally required records with restricted access and documented reason.
11. Confirm completion without exposing sensitive retained data.

## Legal hold

A legal/safety hold must be narrow, authorized, logged, reviewed, and released when no longer necessary. A hold should not become a reason to retain unrelated account data indefinitely.
