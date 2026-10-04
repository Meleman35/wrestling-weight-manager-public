# Apple verification hosting decision

Status: Damon approved the proposed $7/month Render service plus applicable usage/taxes on October 4, 2026. Code and deployment configuration are prepared. Render account connection and private-key configuration are still needed; no service or charge has been created. This is a backend component of the existing app. Families and directors do not install another app.

## Why this is needed

The read-only `wm-runtime-readiness` function on the existing Supabase project returned HTTP 200 with `appleCertificateVerification: false` and `billingEnabled: false`. The same check on Deno 2.1.4 throws `Not implemented: crypto.X509Certificate.prototype.verify`. Apple's official Node library uses that method to validate certificate signatures. Removing our root check would not fix Apple's verifier.

The prepared solution uses Node for Apple's verification library. Supabase retains authentication, purchase ownership, database decisions and notifications. The new service receives signed Apple evidence or an existing subscription binding, checks it through Apple's library and API, and returns verified facts. It has no database credentials and receives no athlete photographs or weigh-in records. It does not grant access or charge customers itself.

## Approved service scope

One Render Node web service, `wm-apple-verifier`, on its 0.5 CPU / 512 MB plan (formerly Starter). Render lists this compute size at **$7/month**; applicable usage and taxes are additional. Confirm the displayed total before creation. No new database, disk, workspace upgrade, preview service or autoscaling is requested. The prepared Blueprint is `billing-candidate/render-verifier.yaml`. Automatic deploys are disabled.

This size is a starting deployment, not proof of nationwide capacity. Two verification requests can execute concurrently, with a 25-second worker deadline; excess work receives a retryable response. Existing delivery/reconciliation must retain pending work when verification is unavailable. Check actual Apple sandbox latency and queue drainage before opening paid access.

## Setup

1. Connect the existing GitHub repository to the owner's Render account. Select the prepared Blueprint file and the integration branch. Review the proposed resource and price before creating it.
2. In Render's private environment settings, supply the existing `.p8` contents as `APPLE_IAP_PRIVATE_KEY`, preserving actual line breaks. Public key ID: `79R244P822`. Do not recreate Apple products, tax, banking or agreements for this step. Never paste the private key into chat, the repository, an app package or a screenshot.
3. Generate a fresh 32-byte random value encoded as 64 hexadecimal characters on the owner's computer, and save it privately as `APPLE_VERIFIER_SHARED_SECRET`. For example, run `openssl rand -hex 32` locally and copy the result directly into the secret field. Do not send that output to chat. Render's generated Base64 secrets do not match this service's hexadecimal format.
4. Deploy the reviewed commit. The service binds Render's supplied `PORT`. `/health` confirms local startup configuration only; it does not establish valid Apple credentials, paid access or end-to-end purchase readiness.
5. In Supabase's server secret store, configure `APPLE_VERIFIER_URL` as the exact HTTPS service URL ending in `/apple`, and the same `APPLE_VERIFIER_SHARED_SECRET`. The `.p8` stays in the Node service. Never expose either server secret through browser/native configuration.
6. Wire the approved Supabase billing entry point with `remoteApple: {url, secret}` and the selected Apple environment. Keep the existing deployment, deletion/retention and restricted-database-identity checks. This document does not provide an entry point that bypasses them.
7. Check unauthorized requests are rejected, Apple's signed sandbox TEST notification is verified, and actual sandbox purchase/restore updates only the intended purchaser/team. Confirm worker retries after a verifier outage, then finish the combined launch prerequisites before owner device acceptance.

## Implementation checks

- Node tests cover secret/origin rejection, malformed and oversized requests, strict action validation, concurrency bounds, redacted failures, real worker behavior and signing-key type.
- Transport tests require HTTPS, forbid redirects, cap response size and bind responses to a fresh request ID, the selected Apple environment and this app's bundle ID.
- The Deno compatibility suite uses `npm ci`'s package lock and pinned Deno 2.1.4. It explicitly records the unsupported local certificate API and tests the remote path without network permissions or private keys. Passing that suite is not a claim that local Apple verification works on Deno.
- On failure, verification denies paid access changes; queued purchase delivery/reconciliation remains responsible for retries. Rotating the shared secret requires updating both services together. Disable paid readiness if the verifier is unavailable; do not add an unverified receipt fallback.

## Sources checked

- [Render compute pricing](https://render.com/articles/render-vs-railway)
- [Blueprint fields and deployment behavior](https://render.com/docs/blueprint-spec)
- [Node version configuration](https://render.com/docs/node-version)
- [Environment variables and secrets](https://render.com/docs/configure-environment-variables)
- [Apple's certificate verification implementation](https://github.com/apple/app-store-server-library-node/blob/main/jws_verification.ts)

Hosting approval resolves the runtime choice only. Hosted billing deletion/retention, paid-team remainder behavior, restricted database identity, remote program/consent/credential provisioning, capture integration and real receipt/storage/retention services still require completion before launch.
