import {runScopedDeletion} from '../../../scripts/scoped-deletion-worker.mjs';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const secret=/^[a-f0-9]{64}$/;
export const hashSecret=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),x=>x.toString(16).padStart(2,'0')).join('');
export function providerAdapter(admin){
 const unavailable=()=>Error('provider_unavailable');
 const absent=error=>error?.status===404&&error?.code==='user_not_found';
 return {
  async disableIdentity(id){const {error}=await admin.auth.admin.updateUserById(id,{ban_duration:'876000h'});if(error)throw unavailable();},
  async identityExists(id){const {data,error}=await admin.auth.admin.getUserById(id);if(absent(error))return false;if(error||data?.user?.id!==id)throw unavailable();return true;},
  async deleteIdentity(id){const {error}=await admin.auth.admin.deleteUser(id,false);if(error&&!absent(error))throw unavailable();},
  async removeObject(bucket,path){const {error}=await admin.storage.from(bucket).remove([path]);if(error)throw unavailable();},
  async objectExists(bucket,path){
   const storage=admin.storage.from(bucket),{data,error}=await storage.exists(path);
   const status=error?.status??error?.originalError?.status;
   if(data===false&&status===404)return false;
   if(data===false&&status===400){
    // This SDK returns a 400 error alongside false for a missing HEAD request.
    // Confirm the explicit object-not-found response with GET metadata; generic
    // bad requests, permission failures and timeouts never establish absence.
    const detail=await storage.info(path);
    if(!detail.error&&detail.data)return true;
    if(detail.error?.status===404||(detail.error?.status===400&&detail.error?.message==='Object not found'))return false;
   }
   if(error||typeof data!=='boolean')throw unavailable();return data;
  }
 };
}
export function createDeletionHandler({admin,caller,waitUntil=()=>{},allowedOrigins=['https://theteammanager.app','https://www.theteammanager.app']}){
 const provider=providerAdapter(admin);
 const service=async(op,job,lease,input)=>{
  const {data,error}=await admin.rpc('scoped_deletion_service',{p_op:op,p_job:job,p_lease:lease,p_input:input});
  if(error){
   const e=Error('service_unavailable');
   const terminal=['UNREVIEWED_FILE_REFERENCE','AMBIGUOUS_FILE_REFERENCE','UNREVIEWED_UPLOADED_FILE','SHARED_FILE_REFERENCE','UNREVIEWED_IDENTITY_COPY'];
   const found=terminal.find(code=>error.message==='DELETION_'+code);if(found)e.code=found.toLowerCase();throw e;
  }return data;
 };
 return async request=>{
  const origin=request.headers.get('Origin');
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',
   ...(origin&&allowedOrigins.includes(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'}:{})};
  const response=(status,data)=>new Response(JSON.stringify(data),{status,headers});
  if(origin&&!allowedOrigins.includes(origin))return response(403,{error:'origin_not_allowed'});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return response(405,{error:'post_required'});
  try{
   const reader=request.body?.getReader();if(!reader)return response(400,{error:'invalid_request'});
   let text='',length=0;const decoder=new TextDecoder();
   while(true){const {value,done}=await reader.read();if(done)break;length+=value.length;if(length>8192){await reader.cancel();return response(413,{error:'request_too_large'});}text+=decoder.decode(value,{stream:true});}text+=decoder.decode();
   const body=JSON.parse(text);
   if(!secret.test(body.receipt))return response(400,{error:'invalid_request'});
   const receiptHash=await hashSecret(body.receipt);
   if(body.action==='schedule'){
    const jobs=await service('due',null,null,{scheduler_hash:receiptHash});
    if(!Array.isArray(jobs))throw Error('invalid_response');
    waitUntil((async()=>{for(const job of jobs)await runScopedDeletion({service,provider,jobId:job.id,receiptHash:job.receiptHash});})());
    return response(202,{accepted:true});
   }
   if(body.action==='begin'){
    const authorization=request.headers.get('Authorization')||'';
    if(!authorization.startsWith('Bearer '))return response(401,{error:'sign_in_required'});
    const userClient=caller(authorization);
    const {data:user,error:authError}=await userClient.auth.getUser();
    if(authError||!user?.user?.id)return response(401,{error:'sign_in_required'});
    if(!uuid.test(body.requestId)||!['personal','team','organization','all'].includes(body.kind)||body.confirmation!=='delete'
      ||!Array.isArray(body.teamIds)||!Array.isArray(body.organizationIds)||body.teamIds.length>100||body.organizationIds.length>100
      ||[...body.teamIds,...body.organizationIds].some(x=>!uuid.test(x)))return response(400,{error:'invalid_request'});
    const {data,error}=await userClient.rpc('scoped_deletion_begin',{p_kind:body.kind,p_team_ids:body.teamIds,p_organization_ids:body.organizationIds,p_confirmation:body.confirmation,p_request_id:body.requestId,p_receipt_hash:receiptHash});
    if(error){
     const codes={DELETION_NOT_ENABLED:'not_enabled',DELETION_ORGANIZATION_HANDOFF_REQUIRED:'organization_handoff_required',DELETION_TEAM_HANDOFF_REQUIRED:'team_handoff_required',DELETION_LINKED_TEAMS_NOT_SELECTED:'linked_teams_not_selected',DELETION_ALREADY_IN_PROGRESS:'already_in_progress'};
     return response(409,{error:codes[error.message]||'request_not_accepted'});
    }
    if(!uuid.test(data?.id))throw Error('invalid_response');
    waitUntil(runScopedDeletion({service,provider,jobId:data.id,receiptHash}));
    return response(202,{id:data.id,state:data.state});
   }
   if(body.action==='recover'&&uuid.test(body.requestId)){
    const job=await service('resolve',null,null,{request_id:body.requestId,receipt_hash:receiptHash});
    if(!uuid.test(job?.id))throw Error('invalid_response');
    const result=await runScopedDeletion({service,provider,jobId:job.id,receiptHash});
    return response(result.state==='completed'?200:202,result);
   }
   if(body.action==='resume'&&uuid.test(body.id)){
    // No JWT is needed after the requesting identity has been erased. This high
    // entropy capability can only resume or inspect its original sealed scope.
    const result=await runScopedDeletion({service,provider,jobId:body.id,receiptHash});
    return response(result.state==='completed'?200:202,result);
   }
   return response(400,{error:'invalid_request'});
  }catch{return response(503,{error:'result_unconfirmed'});}
 };
}
