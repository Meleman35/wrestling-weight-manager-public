import {randomUUID} from 'node:crypto';
import {validAppleVerifierSecret} from './apple-verifier-secret.mjs';
const fail=()=>{throw Error('Apple verification unavailable');};
const object=x=>!!x&&typeof x==='object'&&!Array.isArray(x);
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(x);
// Private server-to-server transport. Public clients never supply this URL or key.
export function createRemoteAppleEvidenceAdapter({url,secret,config,fetchImpl=fetch}){
 const endpoint=new URL(url);
 if(endpoint.protocol!=='https:'||endpoint.username||endpoint.password||endpoint.search||endpoint.hash||endpoint.port||
  endpoint.pathname!=='/apple'||!validAppleVerifierSecret(secret)||!['Sandbox','Production'].includes(config?.environment)||
  config.bundleID!=='com.damonmele.wrestlingmanager')throw Error('Private Apple verifier configuration required');
 async function send(action,input){
  const requestID=randomUUID();
  const body=JSON.stringify({requestID,environment:config.environment,action,input});
  if(new TextEncoder().encode(body).length>196608)fail();
  const response=await fetchImpl(endpoint.href,{method:'POST',redirect:'error',signal:AbortSignal.timeout(30000),
   headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body});
  if(response.status!==200||response.url!==endpoint.href||!response.headers.get('content-type')?.toLowerCase().startsWith('application/json'))fail();
  const reader=response.body?.getReader();if(!reader)fail();
  let size=0;const chunks=[];
  try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>65536)fail();chunks.push(value);}}
  catch{await reader.cancel().catch(()=>{});fail();}finally{reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  let value;try{value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{fail();}
  if(!object(value)||Object.keys(value).sort().join(',')!=='environment,requestID,result'||value.requestID!==requestID||
   value.environment!==config.environment||!object(value.result))fail();
  const result=value.result,evidence=action==='notificationTransaction'?result.evidence:result;
  if(action==='notificationTransaction'&&!uuid(result.notificationID))fail();
  if(action==='notificationTransaction'&&result.kind==='test'){
   if(Object.keys(result).sort().join(',')!=='kind,notificationID')fail();return result;
  }
  if(!object(evidence)||evidence.environment!==config.environment||evidence.bundleID!==config.bundleID)fail();
  // Existing delivery/notification policy validates all evidence fields and
  // immutable purchase bindings before any database write or paid access.
  return result;
 }
 return Object.freeze({resolve:input=>send('resolve',input),notificationTransaction:input=>send('notificationTransaction',input),
  refresh:evidence=>send('refresh',Object.fromEntries(['environment','bundleID','originalTransactionID','appAccountToken'].map(key=>[key,evidence?.[key]])))});
}
