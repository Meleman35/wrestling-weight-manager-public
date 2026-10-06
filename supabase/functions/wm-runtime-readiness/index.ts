import {appleTrustRoots} from './apple-trust-roots.mjs';
import {createRuntimeReadiness} from './remote-check.mjs';
// Read-only deployment diagnostic. JWT verification stays enabled at the gateway.
// The same trust-root check is required by the billing runtime and Apple SDK.
let appleCertificateVerification = false;
try { appleCertificateVerification = appleTrustRoots().length === 3; } catch { /* Not deployable on this runtime. */ }
Deno.serve(createRuntimeReadiness({readSecret:(name: string)=>Deno.env.get(name),appleCertificateVerification}));
