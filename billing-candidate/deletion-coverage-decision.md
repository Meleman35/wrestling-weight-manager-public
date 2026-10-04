# Approved paid-team deletion behavior

Owner approved October 3, 2026: if the purchaser deletes their personal account, preserve Team Pro only through the already paid period, provided another authorized administrator remains. Family coverage ends with its owner.

Implemented server policy candidate: team-paid-remainder.mjs. It stores only team/environment/plan/paid boundary/revocation/version; no purchaser ID, account token, receipt or athlete link is copied. Current remaining-admin authority is required when creating and using the grant. Later renewals cannot extend the paid boundary. Verified refunds revoke access; old active evidence cannot undo them. Seven focused checks pass.

Canonical remaining-admin permission must follow the live public.is_team_admin definition inspected October 3: active head coach, active assistant coach/manager with team_admin permission, or organization_admin membership. Reject deleted/banned/managed/deleting identities and deleted team/organization.

The policy is not yet attached to the production deletion worker or live entitlement resolver. Deployment requires private remainder storage, atomic billing deletion/grant creation, mapping refunds after purchaser deletion, full catalog/schema integration, and removal of the grant on expiry/team deletion. Do not treat this policy file as a deployed entitlement.

Deletion remains immediate. Explain Apple billing cancellation and link https://apps.apple.com/account/subscriptions. Reference: https://developer.apple.com/support/offering-account-deletion-in-your-app/
