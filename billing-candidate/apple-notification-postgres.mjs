import {randomUUID} from 'node:crypto';
import {reconcileKnownSubscription} from './subscription-policy.mjs';
// query commits standalone statements; transaction commits only after callback.
// Dedicated private runtime credentials and deletion-catalog integration required.
export function createAppleNotificationPostgres({db,environment}){
 if(typeof db?.query!=='function'||typeof db?.transaction!=='function'||!['Production','Sandbox'].includes(environment))throw Error('Invalid worker database configuration');
 const inbox={
  async claim(){
   const token=randomUUID();
   const row=(await db.query(`with candidate as (
    select notification_id from wm_billing.notification_inbox where environment=$1
     and ((state='pending' and next_attempt_at<=clock_timestamp()) or (state='processing' and lease_until<=clock_timestamp()))
    order by received_at,notification_id for update skip locked limit 1)
    update wm_billing.notification_inbox i set state='processing',lease_token=$2::uuid,
     lease_until=clock_timestamp()+interval '2 minutes',attempts=attempts+1
    from candidate c where i.environment=$1 and i.notification_id=c.notification_id
    returning i.notification_id,i.evidence`,[environment,token])).rows[0];
   return row?{notificationID:row.notification_id,token,evidence:row.evidence}:null;
  },
  async release(lease){await db.query(`update wm_billing.notification_inbox set state='pending',
   lease_token=null,lease_until=null,next_attempt_at=clock_timestamp()+interval '1 minute'
   where environment=$1 and notification_id=$2::uuid and lease_token=$3::uuid and state='processing'`,[environment,lease.notificationID,lease.token]);}
 };
 const repository={async applyKnown({lease,evidence,config,now}){
  if(evidence.environment!==environment||config.environment!==environment||
    evidence.originalTransactionID!==lease.evidence.originalTransactionID||
    evidence.appAccountToken.toLowerCase()!==lease.evidence.appAccountToken.toLowerCase())throw Error('Binding mismatch');
  return db.transaction(async tx=>{
   const key=[environment,evidence.originalTransactionID];
   const initial=(await tx.query('select snapshot from wm_billing.subscriptions where environment=$1 and original_id=$2',key)).rows[0]?.snapshot;
   if(!initial)throw Error('Purchase binding not yet delivered');
   // Same lock order as deletion/access: actor first, then sorted billing keys,
   // then auth/subscription/inbox rows. No fake logged-in actor is constructed.
   await tx.query('select pg_advisory_xact_lock(hashtextextended($1,91347))',[initial.userID]);
   for(const lock of ['original:'+environment+':'+evidence.originalTransactionID,'token:'+evidence.appAccountToken.toLowerCase()].sort())await tx.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[lock]);
   const row=(await tx.query(`select evidence from wm_billing.notification_inbox where environment=$1 and notification_id=$2::uuid
    and state='processing' and lease_token=$3::uuid and lease_until>clock_timestamp() for update`,[environment,lease.notificationID,lease.token])).rows[0];
   if(!row)throw Error('Lease unavailable');
   const existing=(await tx.query('select snapshot from wm_billing.subscriptions where environment=$1 and original_id=$2 for update',key)).rows[0]?.snapshot;
   if(!existing||existing.userID!==initial.userID)throw Error('Binding changed');
   const owner=(await tx.query(`select u.id from auth.users u where u.id=$1::uuid
    and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp())
    and private.board_personal(u.id) and not exists(select 1 from private.scoped_deletion_jobs j
      where (j.actor_id=u.id and j.state not in ('cancelled','completed')) or
       (j.personal and j.sealed_at is not null and j.subject_hash=encode(sha256(convert_to(u.id::text,'UTF8')),'hex')))
    for share`,[existing.userID])).rows[0];
   // Frozen/banned owners may become available again; retain the job for retry.
   if(!owner)throw Error('Owner unavailable');
   const decision=reconcileKnownSubscription({existing,evidence,config,now});
   if(decision.changed)await tx.query('update wm_billing.subscriptions set snapshot=$3::jsonb where environment=$1 and original_id=$2',[...key,JSON.stringify(decision.subscription)]);
   const completed=await tx.query(`update wm_billing.notification_inbox set state='completed',lease_token=null,lease_until=null
    where environment=$1 and notification_id=$2::uuid and lease_token=$3::uuid and lease_until>clock_timestamp() returning notification_id`,[environment,lease.notificationID,lease.token]);
   if(completed.rows.length!==1)throw Error('Lease expired');
   return {status:decision.changed?'updated':'unchanged'};
  });
 }};
 return {inbox,repository};
}
