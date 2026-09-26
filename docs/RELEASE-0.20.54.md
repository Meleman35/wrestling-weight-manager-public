# 0.20.54 — custom-domain invitation links

After the move to https://theteammanager.app/, the invitation sheet still displayed the original GitHub Pages address. Generated team, athlete, family and organization links now use the verified HTTPS custom domain, including QR codes and share/copy actions. Static preview images and the authenticated organization-invitation email function use the same domain. Invitation tokens and permissions are unchanged.

The established email-confirmation callback remains in place pending verification of the new exact Supabase Auth redirect allowlist entry. It is separate from invite-link generation; the old auth-confirm URL currently redirects to the corresponding new page.

Validation: 14 old/new query and fragment routing cases, canonical helper links across five page origins, static preview checks, seven isolated email-handler authorization/delivery cases, and parsing all 48 inline scripts. Email tests use fake transport; no real invitation is sent. The deployed email function is version 4 with JWT verification retained and both source files compared to the tested files. Live HTTPS and legacy path redirection were checked before release. The existing organization browser suite's URL assertion is updated but the full suite was not rerun for this URL-only change.

PIN and Face ID require the separate private native revision 9 source package and an iPhone rebuild; no native source is included in this repository. That source package has not been compiled with Xcode or device-tested here.
