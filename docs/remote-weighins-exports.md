Director reports group athletes by club, then athlete name. Each accepted row
shows the scale weight and provides authenticated access to its verification
snapshot. USA Wrestling ID and AAU athlete membership number are separate text
fields. Entered numbers are unverified identifiers, not evidence of eligibility.

CSV downloads include all matching pages, club, name, both membership numbers,
status, weight, capture/receipt times, verification submission ID and expiry.
CSV cannot embed pictures; use Excel for visual review. The Excel workbook embeds
authenticated JPEG snapshots alongside the athlete, club and scale weight and
preserves membership numbers as text, including leading zeros. Missing athletes
remain listed without invented weights or photos. There are no public photo URLs.
Photo workbooks are bounded to 50 MB of JPEGs; larger reports should be exported
by club. A failed or inaccessible photo aborts the workbook rather than silently
dropping verification evidence. Generic CSV is not a promised USA Bracketing or
TrackWrestling import format; vendor field mapping still needs a sample template.

After-weigh-in warning: "Download a copy for your records. Online weights and
verification photos are deleted 10 days after capture. Your downloaded
spreadsheet remains available after the online copy expires."

Membership editor and lookup are candidate reusable components. Profile update
requires existing profile/guardian/coach authority and a transaction that rechecks
it. Lookup is limited to the authorized club roster and never treats a membership
number as login, permission or guaranteed unique identity. Multiple matches require
explicit athlete selection. The reporting database adapter accepts a trusted
canonical membership resolver and rejects foreign or duplicate mappings.

Not deployed: profile coordinator registration, persistent membership storage,
profile deletion-catalog integration, membership resolver wiring and production
remote reporting runtime. Existing app/profile schema must be checked before
adding storage; do not create competing athlete profiles or overwrite index.html
from the older local checkout. No external membership verification API is assumed.

Official sources checked October 4, 2026:
https://www.usawmembership.com/verify_membership
https://aausports.org/parents-page/
