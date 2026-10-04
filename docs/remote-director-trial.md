Tournament directors: one calendar month free, up to four tournaments.

The trial starts when the organization activates its first tournament. It expires
at the same UTC time one calendar month later, clamped to the last day of the
following month where necessary. The fourth tournament remains usable through
the deadline; a fifth requires paid coverage. Repeated activation of the same
tournament does not consume another slot. Canceled tournaments do not free slots.

After the trial, the approved remote weigh-in director offer is $24.99/month or
$199/year. Show the price, expiry, tournament count and purchase terms before
signup. No automatic charge without an authorized subscription. Participating
clubs retain their independent team coverage requirements. Weight and photo
retention remains exactly 240 hours from capture.

Implementation status: tested server policy candidate; not deployed. Before
activation, wire canonical organization ownership and tournament/program mapping
to a private persistent trial record. Use one permanent record per organization,
including expired/revoked records, and serialize activation using an organization
row lock or equivalent transaction. Never initialize from a client-supplied null
state, delete the record when a director leaves, or rely on an in-memory store.
Atomic submission authorization must check current trial/event coverage alongside
paid coverage. Production database integration and checkout are still pending.
