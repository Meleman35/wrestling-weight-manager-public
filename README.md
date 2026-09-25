# The Wrestling Manager

Mobile team management backed by Supabase, with an iOS web-view app and native/offline scoring tools.

This development branch contains **0.20.44 in draft**, built on the unpublished 0.20.43 tournament-alert work. Published main was 0.20.42 when this draft was prepared. Purchases and tournament phone-alert delivery are not active.

- [Paid launch components and remaining work](docs/PAID-LAUNCH-READINESS.md)
- [0.20.44 changes, tests and deployment limits](docs/RELEASE-0.20.44.md)
- [0.20.43 tournament-alert dependency](docs/RELEASE-0.20.43.md)
- [0.20.42 published release](docs/RELEASE-0.20.42.md)

The app includes team/family access, safeguarded messaging, schedules and attendance, weight-room tools, agreements, goals, inventory/files, Match Book, organization tools and manual Tournament Day. A feature being present does not mean its paid-launch workflow is complete; the workboard records those boundaries.

Build the self-contained web page with:

```sh
python scripts/build-launch-044.py
```

Edit the relevant files in `src/` and rebuild. Existing native-facing assets must remain compatible. Database migrations are separate deployment steps; building the page does not apply them. Keep the pilot enabled until the paid-launch gates are complete.
