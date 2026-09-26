# 0.20.46 — private recording test

Damon selected Bridger Valley Bruins for the initial device test. This release exposes a guarded Test scorebook to explicitly granted personal accounts. The initial grant is for Damon only and expires after seven days. No bulk tester invites or notifications are sent.

Open Locker Room → Match Book · score & record → Test scorebook. Confirm filming permission, open the camera, record while scoring, then stop/save and replay. Test names are synthetic. Use consenting adult or non-person test footage. Initial authorization requires service; the app must stay open to record. Test videos stay on that device and can be exported.

The database defaults to test-only mode: native/browser grants contain no athlete IDs, real-bout recording and guardian/assignment setup are denied, and cloud/live/billing stay off. Other teams have no grant. Athletes/student managers retain the implemented scoped paths for later named tester grants, without coach/referee rights.

The two video migrations install private tables and functions with access off by default. The verified team's account grant is a separate controlled data operation. To stop access, set `private.video_pilot_control.enabled=false` or revoke the exact grant. An offline recording may continue until the existing bounded lease expires (maximum two hours).

Validation: 11 isolated database groups, 11 simulated native-bridge screen groups, 11 existing actual browser capture/recovery groups, 7 upload protocol groups, 8 navigation groups, source preservation and 44 inline-script syntax checks. These do not establish native camera reliability. Revision-4 Swift still needs physical-device recording/replay acceptance; the user is testing that now. No native archive or TestFlight upload is part of this web release.

The full private sharing, media purge/recovery, streaming encoder, live alerts and release notification gates remain documented in TESTFLIGHT-SERVICES-2026-09-25.md. Purchases and other held PRs remain separate.
