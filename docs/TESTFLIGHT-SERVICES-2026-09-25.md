# Wrestling Manager — TestFlight services and acceptance gates

Prepared September 25, 2026. Working draft for Damon Mele / Mele Sports Technologies LLC. No new provider purchase, production activation, tester invitation, SMS, live broadcast or App Store submission was performed.

## Recommended services

| Purpose | Recommendation | Price basis checked September 25 |
| --- | --- | --- |
| Accounts, teams, consent, scores, private original videos and files | Keep the existing Supabase project. Use private buckets and short-lived authorized playback links. | Pro starts at $25/month; 100 GB file storage, then $0.0213/GB; 250 GB uncached egress then $0.09/GB and separate 250 GB cached egress then $0.03/GB. Confirm current plan and remaining allowances. |
| Live video and adaptive replay | Cloudflare Stream; RTMPS/SRT ingestion with authenticated, signed HLS playback. Keep original local recording independent of the network. | Storage capacity costs $5/month per 1,000 minutes, purchased in blocks; delivery $1 per 1,000 viewer-minutes. Ingest and encoding included. Downloads and buffering count toward delivery. |
| Text notifications | Finish the existing Twilio integration. Keep SMS category preferences, explicit opt-in, STOP/START, and signed inbound webhooks. | US outbound SMS starts at $0.0083/segment plus carrier charges, number rental and registration fees. Long-code business messaging needs A2P registration. |
| iPhone notification alerts | Existing Apple push integration, verified in a release/TestFlight build. | No new provider selected; needs operational APNs credentials and an actual TestFlight device registration/delivery test. |
| Email | Keep existing Resend/SMTP setup. | Existing configuration; no new email service or plan change proposed. |

Cloudflare recommendation is an engineering choice for simple live/VOD billing and signed playback, not a claim that an account is connected. Mux remains a credible alternative with signed playback and usage pricing; its live input charges and quality/resolution tiers require a different estimate. No streaming vendor has been purchased or configured for this project.

**Do not use Cloudflare's WebRTC beta/GA transition as the recording solution.** Current documentation says WebRTC broadcasts cannot be recorded by Stream. Its delivery billing begins October 15, 2026. The proposed first live release uses RTMPS/SRT with HLS; it will have a viewing delay. Do not promise zero-delay streaming.

### Small pilot cost example (assumptions, not a quote)

100 matches × 6 recorded minutes = 600 stored minutes. With three full-length views per match, delivery is 1,800 viewer-minutes. That is approximately **$6.80/month for Stream** ($5 storage block + $1.80 delivery), before extra replay/download/buffering usage and taxes. If originals are uploaded again as separate Stream assets in addition to live archives, both assets consume storage; avoid duplicate ingestion.

At the browser pilot target of 2.5 Mbps video + 96 Kbps audio, the same 100 original recordings use about **11.7 GB**, before container overhead. Native AVFoundation uses different actual bitrate behavior; measure physical-device files before setting capacity commitments. Supabase allowances are shared with the rest of the app. Keeping 600 new minutes every month accumulates storage; this is not a permanent $5 cap.

1,000 US outbound single-segment texts cost $8.30 before carrier fees. The currently listed long-code carrier charges add approximately $3.50–$5.00 for that example, plus sending-number rental, registration, replies and taxes. Long or Unicode messages can use multiple segments. No unlimited video or text promise and no paid family subscriptions during the pilot.

## Verified connected project state

- Supabase project: `vfocpoyexnjsjpxhhyqr`.
- Deployed: `dispatch-communication-notifications` v8, `dispatch-team-sms` v2, `inbound-team-sms` v2, `dispatch-scheduled-communications` v2, `sync-notification-badges` v1, `send-team-email` v2.
- Notification dispatcher supports Twilio, Resend and APNs; APNs selects sandbox for development devices and production for release devices. Native source similarly selects development under DEBUG, production otherwise.
- Registered push inventory: three enabled development devices, one disabled development device, **zero registered production devices** at inspection. This is an unverified TestFlight delivery gate, not proof that APNs secrets are missing.
- SMS campaign/recipient tables had no rows at inspection. No text delivery was attempted.
- Secret-name inventory could not be checked: local Supabase CLI is not logged in. Do not request private keys or auth tokens in chat. Account SID/sending-number status, registered messaging campaign, and APNs key configuration need dashboard verification.
- Existing Storage policies are bucket-scoped; the general managed-session policy is restrictive. New bucket access is not covered by a broad existing permissive policy.

## Draft implemented in PR #5

- Athlete profile: **Score & record match**, using server-owned athlete, event, opponent, mat and stable bout UUID. Existing Tournament Day data is coach-entered; official USA Bracketing import is still pending approved access.
- Coach-confirmed event scoring rules and filming permission. Exact event/athlete recorder assignments expire after 24 hours and do not grant other coach rights. Guardian controls determine private recording/sharing. A restrictive linked-parent decision wins.
- Separate scoped match records and optimistic scoring saves. Reopening the same bout reuses its recording match; another recorder cannot silently take over.
- Private upload rows and object policies. Originals and score timelines must both match their declared size/content type before becoming available. Browser and native draft resume with six-MiB TUS chunks. Interrupted uploads retain device files.
- A verified shared recording can be watched/downloaded by the competing athlete and linked parent. Device removal requires a fresh successful cloud playback check. No automatic file deletion.
- **Go live remains disabled**. The red blinking recording indicator explicitly says the video is being recorded on the device and is not live. Reduced-motion preferences disable blinking.

