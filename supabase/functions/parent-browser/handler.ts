import {newToken,tokenHash} from '../_shared/parent-tokens.ts';
// Emailed capabilities authorize this endpoint, never an athlete-supplied identity.
const origin='https://theteammanager.app';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'content-type, apikey, authorization, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Content-Type':'application/json','Vary':'Origin'};
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
const escape=(s:unknown)=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
type Dependencies={env:(name:string)=>string|undefined;fetch:typeof fetch};
export function createHandler(deps:Dependencies){return async(req:Request)=>{
 if(req.headers.get('Origin')&&req.headers.get('Origin')!==origin)return json(403,{error:'Open the private link in your email.'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return json(405,{error:'Method not allowed.'});
 const url=deps.env('SUPABASE_URL'),service=deps.env('SUPABASE_SERVICE_ROLE_KEY'),mail=deps.env('RESEND_API_KEY');
 if(!url||!service)return json(503,{error:'Parent choices are temporarily unavailable. Please try again later.'});
 const post=(path:string,body:unknown)=>deps.fetch(url+path,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const rpc=async(action:string,data:unknown)=>{const r=await post('/rest/v1/rpc/parent_browser_service',{p_action:action,p_data:data});if(!r.ok)throw Error('unavailable');return r.json();};
 try{
  const raw=await req.text();if(raw.length>2000)return json(400,{error:'Invalid request.'});
  let b;try{b=JSON.parse(raw);}catch{return json(400,{error:'Invalid request.'});}
  if(!b||!['preview','approve','revoke','join','recover'].includes(b.action))return json(400,{error:'Invalid request.'});
  if(b.action==='recover'){
   // All outcomes have the same public response, including unknown addresses.
   const answer={ok:true,message:'If this email has browser permissions, a management link will arrive shortly. Check spam, or wait an hour before requesting another.'};
   if(typeof b.email!=='string'||b.email.length>254||!/^\S+@\S+\.\S+$/.test(b.email.trim())||!mail)return json(200,answer);
   try{
    const contacts=await rpc('recovery_context',{email:b.email.trim().toLowerCase()});
    if(!Array.isArray(contacts)||!contacts.length)return json(200,answer);
    const links=[];
    for(const c of contacts.slice(0,10)){
     const token=newToken();await rpc('issue_management',{guardian_id:c.guardian_id,token_hash:await tokenHash(token)});
     links.push(origin+'/parent-browser.html#token='+token);
    }
    const text='You requested access to your Wrestling Manager parent permissions. Open a private link below to review or withdraw your approval. Links expire in one hour. Opening a link does not change permissions.\n\n'+links.join('\n\n')+'\n\nIf you did not request this, ignore this email. Keep these links private.';
    await deps.fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+mail,'Content-Type':'application/json'},body:JSON.stringify({from:'Wrestling Manager <messages@wrestlingmanager.app>',to:[contacts[0].email],subject:'Manage your athlete’s profile permission',text,html:'<p>'+escape(text).replace(/\n/g,'<br>')+'</p>'}),signal:AbortSignal.timeout(20000)});
   }catch{/* Never reveal whether an email, athlete or permission exists. */}
   return json(200,answer);
  }
  if(typeof b.token!=='string'||!/^[a-f0-9]{64}$/.test(b.token))return json(400,{error:'Open the newest private link from your email.'});
  const data:{token_hash:string;acknowledge?:boolean;notice_version?:string;review_photos?:boolean}={token_hash:await tokenHash(b.token)};
  if(b.action==='approve'||b.action==='revoke'){
   if(b.acknowledge!==true||b.notice_version!=='teen-profile-v1'||(b.action==='approve'&&typeof b.review_photos!=='boolean'))return json(400,{error:'Review the choices and confirm you are the parent or legal guardian.'});
   data.acknowledge=true;data.notice_version='teen-profile-v1';if(b.action==='approve')data.review_photos=b.review_photos;
  }
  const result=await rpc(b.action,data);
  if(b.action!=='join')return json(200,result);
  // Auth is created only after the recipient explicitly chooses to join.
  if(!/^\S+@\S+\.\S+$/.test(result?.email))throw Error('unavailable');
  const generate=(type:string)=>post('/auth/v1/admin/generate_link',{type,email:result.email,...(type==='invite'?{data:{full_name:String(result.name||'').slice(0,120),wm_onboarding_role:'parent_guardian'}}:{})});
  let r=await generate('invite'),link=await r.json();
  if(!r.ok&&['email_exists','user_already_exists'].includes(link?.error_code||link?.code)){r=await generate('magiclink');link=await r.json();}
  if(!r.ok||!link.hashed_token||!['invite','magiclink','signup'].includes(link.verification_type))throw Error('unavailable');
  return json(200,{token_hash:link.hashed_token,type:link.verification_type,email:result.email});
 }catch{return json(409,{error:'This action could not be completed. Your link may be expired, replaced or temporarily unavailable. Ask your coach to resend it, or request a management link below. If you just tried joining, wait a minute before retrying.'});}
};}
