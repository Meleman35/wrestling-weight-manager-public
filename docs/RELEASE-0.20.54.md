# Wrestling Manager 0.20.54 — prepared; HTTPS gate pending

Newly copied invitation links and organization invitation emails use `https://theteammanager.app/join.html`, and previews load the existing WM logo from that domain. Team, staff, athlete, guardian, family and organization links use the same public base, including links generated in a native WebView. Ordinary membership and position permissions are unchanged.

Organization sharing now uses the invitation base directly rather than deriving it from the Auth callback. The existing email-confirmation callback stays on its previously allowlisted GitHub URL while Supabase Auth settings are migrated. No Supabase Auth settings, email sender address, membership data or native files are changed.

Validation passed: 14 exact query/fragment forwarding cases across branded and legacy roots, metadata/size checks, blocked-navigation fallback, web/legacy/native link helpers, 10 position invitation interactions including the exact branded URL, 7 fake email transport scenarios, 9 source checks, and parsing of all 46 inline scripts. No real invitation or message was sent.

Deployment gate: valid HTTPS responses on the branded root, join page, callback and logo; verify the host's legacy redirects preserve synthetic query/fragment values before merging. The domain is verified, the CNAME commit is published, and public DNS points to GitHub; the latest real request still fails certificate verification. The organization email endpoint remains v3 until this gate passes. Deploy the updated endpoint with JWT verification enabled after the web release.

Physical iPhone Messages preview and recipient acceptance remain to be checked. Preserve all on-device recordings and app data. This change does not constitute public/paid launch approval.
