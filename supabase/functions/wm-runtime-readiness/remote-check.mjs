const verifierURL = 'https://wm-apple-verifier.onrender.com/apple';
const headers = {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};

async function smallJSON(response) {
  if (!response.body) return null;
  const reader = response.body.getReader();
  const chunks = []; let size = 0;
  try {
    for (;;) {
      const {done,value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1024) { await reader.cancel(); return null; }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.byteLength; }
    return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
  } finally { reader.releaseLock(); }
}

// Checks only the known verifier's authentication boundary. The deliberately
// invalid body cannot reach Apple's API or alter any subscription record.
// Never return, log, hash, or forward secrets to a request-selected destination.
export function createRuntimeReadiness({readSecret,appleCertificateVerification=false,fetchImpl=fetch,now=Date.now}) {
  let cached, expires = 0;
  async function check() {
    const url = readSecret('APPLE_VERIFIER_URL');
    const secret = readSecret('APPLE_VERIFIER_SHARED_SECRET');
    const result = {
      appleCertificateVerification,
      remoteVerifierURLConfigured: url === verifierURL,
      remoteVerifierSecretConfigured: typeof secret === 'string' && (/^[a-f0-9]{64}$/i.test(secret) || /^[A-Za-z0-9+/]{43}=$/.test(secret)),
      remoteVerifierReachable: false,
      remoteVerifierAuthenticated: false,
      billingEnabled: false,
    };
    if (!result.remoteVerifierURLConfigured || !result.remoteVerifierSecretConfigured) return result;
    try {
      const response = await fetchImpl(verifierURL,{
        method:'POST', redirect:'error', signal:AbortSignal.timeout(10000),
        headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},
        body:'{}',
      });
      const body = await smallJSON(response);
      result.remoteVerifierReachable = (response.status === 400 && body?.error === 'invalid_request') ||
        (response.status === 403 && body?.error === 'not_authorized');
      result.remoteVerifierAuthenticated = response.status === 400 && body?.error === 'invalid_request';
    } catch { /* Return booleans only; network errors can contain request details. */ }
    return result;
  }
  return async request => {
    if (request.method !== 'POST') return new Response(null,{status:405,headers:{...headers,Allow:'POST'}});
    if (request.headers.has('origin')) return Response.json({error:'not_authorized'},{status:403,headers});
    // Coalesce concurrent requests and bound repeated probes per isolate.
    if (!cached || now() >= expires) { expires = now()+30000; cached = check(); }
    return Response.json(await cached,{headers});
  };
}
