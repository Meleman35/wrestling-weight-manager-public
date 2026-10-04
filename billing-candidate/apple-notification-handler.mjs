// Server-only V2 receiver candidate. Configure URLs only after deployment.
// apple must be the production AppleEvidenceAdapter. persistVerified must commit
// to a durable, idempotent inbox before returning its acknowledgement.
const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
const reply=(status,error)=>new Response(JSON.stringify(error?{error}:{accepted:true}),{status,headers});
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(x);
class InvalidBody extends Error {}
async function readPayload(request){
 if(!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type')??''))throw new InvalidBody();
 const limit=196608,length=request.headers.get('content-length');
 if(length!==null&&(!/^\d+$/.test(length)||Number(length)>limit))throw new InvalidBody();
 const reader=request.body?.getReader();if(!reader)throw new InvalidBody();
 const chunks=[];let count=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;count+=value.byteLength;if(count>limit)throw new InvalidBody();chunks.push(value);}}
 catch(e){await reader.cancel().catch(()=>{});throw e;}finally{reader.releaseLock();}
 const bytes=new Uint8Array(count);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.byteLength;}
 let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{throw new InvalidBody();}
 if(!body||Array.isArray(body)||typeof body!=='object'||Object.keys(body).length!==1||
  typeof body.signedPayload!=='string'||body.signedPayload.length<10||body.signedPayload.length>131072||
  !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(body.signedPayload))throw new InvalidBody();
 return body.signedPayload;
}
export function createAppleNotificationHandler({enabled=false,apple,persistVerified,allowRequest}){
 if(typeof apple?.notificationTransaction!=='function'||typeof persistVerified!=='function'||typeof allowRequest!=='function')throw Error('Trusted notification dependencies required');
 return async request=>{
  if(!enabled)return reply(503,'notifications_unavailable');
  // Apple authenticates through its signed JWS, not a user's Supabase token.
  if(request.headers.has('origin'))return reply(403,'server_requests_only');
  if(request.method!=='POST')return reply(405,'post_required');
  try{
   if(await allowRequest(request)!==true)return reply(429,'retry_later');
   const signedPayload=await readPayload(request);
   const verified=await apple.notificationTransaction(signedPayload);
   if(!uuid(verified?.notificationID))throw Error('invalid_verifier_result');
   if(verified.kind==='test')return reply(200);
   if(!verified.evidence)throw Error('invalid_verifier_result');
   const ack=await persistVerified(verified);
   if(ack?.notificationID!==verified.notificationID||!['stored','duplicate'].includes(ack.status))throw Error('not_durable');
   return reply(200);
  }catch(e){
   // A non-2xx response preserves Apple's retry behavior. Never return JWS,
   // database diagnostics or an unverified notification label to the caller.
   return reply(e instanceof InvalidBody?400:503,e instanceof InvalidBody?'invalid_request':'notification_unconfirmed');
  }
 };
}
