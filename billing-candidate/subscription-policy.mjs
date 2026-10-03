// Server-only policy candidate. Inputs must come from authenticated server
// session checks and Apple's signature verifier/status API, never request JSON.
// This module performs no signature verification or database writes itself.
export class BillingPolicyError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const reject = code => { throw new BillingPolicyError(code); };
const id = x => typeof x === 'string' && /^[0-9]{1,40}$/.test(x);
const uuid = x => typeof x === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const time = x => Number.isSafeInteger(x) && x >= 0;

export const proposedProducts = Object.freeze({
  'com.damonmele.wrestlingmanager.teampro.annual': 'team_pro_year',
  'com.damonmele.wrestlingmanager.teampro.monthly': 'team_pro_month',
  'com.damonmele.wrestlingmanager.familyvideo.annual': 'family_video_year',
  'com.damonmele.wrestlingmanager.familyvideo.monthly': 'family_video_month'
});
const scopeFor = plan => ['team_pro_year','team_pro_month'].includes(plan) ? 'team' :
  ['family_video_year','family_video_month'].includes(plan) ? 'family' : null;

// No team supplied during restore. The immutable original binding is used.
// The caller applies this result atomically while locking (environment, originalID)
// AND the appAccountToken intent, with corresponding unique constraints.
export function reconcileSubscription({actor, evidence, intent, existing, config, now}) {
  if (!time(now)) reject('invalid_clock');
  if (!actor || !uuid(actor.userID) || actor.liveSession !== true ||
      actor.confirmed !== true || actor.deleted === true || actor.banned === true ||
      actor.managedTeamLogin === true || actor.deletionFrozen === true) reject('unauthorized');
  if (!config || !['Sandbox', 'Production'].includes(config.environment) ||
      typeof config.bundleID !== 'string' || !config.products) reject('invalid_configuration');
  // A property called "verified" in client input is never evidence. The adapter
  // must call this only with output of Apple's verifier plus canonical status.
  const e = evidence;
  if (!e || e.bundleID !== config.bundleID || e.environment !== config.environment)
    reject('app_or_environment_mismatch');
  if (!Object.hasOwn(config.products, e.productID)) reject('unknown_product');
  const scope=scopeFor(config.products[e.productID]);
  if (!scope) reject('unknown_product');
  if (!id(e.transactionID) || !id(e.originalTransactionID) || !uuid(e.appAccountToken) ||
      !time(e.snapshotSignedAt) || e.snapshotSignedAt > now + 60_000 ||
      !time(e.expiresAt) || ![1, 2, 3, 4, 5].includes(e.status)) reject('invalid_evidence');
  if (e.revokedAt != null && !time(e.revokedAt)) reject('invalid_revocation');
  if (e.graceExpiresAt != null && !time(e.graceExpiresAt)) reject('invalid_grace');

  let binding;
  if (existing) {
    if (existing.environment !== e.environment || existing.originalTransactionID !== e.originalTransactionID)
      reject('binding_mismatch');
    if (existing.userID !== actor.userID) reject('different_owner');
    if (existing.appAccountToken.toLowerCase() !== e.appAccountToken.toLowerCase())
      reject('token_mismatch');
    if (scopeFor(existing.plan)!==scope) reject('scope_mismatch');
    if (scope==='team' ? !uuid(existing.teamID) || existing.familyOwnerID != null :
        existing.teamID != null || existing.familyOwnerID !== actor.userID) reject('invalid_binding');
    binding = {userID: existing.userID, teamID: existing.teamID,
      ...(scope==='family'?{familyOwnerID:existing.familyOwnerID}:{}), appAccountToken: existing.appAccountToken};
    // Delayed snapshots cannot overwrite a newer authoritative observation.
    if (e.snapshotSignedAt < existing.snapshotSignedAt) {
      return {changed: false, subscription: {...existing}, ack: acknowledgement(e)};
    }
    // Equal-version contradictory evidence needs server reconciliation.
    if (e.snapshotSignedAt === existing.snapshotSignedAt &&
        (e.status !== existing.status || e.expiresAt !== existing.expiresAt ||
         e.productID !== existing.productID || (e.revokedAt ?? null) !== existing.revokedAt ||
         (e.graceExpiresAt ?? null) !== existing.graceExpiresAt)) reject('conflicting_snapshot');
  } else {
    if (!intent || intent.userID !== actor.userID ||
        (scope==='team' ? !uuid(intent.teamID) || intent.familyOwnerID != null :
          intent.teamID != null || intent.familyOwnerID !== actor.userID) ||
        !uuid(intent.token) || intent.token.toLowerCase() !== e.appAccountToken.toLowerCase() ||
        intent.productID !== (e.purchasedProductID ?? e.productID) || intent.authorized !== true || intent.cancelled === true)
      reject('missing_authorized_intent');
    // An opaque token cannot be reused to bind a second original subscription.
    if (intent.boundOriginalTransactionID && intent.boundOriginalTransactionID !== e.originalTransactionID)
      reject('intent_already_bound');
    binding = {userID: intent.userID, teamID: scope==='team'?intent.teamID:null,
      ...(scope==='family'?{familyOwnerID:intent.familyOwnerID}:{}), appAccountToken: intent.token};
  }
  const subscription = {
    ...binding, environment: e.environment, originalTransactionID: e.originalTransactionID,
    transactionID: e.transactionID, productID: e.productID,
    plan: config.products[e.productID], status: e.status,
    snapshotSignedAt: e.snapshotSignedAt, expiresAt: e.expiresAt,
    revokedAt: e.revokedAt ?? null, graceExpiresAt: e.graceExpiresAt ?? null
  };
  return {changed: true, subscription, ack: acknowledgement(e)};
}

