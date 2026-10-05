// Private worker only. Scheduler authentication belongs to the runtime host.
export function createAppleNotificationWorker({apple,inbox,repository,config,clock=Date.now}) {
 if(![apple?.refresh,inbox?.claim,inbox?.release,repository?.applyKnown].every(f=>typeof f==='function'))throw Error('Trusted worker dependencies required');
 return async ()=>{
  const lease=await inbox.claim();if(!lease)return {status:'idle'};
  try{
   // Requery Apple; a notification's old status/type never drives entitlement.
   const current=await apple.refresh(lease.evidence);
   const result=await repository.applyKnown({lease,evidence:current,config,now:clock()});
   if(!['updated','unchanged','owner_unavailable'].includes(result?.status))throw Error('Unconfirmed reconciliation');
   return {status:result.status};
  }catch{
   await inbox.release(lease).catch(()=>{});
   return {status:'retry'};
  }
 };
}
