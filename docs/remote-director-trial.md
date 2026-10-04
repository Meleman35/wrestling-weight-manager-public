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

Implementation status: database-tested candidate; not deployed. A private organization
trial record and event slots now serialize activation under the canonical organization
row lock. Same-event retries across directors/programs consume one slot. The fifth
event, revoked trial and expired trial are denied. Trial coverage uses the shared SQL
predicate for reporting preflight, private evidence reservation/confirmation and atomic
submission acceptance; revocation also blocks direct SQL retries. The optional HTTP
activation route is only available with a trusted trial service configured.

Before deployment, populate server-owned canonical program/organization mappings,
wire live organization authorization (including the existing actor-deletion lock),
and integrate these tables into scoped deletion and its schema fingerprint. Team
billing still has independent coverage requirements; atomic team entitlement checks,
verified paid network billing and checkout remain pending. Never initialize trial state
from a client, delete it when a director leaves, or reset expired/revoked records.
