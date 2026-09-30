// Temporary hosted acceptance runner. It is gated by an expiring private DB
// capability and creates only tagged @tests.example.invalid synthetic identities.
import {createClient} from 'npm:@supabase/supabase-js@2.100.1';
import {hashSecret,providerAdapter} from '../../supabase/functions/scoped-deletion/handler.mjs';
import {runScopedDeletion} from '../../scripts/scoped-deletion-worker.mjs';
const url=Deno.env.get('SUPABASE_URL')!,serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const admin=createClient(url,serviceKey,options);
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
const ok=(condition:unknown,code:string)=>{if(!condition)throw Error(code);};
Deno.serve(async req=>{
 if(req.method!=='POST')return new Response('',{status:405});
 try{
  const body=await req.json();if(!/^[a-f0-9-]{36}$/.test(body.runId)||!/^[a-f0-9]{64}$/.test(body.token))throw Error('invalid_capability');
  const hash=await hashSecret(body.token);
  const rpc=async(action:string,data:unknown={})=>{
   const result=await admin.rpc('scoped_deletion_acceptance',{p_action:action,p_run:body.runId,p_hash:hash,p_data:data});
   if(result.error)throw Error('rpc_'+action+':'+result.error.message);return result.data;
  };
  if(body.action==='cleanup'){
   const clean=async(action:string)=>{const {data,error}=await admin.rpc('scoped_deletion_acceptance_cleanup',{p_action:action,p_run:body.runId,p_hash:hash});if(error)throw Error('cleanup_'+action+':'+error.message);return data;};
   const fixture=await clean('context');
   EdgeRuntime.waitUntil((async()=>{
    try{
     const provider=providerAdapter(admin);
     await provider.removeObject(fixture.bucket,fixture.path);ok(!await provider.objectExists(fixture.bucket,fixture.path),'fixture_file_remains');
     await clean('records');
     for(const id of [fixture.retained,fixture.child]){await provider.deleteIdentity(id);ok(!await provider.identityExists(id),'fixture_auth_remains');}
     await clean('complete');
    }catch(error){await rpc('failed',{code:String(error?.message||'cleanup_failed').slice(0,180)}).catch(()=>{});}
   })());
   return Response.json({accepted:true},{status:202});
  }
  if(body.action==='resume'){
   const {data:fixture,error}=await admin.rpc('scoped_deletion_acceptance_inspect',{p_run:body.runId,p_hash:hash});
   ok(!error&&fixture?.jobId,'resume_not_authorized');
   EdgeRuntime.waitUntil((async()=>{
    let phase='resume';
    try{
     const service=async(op:string,job:string,lease:string,input:unknown)=>{
      const {data,error}=await admin.rpc('scoped_deletion_service',{p_op:op,p_job:job,p_lease:lease,p_input:input});
      if(error)throw Error('service_'+op+':'+error.message);return data;
     };
     const provider=providerAdapter(admin);
     const result=await runScopedDeletion({service,provider,jobId:fixture.jobId,receiptHash:fixture.receiptHash,budgetMs:90000});
     if(result.state!=='completed'){
      // Only synthetic file errors are persisted, without paths or credentials.
      for(const file of fixture.files.filter((x:any)=>x.remove)){
       const check=await admin.storage.from(file.bucket).exists(file.path);
       if(check.error)throw Error('exists_'+file.bucket+':'+JSON.stringify({status:check.error.status,name:check.error.name,originalStatus:check.error.originalError?.status,data:check.data}));
      }
      throw Error('worker_'+result.state+':'+result.code);
     }
     phase='provider_verify';ok(!await provider.identityExists(fixture.actor),'auth_still_present');
     for(const id of [fixture.retained,fixture.child])ok(await provider.identityExists(id),'other_auth_missing');
     for(const file of fixture.files)ok(await provider.objectExists(file.bucket,file.path)===!file.remove,'storage_verification_failed');
     phase='database_verify';await rpc('verify',{provider_auth:true,provider_files:true,completed_receipt:true});
    }catch(error){await rpc('failed',{code:phase+':'+String(error?.message||'unknown').slice(0,180)}).catch(()=>{});}
   })());
   return Response.json({accepted:true},{status:202});
  }
  await rpc('authorize');
  EdgeRuntime.waitUntil((async()=>{
   let phase='create_users';
   try{
    const people=[];
    for(const suffix of ['actor','retained','child']){
     const email='scoped-'+body.runId+'-'+suffix+'@tests.example.invalid',password=random();
     const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,app_metadata:{scoped_deletion_acceptance:body.runId},user_metadata:{full_name:'Synthetic deletion acceptance'}});
     ok(!error&&data?.user?.id,'auth_create_failed');people.push({id:data.user!.id,email,password});
    }
    const [actor,retained,child]=people;
    phase='seed';const fixture=await rpc('seed',{actor:actor.id,retained:retained.id,child:child.id});
    phase='sign_in';const userClient=createClient(url,anon,options);
    const signed=await userClient.auth.signInWithPassword({email:actor.email,password:actor.password});
    ok(!signed.error&&signed.data.session?.user.id===actor.id,'auth_sign_in_failed');
    const token=signed.data.session!.access_token;
    phase='upload';
    for(const file of fixture.files){
     const owner=file.bucket==='profile-photos'&&file.path.startsWith(actor.id+'/')?userClient:admin;
     const uploaded=await owner.storage.from(file.bucket).upload(file.path,new Uint8Array([255,216,255,217]),{contentType:'image/jpeg',upsert:false});
     ok(!uploaded.error,'storage_upload_failed:'+file.bucket);
    }
    const requestId=crypto.randomUUID(),receipt=random();
    const invoke=async(data:unknown)=>{
     const response=await fetch(url+'/functions/v1/scoped-deletion',{method:'POST',headers:{apikey:anon,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(data)});
     const result=await response.json();ok(response.ok,'worker_http_'+response.status+':'+result.error);return result;
    };
    phase='begin';const began=await invoke({action:'begin',kind:'all',teamIds:[fixture.team],organizationIds:[fixture.organization],requestId,receipt,confirmation:'delete'});
    ok(!!began.id,'missing_job');await rpc('job',{id:began.id});
    phase='worker';let result;
    for(let i=0;i<20;i++){
     result=await invoke({action:'recover',requestId,receipt});
     if(result.state==='completed')break;
     ok(result.state!=='blocked','worker_blocked:'+result.code);
     await new Promise(resolve=>setTimeout(resolve,5000));
    }
    ok(result?.state==='completed','worker_pending');
    phase='provider_verify';
    const gone=await admin.auth.admin.getUserById(actor.id);ok(gone.error?.status===404&&gone.error?.code==='user_not_found','auth_still_present');
    for(const person of [retained,child]){const present=await admin.auth.admin.getUserById(person.id);ok(!present.error&&present.data.user?.id===person.id,'other_auth_missing');}
    for(const file of fixture.files)ok(await providerAdapter(admin).objectExists(file.bucket,file.path)===!file.remove,'storage_verification_failed');
    const stale=await fetch(url+'/rest/v1/profiles?select=id&limit=1',{headers:{apikey:anon,Authorization:'Bearer '+token}});ok(stale.status===401||stale.status===403,'stale_jwt_still_accepted');
    phase='database_verify';await rpc('verify',{provider_auth:true,provider_files:true,old_jwt_rejected:true,completed_receipt:true});
   }catch(error){
    const code=phase+':'+String(error?.message||'unknown').slice(0,180);
    await rpc('failed',{code}).catch(()=>{});
   }
  })());
  return Response.json({accepted:true},{status:202});
 }catch{return Response.json({error:'not_authorized'},{status:403});}
});
