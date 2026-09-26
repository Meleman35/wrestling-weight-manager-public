# theteammanager.app connection — prepared, not activated

Requested by Damon on September 26, 2026. The target is `theteammanager.app`. Public NS records confirm Squarespace DNS. The existing Google Workspace mail service must remain intact.

No custom-domain binding or DNS edits have been applied. Do not publish a CNAME file or switch generated invitation URLs until the coordinated connection can be completed and HTTPS verified; an early GitHub custom-domain redirect could interrupt current testers.

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

## Application changes after verification

Update `JOIN_PUBLIC_BASE_042`, invitation/email entry URLs, the account-confirmation URL, and absolute preview-image URLs to the new origin. The published invitation path will be `https://theteammanager.app/join.html?invite=…`. Keep old links working through the host's redirect and verify that both query tokens and family-invitation fragments survive.

Check the native app's actual configured web origin before any native release. Browser storage is origin-specific: preserve current on-device recordings and settings, do not uninstall or clear storage, and plan recovery of old-origin local recordings before moving affected recording sessions.

Verify DNS, a valid HTTPS response, app/asset loading, a synthetic invitation redirect, email-confirmation return and existing invitation acceptance. Do not send a real invitation without a designated recipient and authorization.
