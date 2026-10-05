import {createAppleNotificationInbox} from './apple-notification-inbox.mjs';
import {reconcileTeamRemainderTransaction} from './team-paid-remainder-postgres.mjs';
// The notification adapter already resolves Apple's current canonical status.
// A deleted purchaser's known grant is reconciled before acknowledging Apple,
// without recreating a receipt, user binding or raw-token inbox entry.
export function createBillingNotificationPersistence({db,config,clock=Date.now}) {
 if(typeof db?.transaction!=='function')throw Error('Transactional notification persistence required');
 return async notification=>db.transaction(async tx=>{
  const e=notification.evidence;
  const owners=(await tx.query(`select user_id from wm_billing.intents where token=$1::uuid
   union select user_id from wm_billing.subscriptions where environment=$2 and original_id=$3`,
   [e.appAccountToken,config.environment,e.originalTransactionID])).rows;
  if(owners.length>1)throw Error('Notification binding conflict');
  if(owners[0])await tx.query('select pg_advisory_xact_lock(hashtextextended($1,91347))',[owners[0].user_id]);
  for(const lock of ['original:'+config.environment+':'+e.originalTransactionID,'token:'+e.appAccountToken.toLowerCase()].sort())
   await tx.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[lock]);
  const preserved=await reconcileTeamRemainderTransaction(tx,e,{config,now:clock()});
  if(preserved.status==='reconciled')return {notificationID:notification.notificationID,status:'stored'};
  if(owners[0]&&(await tx.query('select wm_billing.notification_owner_available($1::uuid) as allowed',[owners[0].user_id])).rows[0]?.allowed!==true)
   throw Error('Owner unavailable');
  return createAppleNotificationInbox({db:tx,environment:config.environment})(notification);
 });
}
