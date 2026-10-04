Director reports group athletes by club, then athlete name. Each accepted row
shows the scale weight and provides authenticated access to its verification
snapshot. USA Wrestling ID and AAU athlete membership number are separate text
fields. Entered numbers are unverified identifiers, not evidence of eligibility.

CSV downloads include all matching pages, club, full/first/last name, both membership numbers,
status, weight, capture/receipt times, verification submission ID and expiry.
CSV cannot embed pictures; use Excel for visual review. The Excel workbook embeds
authenticated JPEG snapshots alongside the athlete, club and scale weight and
preserves membership numbers as text, including leading zeros. Missing athletes
remain listed without invented weights or photos. There are no public photo URLs.
Photo workbooks are bounded to 50 MB of JPEGs; larger reports should be exported
by club. A failed or inaccessible photo aborts the workbook rather than silently
dropping verification evidence. Generic CSV is not a promised USA Bracketing or
TrackWrestling import format; vendor field mapping still needs a sample template.
Both are intended targets; see remote-tournament-export-compatibility.md for
verified roster-import guidance and the remaining existing-entry weight-update test.

After-weigh-in warning: "Download a copy for your records. Online weights and
verification photos are deleted 10 days after capture. Your downloaded
spreadsheet remains available after the online copy expires."

Membership editor and lookup are candidate reusable components. Profile update
requires existing profile/guardian/coach authority and a transaction that rechecks
it. Lookup is limited to the authorized club roster and never treats a membership
number as login, permission or guaranteed unique identity. Multiple matches require
explicit athlete selection. The reporting database adapter accepts a trusted
canonical membership resolver and rejects foreign or duplicate mappings.

Private membership storage and transaction adapters are now drafted and database-tested.
Numbers attach to the canonical athlete profile and follow its linked athlete records.
Client database roles have no direct access. Profile deletion cascades to the numbers;
production scoped deletion catalog still requires explicit integration.

Not deployed: profile coordinator registration, membership storage migration,
profile deletion-catalog integration, membership resolver wiring and production
remote reporting runtime. Existing app/profile schema must be checked before
adding storage; do not create competing athlete profiles or overwrite index.html
from the older local checkout. No external membership verification API is assumed.

Official sources checked October 4, 2026:
https://www.usawmembership.com/verify_membership
https://aausports.org/parents-page/

October 4 hardening:
- Every report page carries a SHA-256 revision of all matching projected rows
  and counts. Pagination/export stops on any revision change, even if row count
  remains the same. Export checks again before download, including after photos.
- Excel now includes canonical first/last name, server receipt time and the
  verification submission ID. Portrait and landscape JPEGs preserve proportions.
- createCanonicalRemoteReportReader supplies scoped canonical names, memberships,
  accepted weights, counts, at most 500 rows and the revision in one SQL statement.
  Compose it as getReportPage in createRemoteReportingService. It requires the
  canonical public roster and the private membership draft, and remains behind
  live service authorization. The older injected-array adapter is a test/fallback
  path; do not use that path for nationwide production reporting.
- The SQL reader handles 32 fictional clubs / 3,200 athletes in isolated PGlite
  checks, filters active canonical rosters/club enrollment/consent, and excludes
  revoked or expired photo evidence. This is not a hosted production load test.
- Report connections bind to the Auth session ID as well as the account, cancel
  pending requests on close, time out stalled reads and bound JSON/photo sizes.
