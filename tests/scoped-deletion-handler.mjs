import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createDeletionHandler,providerAdapter,hashSecret} from '../supabase/functions/scoped-deletion/handler.mjs';
const receipt='c'.repeat(64),requestId=randomUUID(),job=randomUUID(),user=randomUUID();
let authenticated=false,begun=0,privileged=0,background=[];
const admin={rpc:async(name,args)=>{
 privileged++;assert.equal(name,'scoped_deletion_service');
 if(args.p_input.receipt_hash!==await hashSecret(receipt))return {error:{message:'DELETION_RECEIPT_REQUIRED'}};
 if(args.p_op==='resolve')return {data:{id:job,state:'completed'}};
 assert.equal(args.p_op,'claim');assert.equal(args.p_job,job);return {data:{id:job,state:'completed',personal:true}};
}};
const caller=()=>({auth:{getUser:async()=>authenticated?{data:{user:{id:user}}}:{error:Error('invalid token')}},rpc:async(name,args)=>{
 begun++;assert.equal(name,'scoped_deletion_begin');assert.equal(args.p_receipt_hash,await hashSecret(receipt));assert.equal(args.p_confirmation,'delete');
 return {data:{id:job,state:'planning'}};
}});
const handler=createDeletionHandler({admin,caller,waitUntil:p=>background.push(p)});
const request=body=>new Request('https://example.invalid/scoped-deletion',{method:'POST',headers:{Origin:'https://theteammanager.app',Authorization:'Bearer synthetic-fixture'},body:JSON.stringify(body)});
const body={action:'begin',receipt,requestId,kind:'personal',teamIds:[],organizationIds:[],confirmation:'delete'};
assert.equal((await handler(request(body))).status,401);assert.equal(begun,0);assert.equal(privileged,0);
authenticated=true;
assert.equal((await handler(request({...body,confirmation:'DELETE'}))).status,400);assert.equal(begun,0);
assert.equal((await handler(request(body))).status,202);await Promise.all(background);assert.equal(begun,1);
assert.equal((await handler(request({action:'resume',id:job,receipt:'d'.repeat(64)}))).status,503);
const result=await handler(request({action:'recover',requestId,receipt}));assert.equal(result.status,200);assert.equal((await result.json()).id,job);
assert.equal((await handler(new Request('https://example.invalid',{method:'POST',headers:{Origin:'https://untrusted.invalid'},body:JSON.stringify(body)}))).status,403);
assert.equal((await handler(request({...body,padding:'x'.repeat(9000)}))).status,413);
let deleted=[],files=[];
const sdk={auth:{admin:{
 updateUserById:async(id,data)=>{assert.equal(id,user);assert.equal(data.ban_duration,'876000h');return {};},
 getUserById:async()=>({error:{status:403,code:'not_authorized'}}),
 deleteUser:async(id,soft)=>{deleted.push(id);assert.equal(soft,false);return {};}
}},storage:{from:bucket=>({remove:async paths=>{files.push([bucket,paths]);return {};},exists:async()=>({error:{status:403}})})}};
const provider=providerAdapter(sdk);
await assert.rejects(()=>provider.identityExists(user));await assert.rejects(()=>provider.objectExists('profile-photos','one.jpg'));
sdk.auth.admin.getUserById=async()=>({error:{status:404,code:'user_not_found'}});assert.equal(await provider.identityExists(user),false);
sdk.storage.from=bucket=>({remove:async paths=>{files.push([bucket,paths]);return {};},exists:async()=>({data:false})});
await provider.deleteIdentity(user);await provider.removeObject('profile-photos','one.jpg');assert.equal(await provider.objectExists('profile-photos','one.jpg'),false);
assert.deepEqual(deleted,[user]);assert.deepEqual(files,[['profile-photos',['one.jpg']]]);
console.log('PASS Edge authentication, exact consent, receipt recovery, bounded requests, origin checks, exact provider targets and 403-is-not-absence');
