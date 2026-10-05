# Private billing database connection

The Apple verifier is live, and Supabase's saved URL/shared secret passed authentication. The verifier has no database credentials. The billing server separately requires a restricted database identity before its runtime can start.

Confirmed project: `vfocpoyexnjsjpxhhyqr`, region `us-west-2`, PostgreSQL 17.6.1.166. The direct database hostname is `db.vfocpoyexnjsjpxhhyqr.supabase.co`. No billing schema or `wm_billing_service` login has been provisioned in production. Existing production records have not been changed.

## Owner detail needed

Open [this project's connection settings](https://supabase.com/dashboard/project/vfocpoyexnjsjpxhhyqr?showConnect=true&method=session), choose **Session pooler**, then **View parameters** if present. Copy only the **Host** value ending in `.pooler.supabase.com`. This hostname is not a password. Do not send the full connection string, database password or any private key.

The connected tools expose the direct hostname and region but not this project's assigned shared-pooler hostname. It was not present in the project files. Do not guess its cluster prefix from the region or replace an existing database password.

## Implementation after the host is confirmed

- Provision a restricted login and the `wm_billing_runtime` permission role with no superuser or RLS-bypass privileges. Generate/store credentials privately; never put them in this document, source, an app bundle or logs.
- Use an encrypted connection with certificate verification and a bounded connection pool. The existing runtime checks both the login and effective role. Session pooling supports its connection-level role selection; transaction pooling requires a separately tested per-transaction role adapter.
- Store the completed credential privately in Supabase's Edge Function Secrets. The connected tool set does not provide a secret-writing operation, so the owner must perform that private copy step when the credential is ready.
- Verify a read-only connection and exact role permissions, then complete billing schema/catalog, write-freeze, full deletion-worker and scheduler acceptance before activating billing. A working database connection alone does not authorize paid access.

Reference checked October 5: [Supabase database connection modes](https://supabase.com/docs/guides/database/connecting-to-postgres).
