import {createBillingConnectionPool} from '../../supabase/functions/wm-billing-readiness/billing-connection.mjs';
import {validAppleVerifierSecret} from '../../billing-candidate/apple-verifier-secret.mjs';
import {validNotificationTestCall,validTestToken} from '../../billing-candidate/apple-notification-test.mjs';
const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
const reply=(status,value)=>Response.json(value,{status,headers});
async function boundedJSON(body,limit){
 const reader=body?.getReader();if(!reader)throw Error('Body required');let size=0;const chunks=[];
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit)throw Error('Body too large');chunks.push(value);}}
 catch(error){await reader.cancel().catch(()=>{});throw error;}finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 return JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(bytes));
}
function safeResult(result,action){
 if(result?.state==='apple_error'&&Object.keys(result).sort().join(',')==='appleCode,httpStatus,state'&&Number.isInteger(result.httpStatus)&&result.httpStatus>=400&&result.httpStatus<=599&&(result.appleCode===null||Number.isSafeInteger(result.appleCode)))return result;
 if(action==='testRequest'&&result?.state==='requested'&&Object.keys(result).sort().join(',')==='state,testNotificationToken'&&validTestToken(result.testNotificationToken))return result;
 if(action==='testStatus'&&result?.state==='checked'&&Object.keys(result).sort().join(',')==='attempts,delivered,notificationID,state,verified'&&result.verified===true&&typeof result.delivered==='boolean'&&/^[a-f0-9-]{36}$/i.test(result.notificationID)&&Array.isArray(result.attempts)&&result.attempts.length<=6&&result.attempts.every(a=>Object.keys(a).sort().join(',')==='at,result'&&Number.isSafeInteger(a.at)&&a.at>=0&&/^[A-Z_]{1,80}$/.test(a.result))&&result.delivered===result.attempts.some(a=>a.result==='SUCCESS'))return result;
 throw Error('Unconfirmed Apple test');
}
// Temporary operator-only bridge. Its deployment supplies a fixed expiry and
// uses the database's private scheduler capability, never a client JWT.
export function createAppleNotificationDiagnostic({Pool,readSecret,expiresAt,clock=Date.now,fetchImpl=fetch,makePool=createBillingConnectionPool}){
 if(!Number.isSafeInteger(expiresAt))throw Error('Diagnostic expiry required');
 let pool,inFlight=false;
 return async request=>{
  if(clock()>=expiresAt)return reply(410,{error:'diagnostic_closed'});
  if(request.method!=='POST'||request.headers.has('origin'))return reply(403,{error:'not_authorized'});
  const token=request.headers.get('authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
  if(!token)return reply(403,{error:'not_authorized'});
  if(inFlight)return reply(429,{error:'retry_later'});inFlight=true;
  try{
   pool??=makePool({Pool,connectionURL:readSecret('BILLING_DATABASE_URL')});
   const connection=await pool.connect();let allowed;
   try{allowed=(await connection.query('select wm_billing.authorize_notification_worker($1) and wm_billing.notification_deployment_ready() as allowed',[token])).rows[0]?.allowed===true;}finally{connection.release();}
   if(!allowed)return reply(403,{error:'not_authorized'});
   let body;try{body=await boundedJSON(request.body,4096);}catch{return reply(400,{error:'invalid_request'});}
   if(!body||Array.isArray(body)||Object.keys(body).sort().join(',')!=='action,environment,input'||!['Sandbox','Production'].includes(body.environment)||!validNotificationTestCall(body.action,body.input))return reply(400,{error:'invalid_request'});
   const url=readSecret('APPLE_VERIFIER_URL'),secret=readSecret('APPLE_VERIFIER_SHARED_SECRET');
   if(url!=='https://wm-apple-verifier.onrender.com/apple'||!validAppleVerifierSecret(secret))throw Error('Verifier unavailable');
   const requestID=crypto.randomUUID();
   const response=await fetchImpl(url,{method:'POST',redirect:'error',signal:AbortSignal.timeout(30000),headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify({...body,requestID})});
   if(response.status!==200||response.url!==url||!response.headers.get('content-type')?.startsWith('application/json'))throw Error('Verifier unavailable');
   const value=await boundedJSON(response.body,8192);
   if(value?.requestID!==requestID||value?.environment!==body.environment||Object.keys(value).sort().join(',')!=='environment,requestID,result')throw Error('Unconfirmed response');
   return reply(200,{environment:body.environment,...safeResult(value.result,body.action)});
  }catch{return reply(503,{error:'apple_test_unavailable'});}finally{inFlight=false;}
 };
}
