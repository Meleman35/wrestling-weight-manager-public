# Parent choices by email — v0.20.92

This feature lets a parent or legal guardian approve limited profile edits for a coach-verified athlete aged 13–17 without a parent account. It is not an under-13 consent mechanism, a waiver of required permissions, or a replacement for the app's messaging safeguards.

## Use

1. Athlete joins normally and opens their athlete profile. They can create a parent invitation under Family Connections.
2. Coach opens the athlete's access screen from the roster, saves/selects the guardian contact, verifies the guardian relationship and email through established records or direct conversation, and checks the athlete birth date.
3. Coach checks the verification statement and chooses **Verify for parent browser choices**. An email supplied solely by the teen is insufficient.
4. Create the parent invitation and choose **Email**. The Email button sends the private browser choices only to the saved recipient. Copy, Text and Share remain account invitations.
5. Parent chooses **Join as a parent**, or explicitly approves teen-managed routine profile edits. Photos require a separate opt-in. No reply grants nothing.
6. Parent can request a management link at `/parent-browser.html` to review or withdraw permission. To revise choices, withdraw and ask for a fresh invitation. Joining later restores precedence to account-based parent controls.

Name, contact details, contact sharing, profile visibility, medical/team records, messaging, follows, recordings, payments and other protected permissions are not delegated. A teen whose parent remains outside the app must still obtain parent account review for protected changes. Browser approval does not unlock adult–minor messaging: current chat rules still require a connected guardian.

## Safeguards

- Service-only RPC behind 256-bit emailed bearer capabilities; database stores only SHA-256 token hashes. Inviting users never receive these capabilities. Link fragments are removed immediately, kept in memory, and excluded from app storage, referrers and service-worker caches.
- Opening/previewing a link never creates an Auth account or approves a permission. Auth starts only after explicit **Join**, with verified recipient matching before the app session handoff.
- Invitation links expire within seven days or sooner when their underlying invitation expires. Management links expire in one hour. Replacement approval emails revoke prior unused approval links.
- Actual guardian email, effective birth date, team connection, verified staff authority and shared profile mapping are rechecked. Reverification requires a new approval. Any linked parent account takes precedence; any valid browser withdrawal blocks automatic approval across externally verified guardians.
- Explicit acknowledgment, fixed notice version, receipt and audit record. Retry of the same decision returns its historical receipt without reapplying it after withdrawal.
- Withdrawal and publishing lock the same profile row. Photo publication rechecks approval after upload; withdrawal cannot be bypassed using a pending photo request.
- Recovery returns the same response for unknown, known and rate-limited recipients. Delivery is limited per address and globally. No email addresses or tokens appear in client error details.

## Deployment and rollback

Apply `20260929114400_parent_browser_approval.sql` (disabled by default). Deploy `parent-browser` with gateway JWT verification disabled because the handler validates emailed capabilities; deploy `send-member-invitation` with its existing JWT verification enabled. Both include `_shared/parent-tokens.ts`.

Publish the tested web version before enabling `private.parent_browser_settings.enabled`. With the flag off, profile policy falls back to the previous implementation and parent invitation emails use the existing account-invitation flow. Existing accounts and invitations remain available. No native/Xcode changes are required for this web/backend feature.

Validation: actual migration plus existing prepare/submit/publish functions in PGlite with synthetic identities; mocked Edge/Auth/Resend tests; Chromium page and session-handoff tests; existing signup, email, profile approval, parent controls and offline browser suites. No real messages or user deletion in testing. These checks do not substitute for a parent opening a real delivered email on a device.

## Follow-up: quiet adult reviewer

Damon proposed Hadley as another adult who can review coach–athlete messages and images without routine notifications. Existing linked parents already have **Yellow and red alerts only** while retaining read access. A non-guardian reviewer is a separate role, not parental authority.

Do not assign Hadley automatically or add her as another athlete's guardian. A future reviewer workflow should use her verified personal adult account, team approval, explicit scope, visible participant/reviewer identity, appropriate family authorization, revocation and audit records. Routine alerts may be muted while safety alerts remain available. No blanket access to all team conversations, no removal of required safeguards, and no claim that silent access alone satisfies an external sport policy. Current release does not add this reviewer role.
