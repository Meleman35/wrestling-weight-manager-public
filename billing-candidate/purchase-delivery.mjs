import {reconcileSubscription} from './subscription-policy.mjs';

// Server integration candidate. Repository/auth ports deliberately have no
// permissive defaults. No HTTP endpoint or production database is installed.
export class PurchaseDeliveryService {
  constructor({auth, apple, repository, config, clock=Date.now}) {
    this.auth=auth; this.apple=apple; this.repository=repository; this.config=config; this.clock=clock;
  }

  async deliver(authContext, request) {
    if (!request || Object.keys(request).some(k=>k!=='signedTransaction') ||
        typeof request.signedTransaction!=='string') throw Error('invalid_request');
    const initial=await this.auth.currentActor(authContext);
    this.requireActor(initial);
    const evidence=await this.apple.resolve(request.signedTransaction);
    // An Apple/network await must not preserve an expired/revoked app session.
    // The auth port validates the exact session_id and account from authContext.
    const current=await this.auth.currentActor(authContext);
    this.requireActor(current);
    if(initial.userID!==current.userID)throw Error('session_changed');
    // Locks must cover both immutable original binding and token intent. Unique
    // database constraints remain mandatory; an in-process mutex is insufficient.
    return this.repository.transaction({userID:initial.userID,environment:evidence.environment,
      originalTransactionID:evidence.originalTransactionID, token:evidence.appAccountToken},async tx=>{
      const actor=await tx.currentActor(authContext);
      this.requireActor(actor);
      if(actor.userID!==initial.userID)throw Error('session_changed');
      const existing=await tx.getSubscription(evidence.environment,evidence.originalTransactionID);
      const intent=await tx.getIntent(evidence.appAccountToken);
      const decision=reconcileSubscription({actor,evidence,existing,intent,config:this.config,now:this.clock()});
      if(decision.changed)await tx.saveSubscription(decision.subscription);
      if(!existing)await tx.bindIntent(evidence.appAccountToken,evidence.originalTransactionID);
      // Must persist delivery identity even when canonical subscription is newer.
      await tx.recordDelivery(evidence.environment,evidence.transactionID,evidence.originalTransactionID);
      return decision.ack;
    });
    // repository.transaction returns only after successful commit. Its result
    // is the native acknowledgement; paid access is read through separate policy.
  }

  requireActor(actor) {
    if(!actor || actor.liveSession!==true || actor.confirmed!==true || actor.deleted===true ||
       actor.banned===true || actor.managedTeamLogin===true || actor.deletionFrozen===true)
      throw Error('unauthorized');
  }
}
