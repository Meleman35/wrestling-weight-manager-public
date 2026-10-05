import test from 'node:test';
import assert from 'node:assert/strict';
import {subscriptionPresentation as present} from './subscription-presentation.mjs';
const prefix = 'com.damonmele.wrestlingmanager.';
const teamID = '11111111-1111-4111-8111-111111111111';
const product = (id, displayPrice = '€14,99') => ({id: prefix + id, displayPrice, type: 'autoRenewable'});

test('family uses localized Apple prices and never introduces a team target', () => {
  const view = present({kind:'family', products:[product('familyvideo.monthly'), product('teampro.annual')]});
  assert.equal(view.options.length, 1);
  assert.equal(view.options[0].price, '€14,99');
  assert.deepEqual(view.purchaseTarget, {kind:'family'});
  assert.equal(view.restoreTarget, null);
  assert.equal(view.canPurchase, false);
  assert.match(view.coverage, /two linked athletes across teams/);
  assert.match(view.recording, /even when the team does not have Team Pro/);
  assert.throws(() => present({kind:'family', teamID}), /family_has_no_team_target/);
});
test('team selection is required and restore cannot rebind a team', () => {
  const products = [product('teampro.monthly', '$75.00')];
  assert.equal(present({kind:'team', products, purchaseReady:true}).canPurchase, false);
  const view = present({kind:'team', teamID, products, purchaseReady:true});
  assert.equal(view.canPurchase, true);
  assert.deepEqual(view.purchaseTarget, {kind:'team', teamID});
  assert.equal(view.restoreTarget, null);
  assert.throws(() => present({kind:'team', teamID:'unknown'}), /invalid_team_target/);
});
test('missing or invalid StoreKit metadata has no hardcoded price fallback', () => {
  const products = [product('familyvideo.monthly', ''), {...product('familyvideo.annual'),type:'consumable'}, product('familyvideo.extra3')];
  const view = present({kind:'family', products, purchaseReady:true});
  assert.deepEqual(view.options, []);
  assert.equal(view.canPurchase, false);
  assert.match(view.unavailableReason, /Prices could not be loaded/);
  assert.throws(() => present({kind:'family',products:[product('familyvideo.monthly'),product('familyvideo.monthly')]}), /duplicate_product_metadata/);
});
test('unimplemented services and extra athletes are explicit, with no paid flag', () => {
  const view = present({kind:'family', products:[product('familyvideo.annual'),product('familyvideo.monthly')], purchaseReady:'true'});
  assert.equal(view.canPurchase, false);
  assert.deepEqual(view.options.map(p => p.period), ['month','year']);
  assert.equal(view.notices.length, 4);
  assert.match(view.notices[0], /remote weigh-ins.*later update.*not included at launch/);
  assert.match(view.extraAthletes, /not available yet/);
  assert.equal(Object.hasOwn(view, 'paid'), false);
  assert.equal(Object.hasOwn(view, 'entitlement'), false);
  assert.ok(Object.isFrozen(view));
  assert.ok(Object.isFrozen(view.options));
});
