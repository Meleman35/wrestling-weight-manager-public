# theteammanager.app connection — active HTTPS

Requested by Damon on September 26, 2026. The target is `theteammanager.app`. Public NS records confirm Squarespace DNS. The existing Google Workspace mail service must remain intact.

As of September 26, 2026, GitHub Pages is bound to theteammanager.app, the Squarespace records below are installed, and HTTPS returns 200. The former GitHub join and auth-confirm paths redirect to the corresponding custom-domain paths; a synthetic join query was preserved. Google Workspace mail records were retained.

## Required controls

- GitHub: `Meleman35/wrestling-weight-manager-public` → Settings → Pages → Custom domain.
- Squarespace Domains: `theteammanager.app` → DNS settings. Inspect current website records before replacement. Keep Google Workspace MX, verification, SPF, DKIM and DMARC records, and existing email sending/tracking records.
- Supabase: inspect Auth URL settings and add the final `https://theteammanager.app/auth-confirm.html` callback without removing the current GitHub callback during migration.

## Website DNS values

GitHub's documented apex records:

| Type | Host | Value |
| --- | --- | --- |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| CNAME | www | meleman35.github.io |

Avoid changing nameservers or root email records. Review existing A/AAAA records and forwarding rules so old website targets do not conflict. Verify the domain in GitHub when the owner controls are available, then set the custom domain before pointing DNS there, as GitHub documents. Use HTTPS once the certificate is issued; `.app` requires valid HTTPS.

## Application migration status

Release 0.20.54 updates `JOIN_PUBLIC_BASE_042`, team/athlete/family/organization invitation builders, organization invitation emails, and absolute preview-image URLs. QR codes and share buttons consume these same generated links. Existing invitation codes and backend permissions are unchanged. Local tests preserve query tokens and family fragments on both the old and new entry routes.

The account-confirmation callback remains the established GitHub URL until the exact new `https://theteammanager.app/auth-confirm.html` callback is confirmed in Supabase Auth's allowlist. Its old HTTP route currently redirects to the new corresponding page. No real confirmation email/acceptance was triggered for this migration; a complete confirmation flow still needs device verification. Keep the old callback allowed when adding the new one; do not add a wildcard.

Native revision 8 trusts only the old GitHub origin for several bridges. A separate private revision 9 source package adds the exact custom-domain app route and keeps the legacy route. It must be rebuilt/installed to repair PIN and Face ID; a web release alone cannot replace an installed native guard. Preserve recordings and keychain/app data; do not uninstall or clear storage. Browser storage remains origin-specific.

Verification: HTTPS root, old/new synthetic join URL and old auth-confirm route return 200; 14 local routing cases preserve query/fragment tokens; all invitation builders produce the canonical domain; seven isolated email-handler cases pass with fake transport and no real mail. Full account/invitation acceptance and native PIN/biometrics remain user-device checks.
