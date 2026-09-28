# v0.20.86 verification

Base: production v0.20.85, commit 695a9ccb5a139a84d7b2a489b88c2341fdba5f37.

Changes requested September 28, 2026:
- Roster sorting explicitly offers First name, Last name and numeric Weight class; remembers the choice per account/team/season. Missing/invalid classes sort last.
- Attendance summary and event marking show active wrestlers only. Standby/removed membership records and attendance history remain intact; reactivation restores their attendance view. Competition-ineligible active wrestlers remain on attendance lists.
- Close/X and Back handle the dynamically added Attendance screen. Closing invalidates in-flight attendance responses. Manage attendance dismisses the panel and backdrop before entering Schedule. Back from a roster entry restores the roster.
- Team Board uses the existing selected-tab color. Attendance now highlights while its dialog is open, and returning restores the selected Locker Room section.
- Coach eligibility editor separates competition and practice. Practice defaults to allowed. Coaches can set an inclusive date range or require manual clearance; dates use the displayed timezone. Restrictions automatically stop applying the following local day without an expiry job. Upcoming competition/practice presentation lists evaluate the event date. School/coach practice restrictions are optional. This remains a scoped coach roster/lineup tool, not an AD portal or external tournament eligibility authorization service.
- Existing manual restrictions are retained. Private storage, coach-only access, managed-login denial, revision conflict checks and audit logging are preserved. No student names, reasons, medical data or grades added to source or test fixtures.

Passed:
- All 57 inline JavaScript blocks parse.
- release-086 browser suite: first/last/weight ordering; active-only summary and event attendance; X and Back from Locker Room and roster; backdrop release; Schedule transition; late response isolation; dated saving, date boundaries in America/Denver, scheduled-event eligibility, practice override, manual clearance and editor close.
- 320/390/768 px eligibility form overflow checks; phone screenshot reviewed.
- release-085 browser regression: roster scrolling/anchored identity, collapsed inactive/competition sections, attendance arithmetic and Schedule recurrence/favorite-location behavior.
- release-080 browser regression: profile follows, layout controls, repeat creation/retry and past-event editing.
- Live transactional synthetic database tests: baseline eligibility/attendance permissions and history, stale revision conflicts, inclusive expiry, future restriction, date/timezone validation, practice override, inactive picker exclusion, restoration/history preservation and unauthorized access denial. Synthetic changes rolled back.

Browser: Chromium headless shell 134, phone viewport and Denver timezone. Real iPhone/TestFlight hardware interaction was not exercised. No native bridge, match scoring, guardian messaging or recording modules changed.

Security advisor comparison: no new notices after this migration. Database migration version matches the applied migration history: 20260928112326.
