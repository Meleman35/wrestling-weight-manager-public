# Quiet conversation reviewers — v0.20.93

Damon authorized a reviewing adult under Team Mom or another approved adult helper role, with read access to messages/images without routine notifications. This adds the capability; it does not silently assign Hadley or change anyone's guardian relationship.

## Set up Team Mom

1. A team administrator opens **Edit Team Leaders** for the intended team. Add or confirm the adult's personal **Team Mom** role. They must have accepted their staff invitation and confirmed their own email.
2. Select **Conversation reviewers · Team Mom / adult helpers**. Find the correct adult, verify their age/own account and authority under team policies, then choose **Assign conversation reviewer**.
3. The adult opens **Messages → Conversation review · approved adults** in their own account and accepts the responsibility statement.
4. The inbox now shows that team's coach/team-leader conversations with minors. Open a conversation to read its history and shared images/videos. Safety flags appear in the inbox and conversation; routine reviewer push/email/text alerts are not generated.
5. The administrator can **Remove review access**; the adult can **Stop my reviewer access**. Changing the assigned staff role requires a fresh assignment/acceptance. Removing team membership or the approving administrator's authority stops future reads.

Review access includes existing history in covered conversations and is disclosed to their members by reviewer name and team role. It excludes adult-only chats, athlete-to-athlete private chats, other teams, archived conversations and safety-test simulations. It does not include private cross-team profile chats, medical records, weights or parent controls. The existing connected-guardian and communication-permission gates still apply. A second adult is not a substitute for required legal or organizational permissions.

Reviewer access is separate from normal participation. If the adult is already a regular participant or linked parent, those existing permissions/notifications continue independently. Use the existing notification controls for those roles. Reviewer-only access cannot post, react, upload or delete messages or media. Reviewers should follow their team's reporting procedures for concerns; this is not an emergency monitoring service.

## Implementation and validation

Separate private assignment/settings/audit tables; public invoker wrapper over an authenticated private RPC. No extra conversation membership or guardian records. Server checks team scope, confirmed personal account, adult staff role, known-minor/unknown-age athlete conflicts, current approving administrator and reviewer acceptance on each read.

A separate inbox RPC returns read-only message pages and live attachment metadata. Existing raw-message RLS, send logic, notification routing and parent permission rules remain unchanged. Reviewer-only accounts have no additional direct Storage permission. The conversation-review-media Edge Function verifies the caller and requests the exact live attachment through the authenticated RPC, then signs it with a fixed server-controlled 60-second expiry. The caller cannot choose a path or expiry. Existing Storage read, upload and delete policies remain unchanged, including for former uploaders.

The browser never saves reviewer history offline. Account/team/lock changes discard the view. Every 15 seconds while open, it rechecks reviewer and thread access; loss of access or network clears it. Media links last 60 seconds; already viewed data and issued links cannot be recalled immediately. Reads are logged at most once per conversation/reviewer in five minutes.

Database tests run the actual migration, existing message-send and upload checks, Storage RLS and deletion policy with synthetic accounts. Handler tests cover invalid identity, attachment selection, forged paths/expiry, revocation and fixed server expiry. Browser checks cover verification/acceptance, quiet read-only view, escaping, media expiry request, revocation, stale-account responses, reviewer disclosure and offline failure. Existing messaging, chat drafts, login, parent controls, parent browser approval and offline suites run before merge. No test sends a real message or assigns a real person.

Migration starts with `private.conversation_review_settings.enabled=false`; deploy the authenticated conversation-review-media Edge Function and publish the tested UI before enabling it. There are no assignments until a team administrator chooses them. Disabling the setting stops reviewer-only reads without altering normal conversation membership, notifications or guardian access. No Xcode rebuild is required for this web/backend change.

New private records and their Auth/team/message references must be included in final account-deletion fulfillment. This does not complete the separate default-off deletion draft or resolve child-enrollment launch gates.
