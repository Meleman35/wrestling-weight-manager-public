# Zeffy fundraising referrals — web 0.20.122

Owner-approved referral URL: https://join.zeffy.com/ahiq6lm6xo6a

Locations:
- Public website: welcome.html#fundraising.
- Coaches Clipboard: Fundraising tile.
- Board Room: Fundraising overview tile and Programs & events → Fundraising.

Each destination explains eligible nonprofit fundraising, Zeffy-managed signup/payments/donor records, optional donor contributions, and the referral commission to Mele Sports Technologies LLC. The fixed link carries no account, athlete or team parameters; links suppress referrers and opener access. No tracking script, database migration, payment connection or automatic enrollment is added.

The native launch candidate includes handling for a user tap on this exact link from the trusted main app page, opening it in the system browser. Existing native builds may need the copyable-link fallback inside the fundraising card. This native change ships with the rebuilt app, separately from the web release.

Verification: source generation and web/version pairing pass locally. Public website (four widths), Clipboard navigation/customization, web-update lifecycle, and fundraising browser checks pass with Chromium 138. The fundraising checks exercise the website, Clipboard, both Board Room paths, 320/390/768 layouts, external navigation, copy fallback and role boundaries using synthetic accounts and an intercepted Zeffy destination. No real signup or donation is performed. CI results are recorded on release PR #63. The fundraising sheet participates in the normal close/back lifecycle.

Copy sources reviewed October 5, 2026:
- https://www.zeffy.com/home/affiliates
- https://www.zeffy.com/fundraise/high-schools
- https://market.partnerstack.com/page/zeffyinc
