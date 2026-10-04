// WebCrypto encrypted queue. Storage/key providers must be native-protected or
// IndexedDB-backed; this module never writes localStorage or plaintext media.
import {remoteExpiresAt} from "./remote-weighins-policy.mjs";
const fail=m=>{throw Error(m);};
export function createRemoteOutbox({crypto,storage,key,scope,now=Date.now,maxEntries=200,maxBytes=32*1024*1024}) {
 if(!crypto?.subtle||!key||![storage?.put,storage?.get,storage?.list,storage?.remove].every(f=>typeof f==='function')||!scope?.accountId||!scope?.clubId)fail('Protected queue dependencies required');
 const owner=Object.freeze({...scope}),prefix=JSON.stringify([owner.accountId,owner.clubId]);let active=true,chain=Promise.resolve();
 const aad=id=>new TextEncoder().encode(JSON.stringify([owner.accountId,owner.clubId,id]));
 const check=()=>{if(!active)fail('Queue locked');};
 const run=fn=>{const job=chain.then(()=>{check();return fn();});chain=job.catch(()=>{});return job;};
 async function decode(id,value){check();const decrypted=await crypto.subtle.decrypt({name:'AES-GCM',iv:value.iv,additionalData:aad(id)},key,value.ciphertext);check();const row=JSON.parse(new TextDecoder().decode(decrypted));if(row.payload.submissionId!==id||row.payload.operatorId!==owner.accountId||row.payload.clubId!==owner.clubId)fail('Queue identity mismatch');return row;}
 async function live(id,row){const expiry=Date.parse(remoteExpiresAt(row.payload));if(now()>=expiry){await storage.remove(prefix,id);return false;}return true;}
 async function write(id,row){check();const iv=crypto.getRandomValues(new Uint8Array(12));const raw=new TextEncoder().encode(JSON.stringify(row));const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad(id)},key,raw);check();await storage.put(prefix,id,{iv,ciphertext});check();}
 return Object.freeze({
  lock(){active=false;},
  async enqueue(payload,jpeg){return run(async()=>{
   if(!payload?.submissionId||payload.operatorId!==owner.accountId||payload.clubId!==owner.clubId||!(jpeg instanceof Uint8Array)||jpeg.byteLength>5*1024*1024)fail('Queue capture scope mismatch');
   if(now()>=Date.parse(remoteExpiresAt(payload)))fail('Capture retention expired');
   const id=payload.submissionId,existing=await storage.get(prefix,id);
   // Keep the exact frozen envelope/photo across restarts. Native APIs should
   // pass binary buffers; JSON array representation is internal ciphertext only.
   const row={payload,photo:Array.from(jpeg),receipt:null};
   if(existing){const prior=await decode(id,existing);if(JSON.stringify(prior.payload)!==JSON.stringify(payload)||JSON.stringify(prior.photo)!==JSON.stringify(row.photo))fail('Queue retry conflict');return id;}
   const items=await storage.list(prefix);const used=items.reduce((n,x)=>n+x.value.ciphertext.byteLength,0);
   if(items.length>=maxEntries||used+new TextEncoder().encode(JSON.stringify(row)).length+16>maxBytes)fail('Queue storage limit reached');
   await write(id,row);return id;
  });},
  async pending(){return run(async()=>{const rows=[];for(const {id,value} of await storage.list(prefix)){const row=await decode(id,value);if(!await live(id,row))continue;rows.push({submissionId:id,status:row.receipt?'submitted':'pending',receipt:row.receipt});}return rows;});},
  async deliver(id,{authorize,uploadPhoto,submit}){return run(async()=>{
   if(![authorize,uploadPhoto,submit].every(f=>typeof f==='function'))fail('Delivery adapters required');
   const value=await storage.get(prefix,id);if(!value)fail('Pending capture unavailable');const row=await decode(id,value);if(!await live(id,row))fail('Capture retention expired');if(row.receipt)return row.receipt;
   await authorize(row.payload);check();if(!await live(id,row))fail('Capture retention expired');await uploadPhoto(row.payload,new Uint8Array(row.photo));check();await authorize(row.payload);check();if(!await live(id,row))fail('Capture retention expired');
   const receipt=await submit(row.payload);check();
   if(receipt?.submissionId!==id||receipt?.status!=='submitted'||!receipt.receiptId||!Number.isFinite(Date.parse(receipt.receivedAt)))fail('Submission receipt not confirmed');
   // Retain encrypted photo on any failure, including failed receipt persistence.
   // A retry returns the same server receipt, rather than creating a new capture.
   if(!await live(id,row))fail('Capture retention expired');await write(id,{...row,receipt});return receipt;
  });},
  async removeConfirmed(id){return run(async()=>{const value=await storage.get(prefix,id);if(!value)return;const row=await decode(id,value);if(!row.receipt)fail('Pending capture requires explicit discard');await storage.remove(prefix,id);});}
 });
}
