// Server-only private Supabase photo provider. Never ship service credentials.
import {createHash} from 'node:crypto';
const BUCKET='remote-weighin-evidence';
const deny=message=>{throw Error(message);};
const keyPattern=/^[a-zA-Z0-9_-]{1,160}$/;
const safe=value=>typeof value==='string'&&keyPattern.test(value);
export function createRemotePhotoProvider({supabase,authorize,verifyCapture,normalizeJPEG,evidenceStore,now=Date.now}) {
 if (!supabase?.storage||![authorize,verifyCapture,normalizeJPEG,evidenceStore?.find,evidenceStore?.reserve,evidenceStore?.confirm,evidenceStore?.revoke].every(x=>typeof x==='function'))deny('Private photo dependencies required');
 const bucket=supabase.storage.from(BUCKET);
 return Object.freeze({
  async upload(session,{evidenceId,binding,jpeg}) {
   if(!safe(evidenceId)||!binding||![binding.programId,binding.captureId,binding.operatorId].every(safe)||!(jpeg instanceof Uint8Array)||jpeg.length<4||jpeg.length>5*1024*1024||jpeg[0]!==255||jpeg[1]!==216||jpeg.at(-2)!==255||jpeg.at(-1)!==217)deny('Bounded JPEG capture required');
   // Uploaded JPEG is bound to trusted capture/session evidence, not an assertion
   // that a client field source:camera makes a picture authentic.
   await authorize(session,binding,'upload');await verifyCapture(session,binding);
   jpeg=await normalizeJPEG(jpeg);
   if(!(jpeg instanceof Uint8Array)||jpeg.length<4||jpeg.length>5*1024*1024||jpeg[0]!==255||jpeg[1]!==216||jpeg.at(-2)!==255||jpeg.at(-1)!==217)deny('Bounded normalized JPEG required');
   await authorize(session,binding,'upload');
   const digest=createHash('sha256').update(jpeg).digest('hex');
   const path=`${binding.programId}/${binding.captureId}/${evidenceId}.jpg`;
   const reservation=await evidenceStore.reserve({evidenceId,binding,path,digest,byteCount:jpeg.length});
   if(reservation.path!==path||reservation.digest!==digest||!reservation.binding||Object.keys(reservation.binding).length!==Object.keys(binding).length||Object.keys(binding).some(k=>reservation.binding[k]!==binding[k]))deny('Photo retry conflict');
   if(!reservation.confirmed){
    const result=await bucket.upload(path,jpeg,{contentType:'image/jpeg',upsert:false,cacheControl:'0'});
    if(result.error){
     // Lost upload acknowledgement can be recovered only by verifying the bytes
     // at the reserved immutable path, never by accepting an arbitrary conflict.
     const fetched=await bucket.download(path);
     if(fetched.error||!fetched.data||fetched.data.size>5*1024*1024)throw Error('Photo upload not confirmed');
     const stored=new Uint8Array(await fetched.data.arrayBuffer());
     if(createHash('sha256').update(stored).digest('hex')!==digest)deny('Stored photo does not match capture');
    }
   }
   await authorize(session,binding,'upload');await verifyCapture(session,binding);
   // Adapter must atomically check live authority + immutable reservation again.
   await evidenceStore.confirm({evidenceId,binding,digest,byteCount:jpeg.length});
   return {evidenceId,digest,byteCount:jpeg.length,status:'uploaded'};
  },
  async read(session,evidenceId) {
   if(!safe(evidenceId))deny('Invalid photo identity');
   const record=await evidenceStore.find(evidenceId);
   if(!record?.confirmed||record.revoked||!Number.isFinite(Date.parse(record.expiresAt))||Date.parse(record.expiresAt)<=now())deny('Photo unavailable');
   await authorize(session,record.binding,'read');
   const result=await bucket.download(record.path);
   if(result.error||!result.data||result.data.size>5*1024*1024)deny('Photo unavailable');
   const bytes=new Uint8Array(await result.data.arrayBuffer());
   if(bytes.length!==record.byteCount||createHash('sha256').update(bytes).digest('hex')!==record.digest)deny('Photo integrity failed');
   await authorize(session,record.binding,'read');
   const current=await evidenceStore.find(evidenceId);
   if(!current?.confirmed||current.revoked||!Number.isFinite(Date.parse(current.expiresAt))||Date.parse(current.expiresAt)<=now()||current.path!==record.path||current.digest!==record.digest)deny('Photo unavailable');
   // Serve via authenticated no-store response; never return a public/signed URL.
   return {bytes,contentType:'image/jpeg',headers:{'Cache-Control':'no-store, private','X-Content-Type-Options':'nosniff'}};
  },
  async purge(evidenceId) {
   // Internal retention/deletion worker only: revoke reads before physical delete.
   if(!safe(evidenceId))deny('Invalid photo identity');
   const r=await evidenceStore.revoke(evidenceId);if(!r)return {removed:true};
   const result=await bucket.remove([r.path]);if(result.error)deny('Photo purge needs retry');
   const check=await bucket.download(r.path);
   const code=String(check.error?.statusCode??check.error?.status??'');
   if(check.data||!['404','400'].includes(code)||!['not_found','NoSuchKey','404'].includes(String(check.error?.code??code)))deny('Photo removal could not be verified');
   return {removed:true};
  }
 });
}
