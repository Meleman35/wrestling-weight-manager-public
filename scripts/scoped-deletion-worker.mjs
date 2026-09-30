// Provider calls are injected so the identical state machine runs in acceptance tests.
// A receipt is a capability for this immutable job, never permission for a new scope.
import {planDeletion} from './scoped-deletion-plan.mjs';
export async function runScopedDeletion({service,provider,jobId,receiptHash,budgetMs=45000,clock=()=>Date.now()}){
 const start=clock();
 const lease=await service('claim',jobId,null,{receipt_hash:receiptHash});
 if(!lease.lease)return lease;
 const call=(op,input={})=>service(op,jobId,lease.lease,input);
 let state=lease.state;
 try{
  while(clock()-start<budgetMs){
   if(state==='planning'){
    const context=await call('context');
    const reader={select:(table,predicates,limit)=>call('read',{table,predicates,limit}),
      identityMentions:(table,columns,actorId,limit)=>call('read',{table,mention:{columns,actorId},limit})};
    const plan=await planDeletion({scope:context.scope,catalog:context.catalog,reader,maxRows:context.maxRows});
    const media=await call('media_inventory',{records:plan.records.map(x=>({table:x.table,key:x.key,action:x.action}))});
    await call('seal',{version:plan.version,catalog_hash:context.catalogHash,
     records:plan.records.map(x=>({table:x.table,key:x.key,action:x.action,columns:x.columns,hash:x.row.__deletion_hash||'auth-root'})),
     observations:plan.observations.map(x=>({table:x.table,predicates:x.predicates,mention:x.identityMention,
      rows:x.rows.map(r=>({key:r.key,hash:r.row.__deletion_hash}))})),objects:media});
    state='sealed';
   }else if(state==='sealed'||state==='revoking'){
    const data=await call('revoke');
    // The DB/API gate already rejects this identity before a provider call begins.
    if(data.personal)await provider.disableIdentity(data.actorId);
    await call('advance',{from:'revoking',to:'media'});state='media';
   }else if(state==='media'){
    const objects=await call('objects');
    for(const object of objects){
     if(clock()-start>=budgetMs)return {id:jobId,state:'media',pending:true};
     await provider.removeObject(object.bucket,object.path);
     if(await provider.objectExists(object.bucket,object.path))throw Error('media_still_present');
     await call('object_removed',{id:object.id});
    }
    await call('advance',{from:'media',to:'records'});state='records';
   }else if(state==='records'){
    await call('erase_records');state='auth';
   }else if(state==='auth'){
    const data=await call('identity');
    if(data.personal){
     if(await provider.identityExists(data.actorId))await provider.deleteIdentity(data.actorId);
     if(await provider.identityExists(data.actorId))throw Error('identity_still_present');
    }
    await call('advance',{from:'auth',to:'verifying'});state='verifying';
   }else if(state==='verifying'){
    // Verification is performed by the service against records and object metadata;
    // it never trusts an evidence flag supplied by the browser or a provider mock.
    return await call('complete');
   }else return {id:jobId,state};
  }
  return {id:jobId,state,pending:true};
 }catch(error){
  // Full provider responses/row contents are never persisted in receipts or logs.
  const code=typeof error?.code==='string'&&/^[a-z_]{1,70}$/.test(error.code)?error.code:'retry_required';
  await call('failed',{code,terminal:code!=='retry_required'});
  return {id:jobId,state:code==='retry_required'?state:'blocked',pending:code==='retry_required',code};
 }finally{await call('release').catch(()=>{});}
}
