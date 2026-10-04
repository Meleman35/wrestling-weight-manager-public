Remote weigh-in export direction: support Trackwrestling and USA Bracketing.
Directors retain their chosen tournament system. Keep one complete Excel review
workbook with photos, club grouping, identifiers and original timestamps, and
provide destination-specific data exports only after the relevant import path
has been verified in a test event.

Verified public documentation, checked October 4, 2026:

Trackwrestling open/predefined tournament spreadsheet imports use delimited rows,
without column headers, and administrator-selected field mappings. Team names,
divisions and weight classes must match the destination event. Dual-team imports
use their own fixed layout. These are roster-import instructions; they do not
establish that the same route updates the measured weights of existing entries.
Trackwrestling documents a separate Weigh-Ins workflow for existing wrestlers.

https://support.trackwrestling.com/en/article/8a50d3
https://support.trackwrestling.com/en/article/1d4dff
https://support.trackwrestling.com/en/article/51ef45
https://www.trackwrestling.com/instructions/OT_PdWom_Checklist.html

Baumspage publishes a working USA Bracketing roster import example and a CSV with
headers Weight, Last Name, First Name, Team, Grade, Record. This is evidence for
that particular roster transfer, not a verified bulk actual-weight update API or
template. Never map measured pounds to an ambiguous Weight column automatically.
Do not implement the guide's deletion/reimport process as a remote weigh-in update.

https://www.baumspage.com/cwp/mgr/indexUSA.htm
https://www.baumspage.com/cwp/mgr/usawre.csv
https://www.baumspage.com/cwp/mgr/USA%20Wrestler%20Import%20from%20Baumspage.pdf

Implementation completed: canonical first/last name fields now reach reports and
the generic CSV. Compound names are preserved from profile fields; full names are
never split heuristically. Missing name parts remain blank. Measured scale weight
is explicitly labeled and remains distinct from any registered weight class.

Remaining interoperability test:
- Confirm existing-entry weight update versus new-athlete registration for each
  destination and event type. Obtain that screen's field layout/template.
- Match the destination event and participant IDs; USAW/AAU membership IDs and
  names are lookup aids, not substitutes for a destination participant ID.
- Validate duplicates and unmatched entries before export; never create an
  athlete merely because an update could not be matched.
- Test a small set of fictional entries in a test event, including a compound
  surname, leading-zero identifier, missing capture and decimal scale weight.
- Keep photos and locked timestamps in the review workbook unless the destination
  explicitly supports importing them. Do not imply a partner API or automatic sync.

No vendor-ready preset or live import has been claimed or enabled by this change.
