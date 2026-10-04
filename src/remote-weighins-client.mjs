// Browser transport for the fixed private endpoint. Claims below identify the
// local session lifetime only; the server independently verifies all authority.
const endpoint='https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/remote-weighins';
function identity(session) {
 if(!session?.user?.id||typeof session.access_token!=='string')throw Error('Personal session required');
 try {
  const part=session.access_token.split('.')[1];
  const claims=JSON.parse(atob(part.replaceAll('-','+').replaceAll('_','/')));
  if(claims.sub!==session.user.id||typeof claims.session_id!=='string'||!claims.session_id)throw Error();
  return JSON.stringify([session.user.id,claims.session_id]);
 } catch {throw Error('Personal session required');}
}
async function readBody(response,limit,signal) {
 const length=response.headers.get('content-length');
 if(length!==null&&(!/^\d+$/.test(length)||Number(length)>limit))throw Error('Response too large');
 const reader=response.body?.getReader();if(!reader)throw Error('Empty response');
 const chunks=[];let size=0;
 const cancel=()=>{reader.cancel().catch(()=>{});};signal.addEventListener('abort',cancel,{once:true});
 try {
  for(;;){if(signal.aborted)throw Error('Reporting request cancelled');const {done,value}=await reader.read();if(signal.aborted)throw Error('Reporting request cancelled');if(done)break;size+=value.byteLength;if(size>limit)throw Error('Response too large');chunks.push(value);}
  const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}return bytes;
 } catch(error){cancel();throw error;}
 finally{signal.removeEventListener('abort',cancel);reader.releaseLock();}
}
export function createRemoteReportingClient({initialSession,getSession,isCurrent,publishableKey,fetch=globalThis.fetch,timeoutMs=30000}) {
 if(![getSession,isCurrent,fetch].every(f=>typeof f==='function')||typeof publishableKey!=='string'||!publishableKey||!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>60000)throw Error('Reporting client dependencies required');
 const owner=identity(initialSession),requests=new Set();let active=true;
 const check=()=>{if(!active||isCurrent()!==true)throw Error('Reporting session closed');};
 const session=async()=>{check();const next=await getSession();check();if(identity(next)!==owner)throw Error('Reporting session changed');return next;};
 async function request(action,body,photo=false){
  const current=await session(),controller=new AbortController();requests.add(controller);
  const timer=setTimeout(()=>controller.abort(),timeoutMs);
  try {
   const response=await fetch(endpoint+'/'+action,{method:'POST',redirect:'error',cache:'no-store',credentials:'omit',signal:controller.signal,headers:{Authorization:'Bearer '+current.access_token,apikey:publishableKey,'Content-Type':'application/json'},body:JSON.stringify(body)});
   check();if(!response.ok)throw Error('Reporting unavailable');
   const type=response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
   if(type!==(photo?'image/jpeg':'application/json'))throw Error('Unexpected response type');
   const bytes=await readBody(response,photo?5*1024*1024:4*1024*1024,controller.signal);
   await session();if(controller.signal.aborted)throw Error('Reporting request cancelled');
   if(photo){if(bytes.length<4||bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)throw Error('Invalid photo');return new Blob([bytes],{type:'image/jpeg'});}
   return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
  }finally{clearTimeout(timer);controller.abort();requests.delete(controller);}
 }
 return Object.freeze({context:()=>request('context',{}),report:query=>request('report',query),photo:query=>request('photo-read',query,true),stop(){active=false;for(const controller of requests)controller.abort();requests.clear();}});
}
