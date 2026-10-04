import {appleTrustRoots} from './apple-trust-roots.mjs';
// Read-only deployment diagnostic. JWT verification stays enabled at the gateway.
// The same trust-root check is required by the billing runtime and Apple SDK.
let appleCertificateVerification = false;
try { appleCertificateVerification = appleTrustRoots().length === 3; } catch { /* Not deployable on this runtime. */ }
Deno.serve((request: Request) => {
  if (request.method !== 'POST') return new Response(null, {status:405,headers:{Allow:'POST'}});
  return Response.json({appleCertificateVerification,billingEnabled:false},
    {headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
});
