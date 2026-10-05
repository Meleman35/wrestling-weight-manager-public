# Private billing database connection

The Apple verifier is live, and Supabase's saved URL/shared secret passed authentication. The verifier has no database credentials. The billing server separately requires a restricted database identity before its runtime can start.

Confirmed project: `vfocpoyexnjsjpxhhyqr`, region `us-west-2`, PostgreSQL 17.6.1.166. The owner supplied screenshots confirming Session pooler host `aws-0-us-west-2.pooler.supabase.com`, port `5432`, database `postgres` on October 4 at 7:04 PM Mountain. The direct database hostname is `db.vfocpoyexnjsjpxhhyqr.supabase.co`.

## Provisioned identity

Migration `20261005011326_billing_runtime_identity` is applied. The source was generated with the Supabase CLI and renamed to the actual version recorded by the migration API. It creates the NOLOGIN permission role `wm_billing_runtime` and a separate `wm_billing_service` login with an eight-connection limit. Both lack superuser, RLS bypass, role/database creation and replication privileges. The service can explicitly select the runtime role, but does not inherit it or administer it.

The migration generates a 32-byte random credential inside PostgreSQL, applies SCRAM password encryption and stores the complete connection URL in the existing Vault as `wm-billing-database-url`. It never returns the credential. An existing role or named secret stops the migration, and a failure rolls back both roles and the secret. No existing database password was reset.

Live verification confirmed zero application-table privileges for this login, no Vault read permission for the billing/client roles, unchanged deletion schema hash `c1f0c928a7eefd97e1cf22413ae70c730d97dd608417476383d6c635f902bdf8`, and a matching approved catalog. The security-advisor findings are unchanged from the pre-migration baseline. No billing tables, entitlements or customer records were deployed or changed.

## Owner's private copy step

1. Open [Vault secrets](https://supabase.com/dashboard/project/vfocpoyexnjsjpxhhyqr/integrations/vault/secrets).
2. Find `wm-billing-database-url`. Reveal its value with the eye button and use the copy control. Keep it out of chat and screenshots.
3. Open [Edge Function Secrets](https://supabase.com/dashboard/project/vfocpoyexnjsjpxhhyqr/functions/secrets). Add `BILLING_DATABASE_URL`, paste the copied value, and save.

The connected tools cannot write Edge Function Secrets, so this copy requires the owner. The value is already complete; do not substitute the ordinary `postgres` login, change the port or append URL options.

## Read-only diagnostic and remaining gates

`wm-billing-readiness` version 1 is active with gateway JWT verification enabled. Its initial live invocation returned HTTP 200 and all database readiness flags false because the Edge secret has not yet been added. It never enables billing, reads customer data or returns provider errors, credential values or hashes. It rejects browser origins and non-POST requests and coalesces repeated checks per isolate.

The shared connection adapter enforces the exact host, project login and session port, verified TLS, one pooled connection and bounded timeouts. It checks the actual session identity before selecting the runtime role, then checks the selected role. Privileged or unexpected identities are discarded. Synthetic tests cover role restrictions, atomic provisioning failure, overwrite refusal, redaction, endpoint restrictions and connection cleanup. The Vault test fixture does not claim to validate Vault's encryption or a real password login.

After the owner saves the Edge secret, verify the live connection and role checks. Full billing schema/catalog, write-freeze, complete deletion-worker and scheduler acceptance remain required before payment activation. A successful database connection alone does not authorize paid access.

Reference checked October 5: [Supabase database connection modes](https://supabase.com/docs/guides/database/connecting-to-postgres).
