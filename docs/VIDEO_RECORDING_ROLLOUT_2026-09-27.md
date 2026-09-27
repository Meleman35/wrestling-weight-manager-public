# Athlete recording, storage and live rollout

Requested by Damon Mele, September 27, 2026. Web change 0.20.65.

## Recorder access

Athletes retain their athlete role and use their own personal account on any authorized device. An approved coach can select **Match Book → Team recording access → All active athletes and student managers** for an active season. Individual event/athlete assignments remain available when the team setting is off.

The backend checks active membership, active roster linkage for athletes, the selected active season, filming permission for the event, permission from linked parents, and existing tournament visibility. Blanket recorder access does not grant coach administration, medical access, or other families' video libraries. A recorder can save only the bout claimed by that account; separate bouts have independent IDs and score revisions. Removing roster membership or disabling the season blocks fresh authorizations. Existing offline camera leases last at most two hours; cloud operations always recheck current permission. The switch does not instantly erase local footage or revoke an already-issued offline lease.

The current production pilot remains test-only, with cloud uploads disabled. The new team control enables synthetic camera tests for eligible students in this pilot; real team bouts still require the existing pilot gate to be advanced after consent and device testing. There is no automatic team opt-in, role conversion, subscription activation, or media deletion in this change.

## Storage decision

Recommended first architecture: Supabase for identities, team/athlete/family authorization, match results, score timelines, media metadata, retention jobs and notification state. Cloudflare Stream for a single private cloud video copy, live delivery and replay. Keep originals on the recording device until the authorized owner chooses cleanup after verified cloud recovery/export. Avoid storing the same full video in both Supabase Storage and Stream by default.

Existing Supabase upload code is a disabled pilot, not a completed Stream integration. A provider adapter must preserve recorder authorization, resumable uploads and score timeline linkage. Access must use short-lived signed playback/download tokens after a fresh backend entitlement and parent check. The recorder's account/device is separate from the paying family's entitlement. Paying-family access follows the athlete across teams and can work through any approved recorder even if that team lacks a subscription.

As checked September 27, 2026, Stream storage costs $5/month per 1,000 minutes of capacity, and delivery costs $1 per 1,000 viewer-minutes; downloads and buffering can add delivery usage. For 100 six-minute matches retained, watched fully three times each: 600 stored minutes fit one $5 block; 1,800 viewer-minutes cost $1.80, or approximately $6.80 in Stream charges before downloads, extra viewing, taxes and app/backend costs. This is an estimate, not an activated purchase.

Sources:
- https://developers.cloudflare.com/stream/pricing/
- https://developers.cloudflare.com/stream/uploading-videos/direct-creator-uploads/
- https://developers.cloudflare.com/stream/viewing-videos/securing-your-stream/
- https://developers.cloudflare.com/stream/stream-live/start-stream-live/
- https://blog.cloudflare.com/introducing-scheduled-deletion-for-cloudflare-stream/

## Agreed retention

Cloud media expires 30 days from recording, not upload. Late uploads do not restart the clock. Keep a server-owned capture session and expiry; offline recordings need a validated capture-time reconciliation flow rather than accepting an arbitrary client timestamp. Reject already-expired cloud uploads while keeping the device copy.

Show the expiry date/countdown and free app/push reminders at 7, 3 and 1 day remaining. Provide Download & keep for authorized athletes and families. Distinguish starting a download from actually saving a copy; support opening the saved copy and display its destination where the platform allows it.

At expiry, deny new access and purge the video plus associated cloud derivatives, thumbnails and media timelines. Keep results, scores and statistics. Device originals and downloaded family copies are not part of this deletion. Reconcile scheduled provider deletion with an application purge queue, retries and verified completion. Provider live-input deletion defaults can calculate from processing completion; explicitly set the application capture-time deadline. Do not claim physical deletion completed from a metadata flag alone. Explain bounded provider cache/backup lag when the provider and purge behavior have been verified.

## Live readiness

