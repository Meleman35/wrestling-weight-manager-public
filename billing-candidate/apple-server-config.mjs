import {proposedProducts} from './subscription-policy.mjs';
// Server secret-store reader only. This module must never be bundled for clients.
export function readAppleServerConfiguration({readSecret,rootCertificates,environment}){
 if(typeof readSecret!=='function'||!['Production','Sandbox'].includes(environment)||!Array.isArray(rootCertificates)||!rootCertificates.length)throw Error('Apple server configuration unavailable');
 const signingKey=readSecret('APPLE_IAP_PRIVATE_KEY');
 if(typeof signingKey!=='string'||!signingKey.startsWith('-----BEGIN PRIVATE KEY-----')||!signingKey.trimEnd().endsWith('-----END PRIVATE KEY-----'))throw Error('Apple server configuration unavailable');
 return {environment,bundleID:'com.damonmele.wrestlingmanager',appAppleID:6815511370,
  keyID:'79R244P822',issuerID:'b5931be7-ac93-4ab3-9b1a-15e1dd26a549',
  signingKey,rootCertificates,products:proposedProducts};
}
