# Privacy, COPPA, and App Store Audit

Date: 2026-09-28  
Scope: Wrestling Manager / The Team Manager beta architecture and current privacy page.

## Current strengths observed

- Current privacy page identifies major data categories and service providers.
- Parent/guardian relationships and controls exist in the product design.
- Athlete photo approval, protected communications, role-based access, private tables/RPC authorization, and youth-safety controls have been built/tested in current releases.
- Server secrets are referenced through environment variables rather than embedded live values in the checked public source.
- Privacy page openly states that final retention/deletion and younger-athlete enrollment arrangements are unfinished rather than claiming nonexistent controls.

## Release-blocking gaps for a broad athlete launch

### 1. In-app account deletion

Apple requires apps supporting account creation to let users initiate account deletion in the app (or directly link to the exact deletion webpage where allowed). The current privacy page states that a complete in-app deletion workflow is not available. Treat this as a release blocker before ordinary public App Store launch with account creation.

Required behavior:
- easy-to-find delete-account action;
- identity confirmation appropriate to risk;
- deletion of the account and associated personal data not legally required to be retained;
- handling for shared team/guardian records;
- deletion/anonymization of user-generated posts, photos, video, messages, and profile content where applicable;
- Sign in with Apple token revocation if used;
- clear subscription-cancellation explanation if subscriptions exist;
- auditable completion state.

### 2. Children's privacy / COPPA

If the service is directed to children under 13 or has actual knowledge it is collecting personal information from a child under 13, COPPA obligations may apply. The product collects categories that can be personal information, including names, photos/video, contact/guardian data, persistent identifiers, messages, and potentially other athlete records.

Before enabling independent under-13 accounts, implement a documented COPPA path:
- age-screening strategy that does not encourage false ages;
- direct notice to parents;
- verifiable parental consent where required;
- parental access/review/deletion;
- ability to stop further collection/use;
- data minimization;
- confidentiality/security controls;
- retention only as long as necessary;
- processor/vendor diligence;
- no unnecessary conditioning of participation on excess personal data.

Safer near-term product posture: under-13 athlete profiles should be created/managed through verified parent/guardian or authorized organization workflows rather than independent child self-enrollment until the consent system is finalized.

### 3. Sensitive youth records

Treat weight history, medical/clearance documents, private messages, travel details, and video as higher-risk youth data even where a specific medical-privacy statute does not apply. Limit purpose, access, retention, export, notification lock-screen content, and vendor exposure.

### 4. Privacy-policy completeness

Before general availability, the policy should state:
- legal/business identity and contact information;
- categories collected;
- sources;
- purposes;
- categories of recipients/processors;
- retention periods or criteria;
- account deletion;
- child/guardian rights and consent model;
- security summary without exposing controls;
- international/state privacy rights if applicable;
- video/live-stream handling;
- SMS handling when enabled;
- payment/subscription data handling;
- change-notice/effective date.

### 5. App Store privacy disclosures

App Store Connect privacy answers must match the actual code/vendors. Re-review whenever video, analytics, advertising, Twilio, Cloudflare, recruiting, location, or new SDKs are enabled.

## Recommended data classification

**Restricted:** auth credentials/tokens; minor medical/clearance documents; private messages; precise travel/location; private athlete video; private weight records; government IDs if ever collected.

**Confidential:** birthdays, guardian links/contact info, school/grade, team roles, attendance, internal board records, budgets, signed forms.

**User-shared:** approved profile fields, team posts, public/recruiting fields subject to guardian controls.

**Public:** marketing/support content intentionally published by Company.

## Engineering control checklist

- Row-level/role authorization for every private resource.
- No authorization based solely on hidden UI.
- Signed/short-lived private media URLs.
- Server-side authorization before email/SMS or privileged actions.
- Audit records for guardian approval, consent, deletion, privileged access, and role changes.
- Device/session revocation.
- Secret scanning and dependency review in CI.
- Separate test/synthetic data from production.
- Avoid real athlete data in GitHub, issue trackers, prompts, test fixtures, screenshots, or crash logs.
- Rate limiting and abuse/reporting paths for messaging/following.
- Block/report and guardian controls for profile messaging.