A real stream requires native encoding alongside the local recorder, a server-owned live session per match, protected provider ingest credentials, signed playback and health-confirmed Starting / Live / Reconnecting / Ended states. Notify opted-in linked viewers only after playback is actually available. Local recording continues through network failure. This is native work that needs an Xcode/TestFlight build and a physical two-device test; a web button cannot provide it alone.

Next concrete work: connect the video provider using secure account tooling, implement and test private upload/playback/download and capture-time expiry, then add the native broadcaster and parent live notifications. Provider billing and media deletion are not activated by this recorder permission release.

## 0.20.66 — Shared Team Recorder login

Coach/admin path: **Account & Team → Team Logins → Create Team Recorder Login**.
Choose a display name, username and password (existing minimum 12 characters). Sign in on each device through **Team Login**, using the team's separate team-login code, username and password. A designated Test Athlete is not required. Existing Team Device / Test Athlete logins keep their behavior.

This reuses the deployed `team-logins` Edge Function and its registered, independently scoped auth sessions. The account remains a limited `team_device` with the new `record_matches` permission. The permission sanitizer forces every other operational/admin permission off. Coaches can disable it or reset its password through the existing editor; account revisions and session registration revoke old sessions. No production login/password was created during deployment.

Recorder sessions open a small dedicated screen: score/record, device video library, refresh and sign out. They do not load general team tables. The REST pre-request hook allows only login verification and the two video RPCs; video actions have an additional allowlist. Existing restrictive table/storage policies deny other resources. Camera authorization verifies the account, exact team, membership, registered auth session and revision. Guardian consent, opponent visibility, event filming permission and pilot controls still apply.

Each physical device/browser storage keeps its own draft and original recordings. Concurrent sessions can save different bouts. Server revisions reject stale saves of the same bout; this is not collaborative editing of one bout. A shared login identifies the team recorder account, not which student held the device. Personal athlete accounts remain available through 0.20.65's season setting.

Production remains test-only, with cloud and live off. This release does not activate uploads, a storage provider or automatic 30-day deletion. Shared recorder direct Storage access remains blocked pending the cloud rollout's scoped media policy. Future cloud retention remains the policy described above; no local originals are deleted by this release.

Validation: PGlite tests execute the actual migration and existing registered-session checks on synthetic data, including two concurrent sessions, distinct bouts, stale saves, denied cross-team/admin access, guardian withdrawal and revoked/disabled sessions. JSDOM runs the actual login editor and startup/controller functions, including creation, disable and password-reset payloads, with all inline JavaScript parsed. No physical iPhone sign-in, camera capture or visual claim; the native shell is not rebuilt.

## 0.20.67 — Recorder setup and invitation usability

Damon reported that Create appeared unresponsive, a new login could not accept a photo, and Schedule filter labels were clipped. Investigation found no new or pending recorder account in production; a valid database reservation was verified inside a rolled-back transaction. The existing form reported validation errors only above its long editor, while photo input was disabled until the account existed.

The form now scrolls to a newly opened editor and shows validation/server feedback next to Create. It preserves entered values on failure, shows progress, and keeps a successfully created account open for editing. Coaches may select and crop a photo before creation; the cropped image stays in memory until creation succeeds, then uploads through the existing authorized team-photo flow. Cropping preserves the password fields. A failed photo upload leaves the account intact and displays a retry message.

Schedule filters no longer shrink below their labels and wrap onto additional rows at phone widths. Family circle now offers **Invite family** for server-authorized manageable profiles, then the existing relationship/sharing settings and invitation creation. Copy and Share actions expose the invitation link. Recipients sign in, request access, and must be approved by the profile owner/linked parent. Existing seven-day invitation expiry and privacy rules are unchanged.

Validation: actual app scripts in headless Chromium with synthetic authentication/API/storage fixtures covered missing-password feedback, photo selection/crop before creation, credential preservation, one account creation plus one photo upload, server-error retry, 320/390-pixel filter layouts, and family profile selection/invitation/copy. JSDOM startup/login regressions and all inline script syntax also passed. Screenshots in validation use synthetic data. No production accounts, family invitations, or stored photos were created by testing. No backend deployment or native rebuild is needed for this release; physical iPhone confirmation remains pending.
