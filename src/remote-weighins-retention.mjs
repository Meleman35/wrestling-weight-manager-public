// Server-only scheduled worker. Photo purge revokes access and confirms removal.
export function createRemoteRetentionWorker({db,photos}) {
 if (![db?.query,db?.transaction,photos?.purge].every(f=>typeof f==='function')) throw Error('Trusted retention dependencies required');
 return Object.freeze({async run({limit=100}={}) {
  if(!Number.isInteger(limit)||limit<1||limit>500)throw Error('Invalid retention batch size');
  const expired=(await db.query(`select id from remote_reporting.evidence
   where expires_at<=clock_timestamp() order by expires_at,id limit $1`,[limit])).rows;
  let removed=0;const failed=[];
  for(const {id} of expired){
   try {
    await photos.purge(id);
    const deleted=await db.transaction(async tx=>{
     const row=(await tx.query(`select id from remote_reporting.evidence where id=$1
      and revoked and expires_at<=clock_timestamp() for update`,[id])).rows[0];
     if(!row)return false;
     await tx.query('delete from remote_reporting.submissions where evidence_id=$1',[id]);
     await tx.query('delete from remote_reporting.evidence where id=$1',[id]);
     return true;
    });
    if(deleted)removed++;
   }catch{failed.push(id);}
  }
  return {removed,failed};
 }});
}