function acknowledgement(e) {
  // Matches native acknowledgement, including when an older delivery is durable
  // but a newer subscription snapshot is kept. Return only after commit succeeds.
  return {transactionID: e.transactionID, originalTransactionID: e.originalTransactionID};
}

export function hasTeamSubscriptionAccess(subscription, {teamID, environment, now}) {
  if (!subscription || scopeFor(subscription.plan)!=='team' || !uuid(teamID) ||
      subscription.teamID !== teamID || subscription.environment !== environment ||
      !time(now) || subscription.revokedAt != null) return false;
  if (subscription.status === 1) return time(subscription.expiresAt) && subscription.expiresAt > now;
  if (subscription.status === 4) return time(subscription.graceExpiresAt) && subscription.graceExpiresAt > now;
  // Expired, billing retry without grace, revoked: no paid subscription access.
  // Other legitimate tester/family grants are evaluated separately by the app.
  return false;
}

// All relationship/filming inputs must be resolved by the authenticated server.
// Billing follows the selected linked athletes; it never substitutes for access
// to their records or authorization to film. No team ID constrains this grant.
export function hasFamilyVideoAccess(subscription, {athleteID, familyOwnerID,
    linkedAthleteIDs, recorderAuthorized, environment, now}) {
  if (!subscription || scopeFor(subscription.plan)!=='family' || subscription.teamID!=null ||
      !uuid(familyOwnerID) || subscription.familyOwnerID!==familyOwnerID ||
      subscription.userID!==familyOwnerID || !uuid(athleteID) || recorderAuthorized!==true ||
      !Array.isArray(linkedAthleteIDs) || linkedAthleteIDs.length<1 || linkedAthleteIDs.length>2 ||
      linkedAthleteIDs.some(x=>!uuid(x)) || new Set(linkedAthleteIDs).size!==linkedAthleteIDs.length ||
      !linkedAthleteIDs.includes(athleteID) || subscription.environment!==environment ||
      !time(now) || subscription.revokedAt!=null) return false;
  if (subscription.status===1) return time(subscription.expiresAt)&&subscription.expiresAt>now;
  if (subscription.status===4) return time(subscription.graceExpiresAt)&&subscription.graceExpiresAt>now;
  return false;
}
