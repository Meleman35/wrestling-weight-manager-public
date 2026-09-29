// Reviewer-only Storage access goes through this endpoint so expiry is server enforced.
const origin='https://theteammanager.app';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'content-type, apikey, authorization, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Content-Type':'application/json','Vary':'Origin'};
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
type Dependencies={env:(name:string)=>string|undefined;fetch:typeof fetch};
export function createHandler(deps:Dependencies){return async(req:Request)=>{
 if(req.headers.get('Origin')&&req.headers.get('Origin')!==origin)return json(403,{error:'Open conversation review in Wrestling Manager.'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return json(405,{error:'Method not allowed.'});
 const authorization=req.headers.get('Authorization');
 if(!authorization||!/^Bearer \S+$/i.test(authorization))return json(401,{error:'Sign in with your personal account.'});
 const url=deps.env('SUPABASE_URL'),anon=deps.env('SUPABASE_ANON_KEY'),service=deps.env('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!anon||!service)return json(503,{error:'Review media is temporarily unavailable.'});
 try{
  const raw=await req.text();if(raw.length>1000)return json(400,{error:'Invalid request.'});
  let b;try{b=JSON.parse(raw);}catch{return json(400,{error:'Invalid request.'});}
  if(!b||!uuid(b.thread_id)||!uuid(b.attachment_id)||Object.keys(b).some(k=>!['thread_id','attachment_id'].includes(k)))return json(400,{error:'Invalid request.'});
  const userHeaders={apikey:anon,Authorization:authorization,'Content-Type':'application/json'};
  const auth=await deps.fetch(url+'/auth/v1/user',{headers:userHeaders,signal:AbortSignal.timeout(10000)});
  if(!auth.ok||!(await auth.json())?.id)return json(401,{error:'Sign in again with your personal account.'});
  const context=await deps.fetch(url+'/rest/v1/rpc/conversation_review_request',{method:'POST',headers:userHeaders,body:JSON.stringify({p_action:'media',p_data:{thread_id:b.thread_id,attachment_id:b.attachment_id}}),signal:AbortSignal.timeout(10000)});
  if(!context.ok)return json(403,{error:'This media is unavailable or your review access ended.'});
  const media=await context.json();
  // The authenticated RPC selects this path from a live attachment, never from the caller.
  const parts=typeof media?.path==='string'?media.path.split('/'):[];
  if(parts.length<4||parts.slice(0,3).some((p:string)=>!uuid(p))||parts.some((p:string)=>!p||p==='.'||p==='..'))return json(403,{error:'This media is unavailable.'});
  const encoded=parts.map(encodeURIComponent).join('/');
  const signed=await deps.fetch(url+'/storage/v1/object/sign/communication-media/'+encoded,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({expiresIn:60}),signal:AbortSignal.timeout(10000)});
  if(!signed.ok)return json(502,{error:'This media is temporarily unavailable.'});
  const result=await signed.json();
  if(typeof result?.signedURL!=='string'||!result.signedURL.startsWith('/object/sign/communication-media/'))return json(502,{error:'This media is temporarily unavailable.'});
  return json(200,{signedUrl:url+'/storage/v1'+result.signedURL,expiresIn:60});
 }catch{return json(503,{error:'Review media is temporarily unavailable. Reopen the conversation to retry.'});}
};}
