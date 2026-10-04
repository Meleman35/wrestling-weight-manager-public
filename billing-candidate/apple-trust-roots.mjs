import {X509Certificate,createHash} from 'node:crypto';
import roots from './apple-trust-roots.json' with {type:'json'};
// Public trust anchors downloaded from Apple's PKI page, not private signing keys.
export function appleTrustRoots(){
 return roots.map(root=>{
  const bytes=Buffer.from(root.derBase64,'base64'),certificate=new X509Certificate(bytes);
  if(createHash('sha256').update(bytes).digest('hex')!==root.sha256||!certificate.ca||
   certificate.subject!==certificate.issuer||!certificate.verify(certificate.publicKey))throw Error('Apple trust root integrity failed');
  return bytes;
 });
}
