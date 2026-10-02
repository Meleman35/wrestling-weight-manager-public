# Team Trainer and Athlete Health

Team administrators can invite an adult as **Team Trainer**, or assign that role to an existing adult under **People & Roles**. The trainer signs in with their personal account, opens **Toolbox → Athlete Health**, and accepts the responsibility. This role does not grant coaching, weight-history, or administrator permissions. Other existing operational permissions remain separate.

## School-year baselines

The roster shows missing or trainer-verified baselines for the current school year. Sway is the default provider. Testing takes place in Sway; the trainer verifies completion there and records the completion date here. This release does not retrieve Sway scores, run a concussion test, or automatically integrate with Sway. An approved integration and the school's Sway access would be needed for automatic syncing.

Baselines are required by default. A team administrator can set the school-year start and the requirement. The school year advances annually; an old baseline does not satisfy the new year's requirement. A verified baseline follows the same athlete within the same organization and school-year dates. It does not expose records across organizations.

The required/missing flag is a coach-facing readiness checklist. It does not disable attendance, scales, scheduling, or every sport's lineup. Staff must check readiness before participation. Baseline completion is not injury clearance.

## Concerns, updates, and clearance

Coaches, accepted trainers, connected guardians, and permitted athletes can submit an injury, skin, concussion, or other concern. New concerns await trainer review. Only the accepted trainer records participation decisions: **Not cleared**, **Modified activity**, **No contact**, or **Cleared**. Decisions include instructions, a review date, and an audit history. A future return date remains pending.

To record clearance, the trainer names the authorizing provider, enters a return date, and confirms the school's required release process is complete. Concussion clearance also requires an uploaded written provider release. The app records an authorized decision; it does not verify clinical credentials, diagnose photos, prescribe care, or independently determine medical clearance.

The trainer can send a private update to the connected family or share a participation update with coaches and family. Coaches see baseline completion, participation status/instructions, shared updates and their own submissions. Private care notes and uploaded files are available to accepted team trainers, authorized connected family, and the submitting account. The general conversation-reviewer role grants no clinical access. Use **Refresh Updates** to fetch new replies. New authorized care activity creates generic in-app notifications that open the exact concern/update. Trainers choose Send to Parents / Guardians or Send to Parents & Coaches; earlier private notes stay private. The sender is excluded and current access is rechecked before showing a notice or its destination. This release has no health-specific lock-screen alert push, email or SMS delivery; urgent issues require direct contact. Native badge synchronization is not alert delivery.

## Family permission and files

Connected guardians can submit concerns directly. Athletes aged 13–17 need an active connected guardian's health-update permission; private photo/document sharing is a separate choice. The guardian can withdraw either permission in the athlete's health record. Younger or age-unverified athletes use the parent/trainer submission path. Existing general profile or messaging permission links do not authorize this medical workflow.

Uploads are JPEG photos or PDF releases, up to 8 MB each. The app re-encodes images as resized JPEGs without their original location metadata. The private bucket uses current-session and relationship checks; no public or signed media URLs are issued. Updates and health attachments are not saved to the app's offline cache or browser storage. Downloaded copies remain the recipient's responsibility. Closing, hiding, changing accounts/teams, or going offline clears the health view and temporary media URLs. Access is rechecked while the view is open.

## Preservation and release checks

Shared clinical records and health permissions require an identity review before an ordinary athlete merge. Deletion requests involving protected medical records require support review; the automated planner cannot silently cascade these records or another person's profile. The complete structural deletion catalog is refreshed atomically and schema-drift checks remain enabled for deletion and merge.

Regression tests use synthetic accounts and health records only. Database tests cover trainer acceptance, least-privilege roles, linked-family and team scope, permission withdrawal, current sessions, storage RLS, provider-release confirmation, stale decisions, protected merges and deletion compatibility. Browser tests cover role acceptance, baseline verification, shared/private updates, photo preparation, parent choices, responsive widths, account switching and offline clearing. No real Sway integration or physical iPhone clinical workflow is claimed as tested.
