# IP / Ownership / Privacy Audit Summary

Date: 2026-09-28  
Branch purpose: documentation only. **Do not merge legal text into production/public UX until placeholders and implementation-dependent promises are resolved.**

## Ownership

- Current OpenAI terms assign OpenAI's rights in output to the user as between the user and OpenAI, subject to law.
- AI-assisted material still requires human authorship for U.S. copyright protection; preserve evidence of human specifications, selection, arrangement, edits, testing, and integration.
- No third-party license granting ownership of the overall app was identified in this pass.
- Formal founder-to-LLC assignment should be executed once the exact LLC legal name is verified.

## Repository

- Public repository exposes significant source code, migrations, authorization logic, tests, product plans, and release documentation.
- Public visibility does not by itself make proprietary code open source, but it reduces trade-secret protection for disclosed details.
- No root open-source LICENSE was observed.
- No live Resend, Supabase service-role, Twilio, Cloudflare, private-key, or common live-payment-secret pattern was found in the searches performed. Publishable Supabase browser credentials are intentionally client-visible; security must rely on authorization/RLS.
- Recommendation: keep the deployed web artifacts public only where required, while moving proprietary source/development materials to a private repository or private build pipeline in a planned migration. Do not change hosting architecture until deployment dependencies are mapped.

## Branding

- THE TEAM MANAGER should be treated as the main source brand and marked ™ pending clearance/filing.
- WRESTLING MANAGER is crowded/descriptive and should not be treated as the sole protectable house mark.
- A formal federal/state/common-law trademark clearance and counsel review should precede filing.

## Privacy / youth

Release blockers before broad public athlete launch:
1. functional account-deletion initiation;
2. final retention/deletion rules;
3. under-13 enrollment/parental-consent path;
4. processor/vendor review for every service receiving youth data;
5. final privacy policy matching implemented features;
6. App Store privacy disclosures matching actual SDK/data behavior.

## Third-party IP

- Continue avoiding unlicensed superhero/pro-team/governing-body logos and artwork.
- Use original shield/icon assets.
- Rules/facts may be implemented in original code/text; avoid copying expressive rulebook text or proprietary diagrams.
- Maintain a dependency/license register.

## Safe next engineering work

1. Inventory exactly which public files are required by GitHub Pages.
2. Design private-source -> public-build deployment without changing production output.
3. Add secret scanning/dependency license checks.
4. Implement deletion backend and UI behind tests.
5. Implement versioned guardian consent records.
6. Finalize privacy/terms only after behavior matches the drafts.
