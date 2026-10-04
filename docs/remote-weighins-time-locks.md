Activated reporting windows have immutable start/end times, IANA timezone, event
date and upload grace. A server-set locked_at survives disabling the window and
evidence cleanup. Changing dates requires a new window. Active can be disabled
to revoke access; disabling never unlocks the schedule.

Start is inclusive; end is exclusive. QR/NFC scan, scale receipt and camera
snapshot must occur within the authorized window. Live server preflight rejects
new captures before opening or at/after the deadline. Frozen queued captures are
checked against their original weight/photo timestamps; they do not become new
captures when uploaded. Atomic SQL acceptance enforces both the capture interval
and configured upload grace, plus session, assignment, consent, retention and
program coverage. Evidence must bind exactly to the same timestamped payload.

Accepted records, weights, capture times and server receipt times cannot be
updated. Retries use identical payload/photo bytes and the same receipt. Server
receipt time is separate from capture time and does not extend retention. The
director screen displays the allotted period with timezone and the original
capture/receipt times. No date or time editor is provided to operators.

Candidate implementation, not deployed. Immutable local timestamps alone do not
prove device-clock accuracy. The mandatory production capture-provenance adapter
must validate clock/camera/BLE binding; the current integration fixtures are not
an implementation of that verifier. Do not claim fraud-proof or official certified
weigh-ins. Current tests verify database/window immutability, exact boundaries,
unchanged offline payloads and server receipt/expiry rules.
