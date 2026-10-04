import {hasTeamSubscriptionAccess} from './subscription-policy.mjs';
const millis=x=>Number.isSafeInteger(x)&&x>=0;
// Server-resolved admin permission and verified stored purchase only.
// No user ID, app-account token, athlete link or receipt survives in this value.
export function createTeamPaidRemainder(subscription,{remainingAdmin,now}){
 if(remainingAdmin!==true||!hasTeamSubscriptionAccess(subscription,{teamID:subscription?.teamID,environment:subscription?.environment,now}))return null;
 const paidThrough=subscription.status===4?subscription.graceExpiresAt:subscription.expiresAt;
 return Object.freeze({teamID:subscription.teamID,environment:subscription.environment,plan:subscription.plan,
  paidThrough,revokedAt:null,snapshotSignedAt:subscription.snapshotSignedAt});
}
export function hasTeamPaidRemainderAccess(remainder,{teamID,environment,remainingAdmin,now}){
 return remainingAdmin===true&&!!remainder&&remainder.teamID===teamID&&remainder.environment===environment&&
  ['team_pro_year','team_pro_month'].includes(remainder.plan)&&millis(now)&&millis(remainder.paidThrough)&&
  remainder.paidThrough>now&&remainder.revokedAt===null;
}
// A later verified refund may shorten/revoke the preserved period. Renewals
// cannot extend it or transfer this grant to another team or a family plan.
export function reconcileTeamPaidRemainder(remainder,evidence,{config,now}){
 if(!remainder||!config||evidence?.environment!==remainder.environment||config.environment!==remainder.environment||
   evidence.bundleID!==config.bundleID||!Object.hasOwn(config.products,evidence.productID)||
   !['team_pro_year','team_pro_month'].includes(config.products[evidence.productID])||
   !millis(now)||!millis(evidence.snapshotSignedAt)||evidence.snapshotSignedAt>now+60000||
   !millis(evidence.expiresAt)||![1,2,3,4,5].includes(evidence.status)||
   (evidence.revokedAt!=null&&!millis(evidence.revokedAt))||
   (evidence.status===4&&!millis(evidence.graceExpiresAt)))throw Error('Invalid team remainder evidence');
 if(evidence.snapshotSignedAt<remainder.snapshotSignedAt)return {...remainder};
 const revoked=evidence.revokedAt??(evidence.status===5?now:remainder.revokedAt);
 const boundary=evidence.status===4?evidence.graceExpiresAt:evidence.expiresAt;
 return {...remainder,paidThrough:Math.min(remainder.paidThrough,boundary),
  revokedAt:revoked,snapshotSignedAt:evidence.snapshotSignedAt};
}
