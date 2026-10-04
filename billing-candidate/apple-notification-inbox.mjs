// Parameterized private DB port; query must resolve only after statement commit.
export function createAppleNotificationInbox({db,environment}){
 if(typeof db?.query!=='function'||!['Production','Sandbox'].includes(environment))throw Error('Invalid inbox configuration');
 return async ({notificationID,evidence})=>{
  if(evidence?.environment!==environment)throw Error('Notification environment mismatch');
  // Conflicts never rebind an event or overwrite its first canonical observation.
  // Canonical status may advance between Apple retries; a worker rechecks Apple
  // before applying access. No auth user/intent is created from a notification.
  const inserted=await db.query(`insert into wm_billing.notification_inbox
   (environment,notification_id,original_id,token,evidence) values($1,$2::uuid,$3,$4::uuid,$5::jsonb)
   on conflict(environment,notification_id) do nothing returning notification_id`,
   [environment,notificationID,evidence.originalTransactionID,evidence.appAccountToken,JSON.stringify(evidence)]);
  if(inserted.rows.length===1)return {notificationID,status:'stored'};
  const existing=(await db.query(`select original_id,token from wm_billing.notification_inbox
   where environment=$1 and notification_id=$2::uuid`,[environment,notificationID])).rows[0];
  if(!existing||existing.original_id!==evidence.originalTransactionID||existing.token.toLowerCase()!==evidence.appAccountToken.toLowerCase())throw Error('Notification binding conflict');
  return {notificationID,status:'duplicate'};
 };
}
