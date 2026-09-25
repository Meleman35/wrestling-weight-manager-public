# Organization leadership invitations — 0.20.45 draft

Organization leaders currently have to enter through team-oriented onboarding or an existing connected-account selector. This draft lets an organization administrator invite a leader by email from **Organization → Leadership invitations**. No team membership, athlete profile, or parent connection is needed.

## Agreed boundaries

- Affiliates do **not** receive paid plans from an organization. Affiliation and paid team coverage remain separate.
- Organization billing will cover only specifically eligible managed teams through the separate paid-launch design. This change does not create, move, or activate any subscription or paid entitlement.
- One personal account can hold team roles and organization leadership roles separately.
- A title never implies administrator access. The administrator chooses the access grant explicitly.

## Administrator workflow

1. Open Organization → Leadership invitations → Invite organization leader.
2. Enter the recipient's email.
3. Choose **Leadership position** or **Organization administrator**.
4. For a position, select an existing vacant adult position and choose its operational permission. Its organization/division scope and existing meeting/voting permissions appear before creation. Create missing vacant posts in Positions first.
5. Confirm adulthood and the displayed permissions, then create the invitation.
6. Use Email invitation or Copy link. Email submission has explicit success/failure states and retries retain the same invitation.

The saved list shows pending, accepted, expired and revoked invitations. A pending link can be revoked. Raw tokens are not recoverable from the list; losing a link requires revoking and replacing it. Create retries in the same open form reuse a random request ID and 256-bit token.

## Recipient workflow

Open the WMO invitation link, sign in or create a personal account using the invited email, and confirm that email. The link survives the existing signup/confirmation flow on the same device. On another device, reopen the original invitation link after confirming the account.

Before accepting, review the organization, title, scope, operational access and meeting/voting permissions. Confirm adulthood and acceptance. An organization-only account can open its organizations directly from the signed-in landing screen; team setup remains optional. Acceptance opens the invited organization.

## Access and removal

| Choice | Grant | Removal |
| --- | --- | --- |
| Organization administrator | Existing full organization administrator role, including administration of managed teams and leadership invitations; no automatic voting-position appointment | Another administrator can remove this organization role. At least one administrator must remain. |
| Leadership position | Assigns the vacant position and explicitly selected operational permission in its recorded scope; preserves existing meeting/voting flags | Clear or archive the assignment under Positions. |
| Affiliate | No invitation-derived subscription or managed-team grant | Existing affiliate directory controls remain separate. |

Removing one role leaves other independently granted team or organization roles intact. Removing an administrator revokes invitations they created that are still pending. Revoking a pending invitation does not remove an already accepted role. A previously accepted token can never recreate a removed role.

This uses existing organization permission checks. It does not add a new granular team-insights dashboard, organization checkout, or a new read-only analyst role.

## Backend controls

- Private RLS-enabled invitation table; only SHA-256 token hashes persist. Tokens stay out of invitation lists and audit records.
- An authenticated, personal-account RPC verifies organization administrator authority for creation, list, email authorization, revocation and administrator removal.
- Acceptance requires the matching confirmed email from `auth.users`, not an editable metadata role. Known minor or undated athlete identities and managed/shared logins are rejected. Adult checkboxes are recorded attestations, not identity verification.
- Pending invitations expire after 14 days. Acceptance locks organization, invitation and position records, checks the inviter's current administrator membership, and rejects changed/assigned/archived positions.
- Position acceptance writes its revision history. Invite creation, acceptance, revocation and administrator removal write organization audit records.
- The email handler uses the caller's JWT through PostgREST and a server-side `RESEND_API_KEY`; it needs no service-role key. It accepts only saved invitation identifiers and a matching token, and derives recipient/content from database records. Caller-supplied addresses, message content and redirect URLs are ignored.
- Email retries use Resend idempotency keys; database authorization permits the same request for at most 23 hours and limits new requests to once per minute per invitation. Creation is limited to 100 invitations per organization per hour. Provider acceptance is reported as submitted, not delivered.

Reference: [Resend idempotency keys](https://resend.com/changelog/idempotency-keys) documents a 24-hour provider window. Browser/Edge secrets and real recipient data are not in the tests.

## Validation and release hold

Run the dedicated database, browser, email and source tests under `tests/organization-invitations-*`. Their reports are in `validation/organization-invitations-*.json`. Database tests execute the migration in isolated PostgreSQL/PGlite and exercise the actual existing `private.ops_member` predicate. Browser tests load the complete HTML with synthetic accounts. Email tests inject fake HTTP transport and send no real messages. Existing login/onboarding and organization-structure browser checks also pass.

This branch is based on published 0.20.42 and is separate from the held tournament-alert and paid-launch drafts. **Not published; hosted migration and Edge deployment are not applied.** No hosted records or real invitations were created.

Before an approved release:

1. Reconcile any intervening main/held-draft changes, then rerun focused checks.
2. Apply `20260925184016_organization_leadership_invitations_02045.sql` to the approved target. It depends on the existing organization structure migration and live operations helpers.
3. Deploy `send-organization-invitation` with JWT verification enabled and existing Supabase URL/anon-key plus Resend secret configuration. Confirm the `messages@wrestlingmanager.app` sending identity.
4. Publish the matching app bundle, then run an explicitly authorized end-to-end invitation with a designated test recipient. Check Web and TestFlight/WKWebView link-return behavior, organization permissions, and email delivery. Local browser simulations do not substitute for device or delivered-email validation.

The draft adds access records when accepted; rollback must not silently delete accepted grants. Hide/roll back the frontend and disable creation/email functions first if needed, then review existing grants and audit records explicitly.
