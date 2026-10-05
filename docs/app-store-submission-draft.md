# App Store submission draft

Prepared for the combined launch work on October 4; updated October 5, 2026. These are prepared fields, not an App Store Connect update or a submission. Publish only after the accepted build and deployed feature set match the description. Review information must describe the actual submitted build.

Owner-approved scope, October 4 at 8:14 PM Mountain: launch the core app first. Nationwide remote weigh-ins, director subscriptions/trials, remote evidence capture/reporting and tournament imports will ship in a later update. Ordinary team scale/NFC tools remain in the first release. Do not advertise remote weigh-ins as an available first-release benefit. Team Pro is the only first-release paid plan; Family Video and texting were deferred by the owner on October 4 at 9:08–9:10 PM Mountain, with an October 25 update goal. Do not advertise either as available now. Team Pro purchases and their actual benefits still require hosted and device acceptance.

## Prepared listing fields

| Field | Prepared value |
| --- | --- |
| Existing app name | The Wrestling Manager |
| Subtitle | Your team. Every season. |
| Suggested primary category | Sports |
| Suggested secondary category | Productivity |
| Version | 1.0 |
| Combined candidate build | 9; attach only after acceptance |
| Bundle ID | com.damonmele.wrestlingmanager |
| Apple ID | 6815511370 |
| Copyright | 2026 Mele Sports Technologies LLC |
| Support URL | https://theteammanager.app/support.html |
| Marketing URL | https://theteammanager.app/welcome.html |
| Privacy policy URL | https://theteammanager.app/privacy.html |
| Support contact | support@theteammanager.app |
| Keywords | coach,roster,schedule,athlete,guardian,club,practice,scorebook,season,mat |

## Promotional text

Keep your wrestling season organized with team schedules, athlete records, family permissions and communication tools built around the people in your corner.

## Description

The Wrestling Manager brings coaches, athletes and families into one team workspace.

Organize the season
Keep team schedules, announcements and rosters together so your team can follow what is happening and prepare for what comes next.

Support each athlete
Manage authorized athlete records and weight history with access tied to team and family roles.

Keep families involved
Linked guardian permissions support participation in profile sharing and covered communications. Assigned adult review and notification preferences help adults follow the conversations they are responsible for.

Work at the mat
Use the available scorebook and Offline Mat Mode tools on supported devices. Check whether work is saved locally or waiting to sync, and reconnect to complete synchronization.

Connect compatible equipment
Supported native tools work with compatible American Scale equipment and NFC readers. Hardware availability, device permissions and setup affect which tools you can use.

Team Pro coaching tools
An optional monthly or annual Team Pro subscription covers the team selected at purchase. It includes Practice Plans and Wrestler Statistics for authorized users. These tools require an internet connection. Prices appear in the app before purchase; subscriptions renew automatically unless cancelled in Apple subscription settings. Restore keeps the original team binding.

Built by Mele Sports Technologies LLC for the everyday work of wrestling teams.

An account and the appropriate team invitation or assigned role are required for team features. Available tools depend on your role, team configuration and installed build. Weight readings do not replace official weigh-in certification. Family and review tools support responsible communication practices; they do not replace adult supervision or establish SafeSport certification.

Support: https://theteammanager.app/support.html
Privacy: https://theteammanager.app/privacy.html
Terms (Apple standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

The subscription paragraph and terms link are conditional on accepted benefits, enabled production purchases and the agreement selected in App Store Connect. The current service does not yet meet that launch state. See `core-release-readiness-2026-10-05.md` for the benefit, privacy and moderation evidence gaps.

## Review information to complete after acceptance

Use dedicated fictional review accounts and test athletes. Enter reviewer credentials directly in App Store Connect's review fields; do not save passwords in this repository.

- Explain how the reviewer signs in, selects the prepared team and reaches its roster, schedule, family permissions and scorebook.
- Give the exact accepted-build route to account deletion. Keep the durable coach, parent, athlete, trainer, reviewer and organization review accounts intact. Provide a separately prepared disposable fixture for deletion; the designated purchase account is not automatically the deletion fixture either. General account deletion must be available and verified before submission; the earlier pilot gate is not sufficient.
- Explain which functions require compatible scale/NFC hardware and provide a review attachment showing the accepted physical workflow. Do not present a simulation as a real reading or bypass authorization for review.
- If billing is included, list only the two Team Pro product identifiers in `billing-candidate/READ_ME_FIRST.txt`, their actual benefits, the in-app Plans and Restore routes, and the test team's immutable purchase binding. Attach the subscriptions and required review screenshots with the submitted version. Do not promise unlimited storage, SMS, streaming or undecided athlete discounts.
- Remote weigh-ins are deferred from this submission. They have no first-release reviewer setup, director purchase or trial. Preserve their later-update acceptance checklist in `docs/remote-weighins-launch-status.md`.
- Include a staffed review contact phone number in App Store Connect. The support email above is known; a review phone number has not been verified here.

## Fields that still need current account/build evidence

- Content-rights declaration: the account holder must confirm rights to all submitted content and screenshots. A partnership statement is not proof of rights to third-party logos.
- Age-rating questionnaire: use the complete functionality, including user-generated messages/photos, guardian controls and private health-related records. Do not guess an age rating from the sport or select the Kids category merely because minors use the app.
- App Privacy answers: reconcile the deployed data inventory and providers, including account/contact identifiers, athlete records, photos/videos, messages, health/fitness information and purchases. The native required-reason manifest is not a replacement for these answers.
- Digital Services Act trader verification and all remaining agreement status: verify current App Store Connect state. Earlier screenshots established active paid agreement/tax/banking setup; do not repeat those tasks without a new issue.
- Screenshot sizes, supported devices and final native build: create screenshots from the accepted build with fictional data. Missing earlier uploads are not submission screenshots.
- Production and sandbox notification URLs: the owner already saved both Version 2 URLs on October 4, and actual signed Sandbox TEST delivery passed on October 5. Confirm the current saved values without recreating setup. Production TEST requests returned HTTP 401 twice; production authorization/delivery remains unverified. See `apple-production-authorization-2026-10-05.md`.

## References checked

- Apple listing field limits and review information: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
- Apple app information: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/
- Apple submission requirements: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/
- Apple privacy fields: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/

The subtitle is 24 characters, promotional text is below 170 characters, description is below 4,000 characters, and the ASCII keyword list is below 100 bytes. Verify the accepted feature claims before copying these fields.
