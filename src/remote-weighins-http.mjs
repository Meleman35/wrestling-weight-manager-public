// Server-only HTTP composition. No endpoint is deployed by importing this module.
// authenticate and allowRequest must use trusted server session/rate-limit state.
const headers={'Cache-Control':'no-store, private','X-Content-Type-Options':'nosniff','Content-Type':'application/json'};
class BadRequest extends Error {}
const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
async function boundedJson(request,max) {
 const length=request.headers.get('content-length');
 if(length!==null&&(!/^\d+$/.test(length)||Number(length)>max))throw new BadRequest();
 if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')throw new BadRequest();
 const reader=request.body?.getReader();if(!reader)throw new BadRequest();
 const chunks=[];let size=0;
 try {for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>max)throw new BadRequest();chunks.push(value);}}
 catch(e){await reader.cancel().catch(()=>{});throw e;}finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 try {const body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));if(!object(body))throw new BadRequest();return body;}
 catch{throw new BadRequest();}
}
const bindingKeys=['captureId','programId','windowId','clubId','athleteId','operatorId','generation','weight','unit','capturedAt','photoCapturedAt','method'];
export function createRemoteReportingHandler({authenticate,allowRequest,authorizeCapture,photos,reporting,basePath='/functions/v1/remote-weighins',allowedOrigins=[]}) {
 if(![authenticate,allowRequest,authorizeCapture,photos?.upload,photos?.read,reporting?.submit,reporting?.report,reporting?.evidenceForSubmission,reporting?.context].every(f=>typeof f==='function'))throw Error('Trusted HTTP dependencies required');
 const respond=(status,body,extra={})=>new Response(JSON.stringify(body),{status,headers:{...headers,...extra}});
 return async request=>{
  const origin=request.headers.get('origin');
  if(origin&&!allowedOrigins.includes(origin))return respond(403,{error:'Access denied'});
  const cors=origin?{'Access-Control-Allow-Origin':origin,'Vary':'Origin'}:{};
  const path=new URL(request.url).pathname;
  const action=path.startsWith(basePath+'/')?path.slice(basePath.length+1):'';
  if(!['context','authorize','photo','submit','report','photo-read'].includes(action))return respond(404,{error:'Unavailable'},cors);
  if(request.method==='OPTIONS'&&origin)return new Response(null,{status:204,headers:{...headers,...cors,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'Authorization, Content-Type'}});
  if(request.method!=='POST')return respond(405,{error:'POST required'},{...cors,Allow:'POST'});
  let session;
  try{session=await authenticate(request);}catch{return respond(401,{error:'Sign in required'},cors);}
  if(!session)return respond(401,{error:'Sign in required'},cors);
  try{
   if(await allowRequest(session,action)!==true)return respond(429,{error:'Try again later'},cors);
   const body=await boundedJson(request,action==='photo'?7*1024*1024:12000);
   if(action==='context')return respond(200,await reporting.context(session),cors);
   if(action==='authorize'){
    if(await authorizeCapture(session,body)!==true)return respond(403,{error:'Access denied'},cors);
    return respond(200,{authorized:true},cors);
   }
   if(action==='photo'){
    if(!object(body.payload)||typeof body.jpegBase64!=='string'||body.jpegBase64.length>Math.ceil(5*1024*1024/3)*4||body.jpegBase64.length%4!==0||/[^A-Za-z0-9+/=]/.test(body.jpegBase64))throw new BadRequest();
    const jpeg=new Uint8Array(Buffer.from(body.jpegBase64,'base64'));
    if(!jpeg.length||jpeg.length>5*1024*1024||Buffer.from(jpeg).toString('base64')!==body.jpegBase64)throw new BadRequest();
    const binding=Object.fromEntries(bindingKeys.map(k=>[k,body.payload[k]]));
    const result=await photos.upload(session,{evidenceId:body.payload.evidenceId,binding,jpeg});
    return respond(200,result,cors);
   }
   if(action==='submit')return respond(200,await reporting.submit(session,body),cors);
   if(action==='report')return respond(200,await reporting.report(session,body),cors);
   if(typeof body.submissionId!=='string')throw new BadRequest();
   const evidenceId=await reporting.evidenceForSubmission(session,{submissionId:body.submissionId});
   const result=await photos.read(session,evidenceId);
   return new Response(result.bytes,{status:200,headers:{...headers,...cors,'Content-Type':'image/jpeg'}});
  }catch(e){return respond(e instanceof BadRequest?400:403,{error:e instanceof BadRequest?'Invalid request':'Request could not be authorized or completed'},cors);}
 };
}
