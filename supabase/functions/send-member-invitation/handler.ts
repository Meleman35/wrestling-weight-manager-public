// Authentication link and team invitation are delivered together, once.
// The inviter never receives the recipient's sign-in token or code.
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const escape=(v:unknown)=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
type Dependencies={env:(name:string)=>string|undefined;fetch:typeof fetch};
export function createHandler(deps:Dependencies){return async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return json(405,{error:'Method not allowed.'});
 const auth=req.headers.get('Authorization')||'';if(!/^Bearer \S+$/.test(auth))return json(401,{error:'Sign in to send an invitation.'});
 const url=deps.env('SUPABASE_URL'),key=deps.env('SUPABASE_ANON_KEY'),service=deps.env('SUPABASE_SERVICE_ROLE_KEY'),mail=deps.env('RESEND_API_KEY');
 if(!url||!key||!service||!mail)return json(503,{error:'Invitation email is not configured. Please contact your app administrator.'});
 try{
  const raw=await req.text();if(raw.length>2000)return json(400,{error:'Invalid invitation.'});
  const b=JSON.parse(raw);if(!/^WMW[AG]-[a-f0-9]{48}$/.test(b?.token)||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(b?.request_id))return json(400,{error:'Invalid invitation.'});
  const checked=await deps.fetch(url+'/rest/v1/rpc/invitation_email_context',{method:'POST',headers:{apikey:key,Authorization:auth,'Content-Type':'application/json'},body:JSON.stringify({p_token:b.token,p_request_id:b.request_id}),signal:AbortSignal.timeout(15000)});
  if(!checked.ok)return json(checked.status===401?401:403,{error:'Invitation email was not authorized or was just submitted. Check the invitation and wait a minute before retrying.'});
  const context=await checked.json();if(!context?.id||context.request_id!==b.request_id||!/^\S+@\S+\.\S+$/.test(context.email)||!['athlete','parent_guardian'].includes(context.role))return json(502,{error:'Could not verify the invitation recipient.'});
  const generate=async(type:string)=>deps.fetch(url+'/auth/v1/admin/generate_link',{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({type,email:context.email,...(type==='invite'?{data:{full_name:String(context.name||'').slice(0,120),wm_onboarding_role:context.role}}:{})}),signal:AbortSignal.timeout(15000)});
  let response=await generate('invite'),link=await response.json();
  if(!response.ok&&['email_exists','user_already_exists'].includes(link?.error_code||link?.code)){response=await generate('magiclink');link=await response.json();}
  if(!response.ok||!link.hashed_token||!/^\d{6,10}$/.test(link.email_otp)||!['invite','magiclink','signup'].includes(link.verification_type))return json(502,{error:'Could not prepare the secure invitation. Wait a minute and retry.'});
  const href=new URL('https://theteammanager.app/invite-signin.html');href.hash=new URLSearchParams({token_hash:link.hashed_token,type:link.verification_type,invite:b.token,email:context.email}).toString();
  const team=String(context.team_name||'Your team').replace(/[\r\n]/g,' ').slice(0,120);
  const text=`You’re invited to ${team}.\n\nOpen this link and tap Confirm & join team: ${href}\n\nThis one step confirms your email and signs you in. There is no second confirmation email and no password to create now.\n\nPrefer using the installed app? Choose Use an email code on Personal Login, enter ${context.email}, then enter this one-time code: ${link.email_otp}\n\nYour team invitation will be available after sign-in. If the code has expired, ask your coach to resend this invitation. Keep this email private; the link and code sign in to your account.`;
  const sent=await deps.fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+mail,'Content-Type':'application/json','Idempotency-Key':'member-invitation/'+context.id+'/'+b.request_id},body:JSON.stringify({from:'Wrestling Manager <messages@wrestlingmanager.app>',to:[context.email],subject:team+' — confirm & join your team',text,html:'<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;line-height:1.5"><h2>'+escape(team)+'</h2><p>One email. Confirm your email address and join your team.</p><p><a href="'+escape(href.toString())+'" style="display:inline-block;background:#143f85;color:white;padding:14px;border-radius:10px;text-decoration:none">Confirm &amp; join team</a></p><p>Or choose <b>Use an email code</b> in the app and enter:</p><p style="font-size:28px;font-weight:bold;letter-spacing:4px">'+escape(link.email_otp)+'</p><p>Use '+escape(context.email)+'. No second confirmation email or new password is needed.</p><p>Keep this email private. If the link or code expires, ask your coach to resend your invitation.</p></div>'}),signal:AbortSignal.timeout(20000)});
  const result=await sent.json().catch(()=>null);if(!sent.ok||typeof result?.id!=='string')return json(502,{error:'Email delivery was not confirmed. Wait a minute before retrying.'});
  return json(200,{ok:true,sent:1,id:result.id});
 }catch{return json(502,{error:'Email delivery was not confirmed. Wait a minute before retrying.'});}
};}
