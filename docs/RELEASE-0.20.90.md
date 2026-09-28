# v0.20.90 — saved-team refresh and conversation drafts

Normal Messages previously kept unsent text only in the current textarea, and a late send response could clear text from a different conversation. Offline workspace downloads also required manual updates to receive changes from other coaches.

This release adds encrypted device drafts for personal profiles, scoped by account, team and conversation. Drafts restore when an authorized, editable conversation opens. Sending or scheduling removes only the acknowledged draft revision. Text typed during the request stays in place. Concurrent windows retain conflicting copies with recovery controls. Storage failures retain visible text and stop conversation/team switching from discarding it. Sign-out waits for writes; saved normal-chat drafts remain scoped to their profile for the next sign-in.

The normal composer still sends through the existing server methods. Drafts are not an automatic outbox. Only text queued in Offline workspace uses the existing idempotent offline send path. No real messages were sent during validation. Attachments are not saved as offline drafts; an in-flight attachment now retains its original conversation and stops before posting if the account changes.

Unlocked browser Offline workspaces now push saved operations and then refresh complete saved team packs on reconnect. Foreground/periodic refresh is limited to once per five minutes per pack; manual sync can request an immediate update. Downloads use the existing permission-checked endpoints, validate profile/team/season, and replace a pack only after all required responses succeed. Other saved teams are included. Concurrent queue additions survive; a download that overlaps another window's confirmed edit cannot replace that newer local state. Posting-permission changes close an affected composer while preserving its unsent draft.

No database schema or server permission changes are included. Existing guardian/safety/message rules remain server authoritative. The service-worker cache version is bumped, without forcing active windows or recordings to reload.

## Validation

- `tests/chat-drafts-090-browser.cjs`: draft restart, conversation switching, late acknowledgement/new typing, failed/offline sends, scheduling, storage failure, account isolation, concurrent-window recovery, permission changes, phone/tablet layout, attachment destination and account races.
- `tests/offline-refresh-090-browser.cjs`: reconnect push-before-pull, throttling, composer/event preservation, posting permissions, interrupted snapshots, overlapping local saves and acknowledgements, multiple teams, revoked access and stale-account responses.
- Existing offline browser restart/outbox/conflict tests and native/browser capability/layout tests remain passing. The real vendored Supabase bundle is smoke-tested separately from mocked server behavior.
- Test result files live in `validation/`. Browser tests use fictional accounts and mocked requests, including actual IndexedDB, service workers and browser offline mode. They do not substitute for iPhone/iPad device testing.

## Native status

The available Xcode source is native revision 11. `ContentView.swift` starts a `WKWebView` with the HTTPS website and a reload-ignoring-cache policy. Navigation failures report loading failure; they do not load a bundled team workspace. Existing local Mat Mode/video facilities are separate.

The archive was inspected, not modified or rebuilt. Native offline team startup remains pending. Rebuilding revision 11 alone does not add this capability. Native work must preserve existing app identity, Keychain/PIN/Face ID, video recordings, scale, NFC and nearby Mat Mode behavior. See `docs/offline-sync-plan.md` for the remaining full-app work.
