# Creator offers and seven-day trial

Release 0.20.107 adds a private **Account & Team → Creator · Offers & Trial** console. The current RPC prepares discount drafts and records whether a seven-day Team Pro trial should be offered at launch. It does not activate billing, trials, discounts, or paid access.

Release 0.20.108 gives the authorized Creator a separate home immediately after sign-in, before invitation acceptance or membership onboarding. It has Offers & Trial, Sign-In & Security, My Account and Sign Out; no team, organization or athlete profile is required. Other accounts keep their existing onboarding. The route uses the server grant, never an email address or a client preference. No new backend privilege or paid entitlement is added.

## Access

`private.creator_accounts` accepts one reviewed, confirmed personal Auth UUID. No account is enrolled by the migration. The requested account must first be created and email-confirmed, then its exact UUID provisioned privately by the operator. Never publish the owner's email/UUID or enroll using a signup trigger, email comparison, JWT metadata, team role, or client code. Provisioning is not exposed through a public RPC.

Each call checks the private grant, current confirmed/nonbanned/nondeleted user, live Auth session, absence of a managed team login, and scoped deletion access. Creator access gives no extra access to athletes, weights, messages or health records. The client clears the console when the account changes, locks, backgrounds or loses connectivity. It rechecks authorization while open.

## Discount preparation

Create/edit/archive an uppercase alphanumeric code, one of the six accepted subscription plan variants, desired discount percentage, billing periods, maximum redemptions and expiration within a year. All offers remain `draft` or `archived`; they cannot be published or redeemed. Apple may require a different code format, redemption cap, eligibility choice or price point when an actual offer is created. Retries use the same request UUID; edits use a revision to avoid overwrites. A private change history records each successful change.

## Trial setup

The requested launch setting defaults on: Team Pro for **7 days**. It remains `awaiting_billing`. No countdown, charge, customer enrollment or access grant is started. A setting in this console must not be presented as a live introductory offer. Existing free/tester/video-pilot access is unchanged.

Before activation:

1. Implement verified subscription purchases, restore, server notifications and portable entitlement checks. Preserve existing tester grants and the accepted free safety/basic participation features.
2. Configure a one-week introductory offer on eligible Team Pro subscription products in App Store Connect. Use Apple's eligibility and product pricing, including clear renewal terms, before customer confirmation.
3. Create actual Apple subscription offer codes and verify their terms before distribution. Draft percentage/limits are preferences, not Apple-verified discounts.
4. Test purchase approval/pending/cancel, trial expiry, restore, refunds/revocation and offer redemption in the sandbox. No client-reported purchase or discount code alone may grant access.
5. Complete the paid feature boundary inventory, including Family Video coverage that follows the athlete. Do not advertise unfinished cloud/live video as available trial features.

Official references: [introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/), [subscription offer codes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes).

## Deletion and migrations

All four private tables have RLS, no client table grants and the scoped deletion freeze trigger. The migration registers a complete reviewed catalog and updates the exact athlete-merge fingerprint transactionally. Creator access, owned drafts and the owner's audit rows are explicitly deletable with that personal account. The aggregate trial preference has no personal identity fields and remains. There are no customer redemptions or financial records in these draft tables; adding them requires a separate retention/deletion review.

Run `python3 scripts/assemble-creator-offers.py --check`, `python3 scripts/patch-creator-offers.py --check`, `node tests/creator-offers-db.mjs`, `node tests/creator-offers-compatibility.mjs` and `node tests/creator-offers-browser.cjs` (with the pinned `.ci` dependencies).
