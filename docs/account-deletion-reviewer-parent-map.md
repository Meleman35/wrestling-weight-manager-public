# Account deletion: reviewer and parent-browser additions

September 29, 2026. These are implementation requirements, not an executable deletion plan or approved retention policy. The deletion feature remains unmounted and disabled. PR #27 is now merged into main at `0343b4f107b4cba61537a0f394cb9482e3e220fe`; this draft preserves its reviewer feature and the previously released parent-browser changes.

## Reviewer records

| Record | Account relationship | Fulfillment requirement |
| --- | --- | --- |
| `private.conversation_reviewers` | `user_id` is the reviewer; `approved_by` is the assigning administrator. | Revoke the departing account's review access before erasure. Find both relationships. `approved_by` is non-null and has a restrictive Auth reference: deleting only the account's own reviewer row will miss assignments they approved for other people. Remove or replace those approvals through a verified administrator; do not silently transfer approval or acceptance. Preserve unrelated assignments. |
| `private.conversation_review_events` | `actor_id` and `subject_id` refer to accounts and become null on Auth deletion. | Resolve any justified retention and de-identification policy before completion. Null foreign keys alone do not prove anonymity because team, thread, time and other records can permit attribution. Do not delete other people's conversations as a shortcut. |
| `private.conversation_review_settings` | Project-wide switch, no account ownership. | Preserve the setting; deleting one account must not disable review for every team. |
| `conversation-review-media` | Issues media links only after authenticated, current assignment and attachment checks. | Revocation prevents new reviewer links. Existing links last up to 60 seconds; already viewed/downloaded data cannot be recalled. Original conversation attachments remain in their own media ownership/erasure scope. |

Required isolated scenarios: departing reviewer, departing approving administrator, same person in both roles, two teams with unrelated reviewers, revocation before Auth removal, repeated/interrupted cleanup, and media access after revocation. The implementation must not wait indefinitely for another administrator before fulfilling the departing person's request.

## Parent-browser records

| Record | Relationship requiring review | Fulfillment requirement |
| --- | --- | --- |
| `private.parent_browser_verifications` | Guardian, athlete, profile, team, and `verified_by` coach account; contains email and birth date. | Distinguish deletion of a verifying coach from deletion of a guardian's account or a verified child-data request. `verified_by` cascades on Auth deletion. Ensure dependent capability checks fail closed, without erasing a shared athlete or another guardian. |
| `private.parent_browser_permissions` | Guardian relationship; consent/withdrawal status and receipt. | Resolve the correct guardian relationship and retention basis. Do not treat a parent's account deletion as authority to erase every linked child. Permission rows can outlive the coach's verification row. |
| `private.parent_browser_links` | Guardian/invitation; includes email, token hash and a JSON receipt. | Revoke eligible capabilities first, then erase or minimize only the resolved scope. Review receipt JSON as well as relational columns. A parent who never joined may have these records without any Auth account. |
| `private.parent_browser_recovery_attempts` | Email hash, no Auth foreign key. | Include a justified bounded expiry and verified identity mapping; account-root traversal will not discover the ownership relationship. Never publish actual email hashes in review artifacts. |
| `private.parent_browser_events` | Guardian foreign key becomes null; JSON details may remain. | Review JSON and retention explicitly. A nulled guardian ID does not establish completed erasure. |
| `private.parent_browser_settings` | Project-wide switch. | Preserve for unrelated families. |

Required isolated scenarios: non-account guardian withdrawal, linked-parent precedence, two guardians for one athlete, coach deletion invalidating their verification, expired/revoked email links, and removal of personal values from receipts/logs where required. Scope must be resolved from verified account/guardian authority, never only an email string supplied by a caller.

## Integration status

The dependency conflict in `.ci/package.json` and its lockfile is resolved while preserving the pinned PGlite, Playwright and jsdom versions needed by both workstreams. The deletion intake, UI and read-only planner tests pass locally after integration. This does not implement fulfillment, revoke any session, erase any user or activate deletion.

The earlier 217-table/480-foreign-key inventory predates reviewer installation. Refresh the catalogue and fingerprint before building an executable adapter; do not reuse those counts as the current production schema. Ownership, physical Storage/provider cleanup, stale-token protection, device caches, retained records, completion notice and deadline handling remain launch gates.
