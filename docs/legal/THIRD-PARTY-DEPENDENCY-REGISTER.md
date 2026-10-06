# Third-Party Dependency and Rights Register

Status: initial audit, 2026-09-28.

| Component / Service | Current use observed | Rights / license action |
|---|---|---|
| Supabase | Auth, database, storage/backend processing, Edge Functions | Keep service agreement/DPA records; browser publishable key is expected; service-role secret must remain server-side |
| Resend | Transactional/invitation email | Keep API key only in server environment; document processor/vendor role |
| GitHub Pages | Web hosting/deployment | Public delivery does not itself grant ownership of proprietary source; reduce unnecessary source exposure |
| jsDelivr | Client-library delivery | Record exact library/package/version/license |
| Apple | iOS/iPadOS/macOS distribution, APNs, Sign in with Apple if enabled | Follow Developer Program/App Review/privacy/account-deletion terms |
| Cloudflare Stream | Planned, not yet configured per project docs | Review Stream terms/DPA before production athlete video |
| Twilio | Planned SMS | Review messaging terms, consent/A2P, data processing before enabling |
| USA Bracketing / tournament providers | Planned integration | Obtain API/data-use permission; do not imply endorsement; use logos only with permission |
| NFHS / USA Wrestling rule materials | Rules inform app behavior | Implement facts/rules in original code/text; do not reproduce protected rulebook expression or logos without permission |
| System fonts / Apple platform assets | UI | Prefer platform-provided assets or properly licensed custom assets |

## Required register fields for every new dependency

1. Name and version.
2. Source URL/vendor.
3. License/terms.
4. Whether source code is distributed.
5. Whether it processes personal data.
6. Whether it receives children's data.
7. Whether it receives video, messages, health/medical/clearance, weight, or precise location data.
8. Data-retention/deletion terms.
9. Subprocessors.
10. Security/incident commitments.
11. Commercial-use restrictions.
12. Attribution/notice requirements.
13. Approval owner and date.

## License policy

Preferred software licenses: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, ISC, or commercial licenses compatible with proprietary distribution.

Escalate before adding: GPL, AGPL, LGPL where linking/distribution implications are unclear, SSPL, source-available/noncommercial licenses, Commons Clause, custom licenses, or assets marked "personal use only."

Do not assume a GitHub repository is reusable merely because it is public.