## Remaining implementation before real family rollout

1. Review and apply the held migrations in an isolated environment, run database advisors there, provision only named pilot testers, configure upload limits, and test real Supabase Storage. Current tests use synthetic objects/protocol fixtures; no actual cloud upload has occurred.
2. Xcode compile/type-check the new native upload file; test continuous movie capture, force-close recovery, interrupted upload, expired TUS URL, token renewal, phone storage pressure, and repeat family playback on another phone. Foreground upload only currently; do not claim it continues after iOS suspends/terminates the app. Uploads require current recording permission; a teammate returning after the 24-hour assignment expires needs a renewed assignment.
3. Add a storage deletion worker and a verified recovery/backup policy for media. Family Remove currently revokes access immediately but leaves objects pending physical purge. Database backup is not proof of a video-object backup. Do not promise recovery from a deleted cloud object yet.
4. Complete verified parental-consent prerequisites for existing under-13 testers before recording real children. The video permission switch is not a substitute for the existing required verification process. Plan adult/self authorization for adult athletes; current sharing gate requires a linked guardian and is intentionally limited.
5. Connect a Stream account with narrowly scoped server credentials. Implement one native camera pipeline feeding both the local file and broadcaster; the current movie recorder does **not** encode RTMPS/SRT. Do not open competing camera sessions or silently switch away from the local recording.
6. Add server-owned live sessions, one active broadcaster per bout, verified provider webhook/status handling, current-viewer permission checks and signed playback. Notify opted-in linked parents once per live session only after playable video is confirmed. Never put ingest credentials or signed playback tokens in an SMS, public page, log or notification payload.
7. Add **Starting live / Live / Reconnecting / Ended** states. Drop the live indicator and suppress stale alerts when provider health disappears. Local recording continues if service fails. Returning service must not start a broadcast without the recorder's explicit choice.
8. Complete live notification links, deduplication and expiry through existing push/SMS infrastructure. Ensure an ended match does not trigger a late "live" text. Test STOP/START, preference changes, blocked recipients, carrier delivery failures, retries and valid/invalid webhook signatures.

## TestFlight gate

Preserve **The Wrestling Manager**, bundle ID **com.damonmele.wrestlingmanager**, Damon Mele's signing team and installed app data. Last confirmed Apple build was 1.0 (1). Prior handoff lists **Mele Testing** (internal) and **Team Testing** (external, previously waiting for review); these group/review details have not been checked live in this turn. Do not replace a pending submission based on that historical status.

The current draft app still loads production GitHub Pages; building the ZIP alone does not expose the held web pilot. Keep GitHub Pages and the existing Supabase project; no hosting migration. Choose a reviewed, guarded web distribution and increment the native build number only when preparing an actual archive. No Xcode or Apple SDK is available in this workspace.

Run with the existing testers after Damon's own two-device verification:

| Area | Required result |
| --- | --- |
| Accounts and roles | Coach, manager, assigned teammate, athlete and linked parent see only authorized actions; account/team switches clear prior screens. |
| Core app | Invitations/reset email, schedules, announcements, unread badges across teams, roster, goals, Clipboard, forms and agreements still work. |
| Hardware | Scale, NFC/card scanner, kiosk lock/unlock and recording camera do not interfere. |
| Match recording | Start from profile, imported identity, score/undo/clock, stop, replay and export work on physical iPhone and iPad. |
| Weak service | Record without service after initial authorization; resume upload while foregrounded; no duplicate files; no early device deletion. |
| Family | Separate phone can view/download; unrelated users cannot; revoked consent blocks fresh playback links. Existing signed links expire within two minutes. |
| Live | Two different networks; provider confirms playable media; one parent alert; red live state accurate; reconnect/stop behave correctly. |
| Notifications | Release/TestFlight token registered as production; foreground, background and closed-app delivery; correct athlete/match opens from alert. |
| Texts | Verified sender, consent, STOP/START, category choice, retry/dedupe and carrier receipts verified with explicitly authorized test recipients. |
| Purchases | Remain off for this free pilot. StoreKit products, verification, restore, organization/team benefits and offer codes stay a separate release gate. |

Officials iPad-to-iPad communication is a separate track, previously agreed not to block first launch. Held PRs #2 (tournament alerts), #3 (paid foundation), #4 (organization invites) need their own review; do not merge wholesale into video work.

## Sources checked

- https://supabase.com/pricing
- https://supabase.com/docs/guides/storage/uploads/resumable-uploads
- https://developers.cloudflare.com/stream/pricing/
- https://developers.cloudflare.com/stream/stream-live/
- https://developers.cloudflare.com/stream/viewing-videos/securing-your-stream/
- https://developers.cloudflare.com/stream/webrtc-beta/
- https://www.mux.com/docs/pricing/overview
- https://www.twilio.com/en-us/sms/pricing/us

Prices are provider list prices at the time of research. Taxes, other existing workloads and plan-specific terms are excluded.
