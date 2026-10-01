# Linked Creator server staging — October 1, 2026

At 15:38:43 UTC the shared-Creator backend is staged and verified; the actual personal-account link is still null and web 0.20.114 is not yet published. The original dedicated owner remains configured. This note records real provider results, not a browser fixture.

## Applied migration

The Supabase tool successfully applied `creator_linked_access_020114` and its returned migration history reports version `20261001153751`. The CLI-generated SQL was moved to that actual versioned filename without altering its content (Git blob `70ef8e07f9ec553c935201a598b5fe105b1e74fe`). Do not reapply it under its earlier preparation timestamp.

The structural schema fingerprint and registered deletion catalog both equal `73d4ab1a9cf488dc3a0112e1895813cab8698e46335e7f64a9a94d28f1597246`. The athlete-merge router contains that exact new fingerprint. Zero unfinished deletion jobs were returned.

Live PostgreSQL function-body MD5 values were compared with the exact tested SQL bodies:

- `private.creator_access`: `21e794f0b4061e2899f111294ceae7ea`.
- `private.creator_offers_request`: `282ac6507fec34231bf7e5815db93990`.
- `public.creator_offers_request`: `f903b5734918f30683633fdc4079119c`.

All three match. Empty fixed search paths are preserved. The public wrapper remains SECURITY INVOKER; anonymous function execution is denied. The private access helper is not callable by authenticated users. All four Creator tables retain RLS and deny direct anonymous/authenticated SELECT/INSERT/UPDATE/DELETE. An access call with no user identity returns creator=false and no home mode; no real session was impersonated or token read.

## Edge worker compatibility

The authorized Supabase deployment tool staged the existing five-file scoped-deletion bundle with the additional nullable edge `private.creator_accounts.linked_user_id`. The existing custom authentication and verify_jwt=false setting were retained. No deletion endpoint was invoked.

The first staging copy, version 6, had a transcription error in the handler's UUID expression and would reject valid request identifiers. It was caught before schema application or personal-link activation and corrected by redeploying the reviewed source. Version 7 was returned ACTIVE and retrieved for inspection; the 8-4-4-4-12 UUID expression is restored. Its provider bundle fingerprint is `79fe499f5236929b3cefe7e923e7eb9a403a8292ef5ae1d2af241f7c6eb8f5e7`. No deletion job was pending at the preflight or post-migration check; no claim is made about an independent live HTTP traffic trace during staging.

## Rollout boundary

Complete branch run 36883440745 and the current-head linked/database/deletion checks passed before staging. Some broader browser jobs were still downloading dependencies. Therefore the compatible backend was staged with linked_user_id=null; final current-head regressions remain a publication and real-access activation gate. This staging sequence supersedes the original checklist's suggested order, not its access or test requirements.

The pre-migration security-advisor findings remain separate review work: 110 private RLS/no-policy information notices, two existing anonymous SECURITY DEFINER warnings, 183 existing authenticated SECURITY DEFINER warnings, and disabled leaked-password protection. This release does not assert that those unrelated warnings are remediated or that the application has a compliance certification.

The personal and dedicated identities' team/organization membership fingerprints and existing offer/trial values were captured before any server write, without exposing record details. Compare those again after provisioning. Keep real identities out of deletion testing. Final PR comments must distinguish server staging, web publication, actual link provisioning and physical-phone acceptance.
