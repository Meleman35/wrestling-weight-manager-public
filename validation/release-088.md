# v0.20.88 — browser offline coach pilot

## Shipped scope

Profile → Offline workspace uses the existing profile PIN. Personal coaches can download the roster, current-season team events, attendance and permitted conversation directory with the latest 80 messages each. There they can mark active-wrestler attendance, edit an individual event, write persistent message drafts and queue text messages. Device writes are encrypted and atomic. Server replay checks current access, deduplicates operation IDs, retains guardian/safety processing, and requires conflict review for changed attendance/events.

This is a browser pilot, not full-app offline certification. Original app screens remain online. Attachments, other modules, native Keychain/background integration, automatic incoming delta sync and physical iPhone/iPad testing remain outstanding. Download / update fetches a new full core pack. Foreground outgoing sync resumes while the same account and workspace are unlocked. Reopening after force quit requires unlock.

## Verification

- `tests/offline-088-browser.cjs`: actual service-worker offline navigation; encrypted IndexedDB; PIN and account boundaries; failed download preserves prior pack; offline event/attendance/message writes; draft and queue survival across reload and full browser process restart; acknowledgement loss/retry; conflict review; concurrent local saves; full-storage rejection; static-only cache; 320/390/768px layout.
- `tests/offline-088-rollback.sql`: synthetic coach/family/stranger data in a transaction rolled back after all assertions. Scoped reads, active-only replay, stale event/attendance conflicts, same-ID message/attendance/event retries, unchanged receipt count, wrong payload ID reuse denied, revoked coach replay denied, private ledger inaccessible.
- Existing release-086 browser regression: all ten checks pass, including roster sorting, attendance X/Back, active-only membership, dated eligibility and independent practice restrictions.
- Existing schedule-087 browser regression: all five checks pass, including duration/time handling and saved/recent venue selection.
- Real vendored Supabase bundle starts the unauthenticated app without JavaScript errors.
- Inline script syntax, source syntax and git whitespace checks pass.
- UI screenshot inspected at phone size; no overflow in tested viewport widths.

## Security review

No new warning/error in Supabase security advisors. One new informational finding is intentional: the private offline operation ledger has RLS enabled with no client policies and all direct client privileges revoked; only the authenticated, explicitly scoped function can access it. See [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). Existing project findings are unchanged.

Browser encryption uses nonextractable AES-GCM keys stored by origin, plus the existing profile PIN UI gate. It does not claim native Keychain protection or resistance to compromised same-origin JavaScript. Seven-day offline access is a labeled pilot limit, not a school-configurable policy yet. Browser storage eviction/clearing can remove local data; persistence is requested, and the UI never promises storage that the OS cannot guarantee.

## Recovery and future releases

The complete v0.20.87 index backup was saved before changes, and git retains the complete prior release. Both database migrations are additive; existing online RPCs were not replaced. If the UI is rolled back, retain the offline store and server ledger so pending work can be recovered.

**Every subsequent index/vendor change must bump the cache name in `sw.js`.** Worker activation waits for older windows to close and never forces a running app/recorder to reload. Do not delete queued data during future schema migrations.
