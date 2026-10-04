import {Buffer} from 'node:buffer';

// Accept a 32-byte secret from either OpenSSL (hex) or Render (Base64).
// Do not trim, decode for comparison, or log it: both services must store the
// exact same text. Encoding validation does not replace random generation.
export function validAppleVerifierSecret(value){
 if(typeof value!=='string')return false;
 if(/^[a-f0-9]{64}$/i.test(value))return true;
 return /^[A-Za-z0-9+/]{43}=$/.test(value)&&Buffer.from(value,'base64').toString('base64')===value;
}
