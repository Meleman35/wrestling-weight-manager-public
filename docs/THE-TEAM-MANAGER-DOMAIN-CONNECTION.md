# theteammanager.app connection — DNS applied; HTTPS pending

Requested by Damon on September 26, 2026. Target: `theteammanager.app`. GitHub repository: `Meleman35/wrestling-weight-manager-public`.

## Current checkpoint

- GitHub ownership verified: Damon supplied a screenshot showing `theteammanager.app` Verified on September 26.
- Ownership TXT retained: `_github-pages-challenge-meleman35` = `af16506f899b0f9edef7f37a3e75c3` (4-hour TTL). Exact value returned by public DNS.
- Damon saved the repository custom domain. Commit `3784716` (Create CNAME) on main contains `theteammanager.app`; local checkout fast-forwarded to it.
- Squarespace browser account is `damonmele@theteammanager.app`; reauthentication succeeded before DNS writes.
- Automatic approval review initially rejected deleting Squarespace Defaults due to possible disruption to an existing site/payment links. Read-only Website and Pay Links checks showed no connected website and payment setup not configured. The same replacement was then accepted after these checks.
- Removed the unused Squarespace Defaults preset (four old A records, www parking CNAME, and parking HTTPS record). Domain Connect preset, Google Workspace and email-sender records were preserved.
- Added all four GitHub A records listed below and www CNAME, each with 30-minute TTL. Google public DNS returned all four expected A records and the correct www CNAME, no conflicting AAAA/HTTPS records, and unchanged MX `1 smtp.google.com.`.
- Public DNS recheck also found no CAA restriction, and the Pages build for commit 3784716 completed successfully.
- HTTPS is not ready. A browser request to `https://theteammanager.app/join.html` returned 502 with `Certificate verify failed: hostname mismatch`. No TLS bypass attempted.
- Published app remains 0.20.53, with existing GitHub URLs. Organization email endpoint remains version 3 and JWT-verified. A tested 0.20.54 change is prepared on a separate branch for branded invitation URLs and preview assets; it is not deployed while HTTPS is failing. Do not claim newly generated invitations use the branded hostname yet.
- GitHub cloud sign-in stalled at Apple's security-key verification. Damon operates GitHub on his own device. Next: refresh the repository Pages settings and run its DNS Check again if offered; wait for/verify the certificate, then enable Enforce HTTPS when available.
- Once HTTPS is valid, update branded invitation destinations/preview images, verify legacy redirects preserve query/fragment tokens, and handle Supabase Auth callback configuration before changing the email-confirmation URL. Keep the existing callback allowlisted during migration.

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

## Prepared application changes and release gate

The prepared change updates `JOIN_PUBLIC_BASE_042`, organization invitation/email entry URLs, and absolute preview-image URLs to the new origin. It deliberately retains the existing allowlisted account-confirmation callback and decouples organization sharing from that callback. Add the new Auth callback in Supabase before changing it in a future release. The published invitation path will be `https://theteammanager.app/join.html?invite=…`. Keep old links working through the host's redirect and verify that both query tokens and family-invitation fragments survive.

Check the native app's actual configured web origin before any native release. Browser storage is origin-specific: preserve current on-device recordings and settings, do not uninstall or clear storage, and plan recovery of old-origin local recordings before moving affected recording sessions.

Verify DNS, a valid HTTPS response, app/asset loading, a synthetic invitation redirect, email-confirmation return and existing invitation acceptance. Do not send a real invitation without a designated recipient and authorization.
