# v0.20.87 schedule verification

Base: verified live v0.20.86, commit 8f158410ee74f9192be28e94296abd041bbb781a.

Adds original controls based on the user's two schedule example recordings:
- Duration: 1 hour, 90 minutes, 2 hours or custom end. Presets maintain duration as start changes and update existing practice weight timing. Custom end stays editable.
- Search saved team venues and recently loaded schedule locations, filling venue/address together. Other teams' venues are excluded. Manual venue entry and existing favorites remain available.
- Controls work in creation and editing, retaining separate arrival/weigh-in times and existing repeat editing safeguards.

No geographic address-autocomplete service is configured; these are saved/recent team venue suggestions, not live map results. Full offline mode is not included. The requested complete offline data/sync/outbox work is recorded in docs/offline-sync-plan.md, including the current source gaps and release gates.

Validation passed:
- 57 inline scripts parse and git diff has no whitespace errors.
- schedule-087 browser suite: presets, changed start, custom end, venue search/selection, cross-team isolation, editing and 320/390/768 px overflow checks.
- release-085 browser regression: roster, attendance arithmetic, favorites and guarded recurring-event editing.
- Phone screenshot reviewed.
- No database or native changes in this version; v0.20.86 database checks remain applicable. Real iPhone/iPad tests remain user-side.
