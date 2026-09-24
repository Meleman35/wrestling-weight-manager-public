# Wrestling Manager 0.20.37 — clear account creation

An invited athlete could select Team Login and find no way to create her personal account. Team Login previously hid Create Account, even though an invitation does not create an account or supply personal sign-in credentials.

## Changes

- Places “New to Wrestling Manager?” and “Create an Account” above both login modes.
- Explains that a team link/code does not create an account and directs existing users to sign in below.
- Explains that Team Login requires administrator-issued credentials.
- Opening signup from Team Login returns to Personal Login so email confirmation and subsequent sign-in use the correct form. Shared-device credentials are not copied into signup.
- Uses the existing invitation persistence, role selection, email confirmation, and team joining flows. Account creation does not grant team membership or bypass coach approval.

The remembered invitation comes from the original invitation link. A manually entered shared-device login code is not converted into a team-registration invitation. If someone only received a registration code, they still need to enter that code during team setup or reopen their invitation link.

## Validation

- Baseline: main commit 129d8dfc8e2f3c9787c7114af6f3519d760c4882, web version 0.20.36. Fresh repository and live-page checks matched the previously tested baseline.
- 33 inline JavaScript syntax checks passed.
- All script code outside chooseSignInMode and openSignUp is byte-identical to the baseline, including account creation, invitation handling, authorization and native bridges.
- Eight complete-page Chromium scenarios passed with a mocked backend and external network blocked: both login modes; signup role choices; 320px/390px/1024px layouts; shared credential separation; signup and email-confirmation retention; reload and successful sign-in resuming the correct team join form; private staff invitations; and the native join URL handler.
- No real accounts, invitations, messages, database changes, or access grants were made during these checks.
- Screenshot supplied by Damon shows TestFlight 1.0 (1) Testing and a phone displaying web version 0.20.36. No new Apple binary was built or uploaded for this web-only change. Actual device validation of 0.20.37 remains pending.

Candidate index.html SHA-256: 80f8d87a542f2b3cd6eb7208adb6c980355595e991bfd556468981e2c02f5e37.

Commands: `python3 tests/check-login-source.py` and `CHROMIUM_EXECUTABLE_PATH=/path/to/chromium node tests/login-onboarding-browser.cjs` (Playwright required).
