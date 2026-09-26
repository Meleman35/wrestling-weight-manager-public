// Fixed invitation email only. Caller JWT is verified by PostgREST; no service key.
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const escape=(v:unknown)=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!));
type Dependencies={env:(name:string)=>string|undefined;fetch:typeof fetch};
export function createHandler(deps:Dependencies){return async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return json(405,{error:'Method not allowed.'});
 const auth=req.headers.get('Authorization')||'';
 if(!/^Bearer \S+$/.test(auth))return json(401,{error:'Sign in to send an invitation.'});
 const url=deps.env('SUPABASE_URL'),key=deps.env('SUPABASE_ANON_KEY'),emailKey=deps.env('RESEND_API_KEY');
 if(!url||!key||!emailKey)return json(503,{error:'Organization invitation email is not configured. Copy the invitation link instead.'});
 try{
  const raw=await req.text();if(raw.length>2048)return json(400,{error:'Invalid invitation request.'});
  const b=JSON.parse(raw),uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if(!b||!uuid.test(b.organization_id)||!uuid.test(b.id)||!uuid.test(b.request_id)||!/^WMO-[0-9a-f]{64}$/.test(b.token))return json(400,{error:'Invalid invitation request.'});
  const checked=await deps.fetch(url+'/rest/v1/rpc/organization_leadership_invites',{method:'POST',headers:{apikey:key,Authorization:auth,'Content-Type':'application/json'},body:JSON.stringify({p_request:{action:'email_context',organization_id:b.organization_id,id:b.id,token:b.token,request_id:b.request_id}}),signal:AbortSignal.timeout(15000)});
  if(!checked.ok)return json(checked.status===401?401:403,{error:'Invitation email was not authorized. Check your access, invitation status, or wait a minute before retrying.'});
  const data=await checked.json();
  if(data.id!==b.id||data.request_id!==b.request_id||typeof data.email!=='string'||!data.access)return json(502,{error:'Invitation details could not be verified.'});
  const link=new URL('https://meleman35.github.io/wrestling-weight-manager-public/join.html');link.searchParams.set('invite',b.token);
  const organization=String(data.organization_name||'Your organization'),title=String(data.access.title||'Organization leadership');
  const access=data.access.access_role==='organization_admin'?'Full organization administration, including administration of its managed teams.':data.access.access_role==='organization_member'?'Organization membership; no board position, voting right or team access.':String(data.access.access_role||'Title only').replaceAll('_',' ');
  const text=`You are invited to join ${organization} as ${title}.\n\nScope: ${data.access.scope||'Organization'}\nAccess: ${access}\n\nOpen your private invitation: ${link}\n\nSign in or create your own personal account using ${data.email}. Confirm your email, then review and accept the invitation. You do not need to join a team.\n\nExpires: ${data.expires_at}. Do not forward this private link. Check Junk or Spam if you are waiting for an account confirmation email.`;
  const sent=await deps.fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+emailKey,'Content-Type':'application/json','Idempotency-Key':'organization-invitation/'+b.id+'/'+b.request_id},body:JSON.stringify({from:'Wrestling Manager <messages@wrestlingmanager.app>',to:[data.email],subject:organization.replace(/[\r\n]/g,' ').slice(0,120)+' — organization invitation',text,html:'<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;line-height:1.5"><h2>Organization invitation</h2><p>'+escape(text).replace(/\n/g,'<br>')+'</p><p><a href="'+escape(link.toString())+'">Review organization invitation</a></p></div>'}),signal:AbortSignal.timeout(20000)});
  const result=await sent.json().catch(()=>null);
  if(!sent.ok||typeof result?.id!=='string')return json(502,{error:'Email submission was not confirmed. Retry this invitation or copy its link.'});
  return json(200,{ok:true,sent:1,id:result.id});
 }catch{return json(502,{error:'Email submission was not confirmed. Retry this invitation or copy its link.'});}
};}
