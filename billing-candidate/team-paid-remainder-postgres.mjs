import {reconcileTeamPaidRemainder} from './team-paid-remainder.mjs';
// Receives only the Apple adapter's canonical verified evidence. The caller must
// verify the signature and refresh status first. This is never a public route.
export async function reconcileTeamRemainderTransaction(tx,evidence,{config,now}) {
  if(evidence?.environment!==config.environment||!/^\d{1,40}$/.test(evidence?.originalTransactionID)||
   typeof evidence?.appAccountToken!=='string'||! /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(evidence.appAccountToken))throw Error('Invalid remainder binding');
   const row=(await tx.query(`select binding_hash,team_id,environment,plan,paid_through,revoked_at,snapshot_signed_at
    from wm_billing.team_paid_remainders where binding_hash=wm_billing.remainder_binding($1,$2,$3::uuid) for update`,
    [evidence.environment,evidence.originalTransactionID,evidence.appAccountToken])).rows[0];
   if(!row)return {status:'unknown'};
   const existing={teamID:row.team_id,environment:row.environment,plan:row.plan,paidThrough:Number(row.paid_through),
    revokedAt:row.revoked_at===null?null:Number(row.revoked_at),snapshotSignedAt:Number(row.snapshot_signed_at)};
   const updated=reconcileTeamPaidRemainder(existing,evidence,{config,now});
   await tx.query(`update wm_billing.team_paid_remainders set paid_through=$2,revoked_at=$3,snapshot_signed_at=$4 where binding_hash=$1`,
    [row.binding_hash,updated.paidThrough,updated.revokedAt,updated.snapshotSignedAt]);
   return {status:'reconciled'};
}
export function createTeamRemainderReconciler({db,config,clock=Date.now}) {
 if(typeof db?.transaction!=='function'||!['Sandbox','Production'].includes(config?.environment))throw Error('Invalid remainder configuration');
 return evidence=>db.transaction(tx=>reconcileTeamRemainderTransaction(tx,evidence,{config,now:clock()}));
}
