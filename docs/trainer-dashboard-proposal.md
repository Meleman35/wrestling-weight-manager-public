# Trainer Dashboard — proposed workspace

Status: design only. This branch does not implement the Trainer Dashboard or change any trainer, guardian, coach, or organization permissions.

The trainer is assigned to the team's care staff, not automatically to its coaching or administrative staff. Keep one personal sign-in and the existing app; do not create a second app, require another personal account, or turn the trainer into a team administrator.

## Initial dashboard

For a trainer-only assignment, propose opening the selected team's Trainer Dashboard rather than coaching operations. Keep the active team prominent. A multi-team trainer can select only teams with an authorized assignment. Assignment to one team or employment within a school does not grant all-team or organization-wide clinical access. For people with multiple roles, provide an explicit workspace switch without merging permissions or losing their selected team.

Build the initial dashboard as a focused landing screen with links into the existing Athlete Health workflow:

- Overview: new concerns awaiting trainer review, recorded activity restrictions, reviews due, and missing current-school-year baselines. Compute counts only from records authorized for the active account and team. An empty case list or a completed baseline is not proof of clearance.
- Athletes: the health-authorized roster and athlete records; baseline verification, participation instructions, review dates, uploaded provider releases and decision history. Do not expose weight history, recruiting information or unrelated coaching statistics by virtue of this role.
- Care updates: the existing private trainer/family workflow and separately marked coach-shared participation updates. Do not invent new direct minor messaging or use a general adult reviewer as clinical authorization.
- Schedule: a proposed read-only view of authorized team practices and competitions for care planning. Schedule editing and attendance administration remain separate permissions.

Retain the current server acceptance step. Before the trainer accepts the assigned responsibility, show the explanation/acceptance screen rather than patient records or counts.

## Information boundaries

The trainer records care decisions only under the current accepted-trainer permissions. Coaches receive authorized participation instructions and shared updates, not the entire clinical record. Parents/guardians receive only records for their connected athlete under the existing relationship and consent rules. Organization leadership or Creator access must not automatically grant private clinical access.

Keep private care updates and photos separate from coach-shared instructions. The current health implementation permits some access to the submitting account; preserve those exact existing rules rather than silently changing them in a dashboard redesign. Athlete health-update and photo permissions remain separate guardian choices.

Sway completion is currently verified manually. This proposal does not run tests, fetch Sway scores or promise an automatic Sway connection. Recording a participation decision does not replace the required provider release process or independently determine medical clearance.

Health-specific push/email alerts are not implemented. Do not present a new dashboard badge as proof that an urgent alert was delivered. Urgent concerns continue to require direct contact.

## Technical and release boundary

Reuse the existing `athlete_health_request` server authorization and private attachment controls. A new layout must not broaden those permissions. Clear health content on account/team changes, lock, background and disconnection; no new offline medical-record cache is proposed. Refresh visible data on return and reject late responses for a previous account/team.

Keep current billing/tester access unchanged. This proposal does not introduce a paid gate on existing care or safety features.

Acceptance should cover trainer-only and multi-role navigation, invited-but-unaccepted and revoked trainers, assigned/unassigned team changes, linked-family visibility, private/shared updates, missing baseline versus actual clearance, late replies and offline clearing. Use synthetic records, never real athletes' health data, for automated verification.
