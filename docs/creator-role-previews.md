# Creator role previews — web 0.20.113

The Creator home and authorized Account & Team sheet offer **Explore Role Views · Demo**. This is a representative, interactive walkthrough, not impersonation, a complete live app instance, or an exhaustive permission test. No separate test account is created. This release is independent of held linked-Creator PR 47 and does not activate that account link.

## Included examples

Six fictional personas: Athlete, Coach (assistant-coach example), Athletic Trainer, Team Mom, Parent / Guardian, and Team Administrator. Each has Home, Profile, Schedule and Access preview pages. Profile pages include an illustrative shared-profile switch; it does not change real visibility.

The trainer example has acceptance, scoped sample athlete filters, and separate private-care versus coach-shared participation panels. Team Mom review is off by default and requires a clearly labeled fictional assigned-and-accepted reviewer scenario. Its sample inbox has no reply or mutation controls. The athlete example distinguishes ages 13–17 from under 13 and a fictional family-messaging permission state. Messaging permission never represents health-photo consent. Coach Practice Plans are labeled paid and awaiting billing; there is no paid-feature unlock or trial activation.

Sample messages, goals, RSVP and acceptance interactions stay in memory and are explicitly labeled simulations. Switching roles, resetting or closing discards demo state. No upload, camera, scale, invitation, provider-release, clinical decision, billing or deletion operation exists in the demo. Fake names contain Demo and the fake team is Summit Demo Wrestling. Enter fictional text only.

## Isolation and access

The outer controller uses only the existing `creator_offers_request` **access** action. It sends the reviewed client-protocol marker for future linked-client compatibility; the marker alone confers no access. The current dedicated Creator owner is supported without changing Supabase schema, grants or account permissions. It rechecks on entry and every 15 seconds while displayed, and destroys the frame on account/team changes, lock, background, offline, close or denied recheck. Shortcut visibility is only a UI hint; a fresh server check decides entry.

The demo is a static `srcdoc` document with `sandbox="allow-scripts"`, no same-origin, forms, downloads, popup or top-navigation permissions. Its CSP permits only the exact hashed demo script, inline styles and no connections, images, child frames, workers, objects, form actions or base URL changes. No session, JWT, account/team identifier, live record, provider client, app globals or secret is passed into it. It does not call native bridges. Its one outbound message can only ask its verified parent to close the same frame, with no user-content payload. Text entered in the sample composer is escaped.

This isolates a demonstration; it does not replace real server/role/device acceptance tests. The sample source is public, non-sensitive application code. Restricting the Creator entry does not turn fictional demo content into confidential data.

## Source mapping and limits

The representative content is based on current `src/trainer-dashboard.js`, `src/athlete-health.js`, `docs/athlete-health.md`, `docs/conversation-reviewer.md`, `docs/parent-approved-messaging.md`, `docs/practice-plans.md`, `docs/creator-offers.md`, and the existing profile/Clipboard/People & Roles screens in `index.html`. Real layouts can vary with memberships, age, guardian permissions, team customization and feature availability. Update the samples when these areas change; this is not automatic mirroring of every production component.

## Build and verify

`python3 scripts/patch-creator-role-preview.py` embeds the isolated document and controller, integrates sheet cleanup and pairs index/service-worker version 0.20.113. `--check` requires an exact reproducible result. The browser suite exercises the actual host controller and demo with a parent-only synthetic provider fixture. It checks all six role pages and key scenarios, HTML escaping, no real write calls, no credentials in srcdoc, sandbox/CSP separation, original account/team preservation, revocation, delayed responses and responsive widths. The workflow runs existing Creator, trainer and athlete-health browser suites too; all normal PR regressions remain required before publication.

No Swift or Xcode settings are changed. Physical Safari/WebView behavior is a separate acceptance check. Local Chromium could render the isolated demo, but full local app navigation was blocked by the environment's browser policy; hosted CI is the integration-test environment.
