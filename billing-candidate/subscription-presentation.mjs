// Candidate presentation model only. It never grants access or verifies payment.
// Supply product metadata from StoreKit and readiness from integration configuration.
const prefix = 'com.damonmele.wrestlingmanager.';
const catalog = Object.freeze({
  [prefix + 'teampro.annual']: {kind: 'team', period: 'year'},
  [prefix + 'teampro.monthly']: {kind: 'team', period: 'month'},
  [prefix + 'familyvideo.annual']: {kind: 'family', period: 'year'},
  [prefix + 'familyvideo.monthly']: {kind: 'family', period: 'month'}
});
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const notices = Object.freeze([
  'Live streaming is not available yet.',
  'Cloud image and video storage allowances are not finalized.',
  'SMS texting is not available yet. Texting limits and costs will be shown before activation.'
]);

export function subscriptionPresentation({kind, teamID = null, products = [], purchaseReady = false} = {}) {
  if (!['team', 'family'].includes(kind)) throw new Error('invalid_plan_scope');
  if (!Array.isArray(products)) throw new Error('invalid_product_metadata');
  if (kind === 'family' && teamID !== null) throw new Error('family_has_no_team_target');
  if (kind === 'team' && teamID !== null && !uuid(teamID)) throw new Error('invalid_team_target');
  const seen = new Set();
  const options = [];
  for (const product of products) {
    const plan = catalog[product?.id];
    if (!plan || plan.kind !== kind) continue;
    // An ambiguous duplicate is not silently used as an offer.
    if (seen.has(product.id)) throw new Error('duplicate_product_metadata');
    seen.add(product.id);
    if (product.type !== 'autoRenewable' || typeof product.displayPrice !== 'string' ||
        !product.displayPrice.trim() || product.displayPrice.length > 100) continue;
    options.push(Object.freeze({
      productID: product.id,
      period: plan.period,
      price: product.displayPrice.trim(),
      label: plan.period === 'month' ? 'Monthly' : 'Annual'
    }));
  }
  options.sort((a, b) => (a.period === 'month' ? 0 : 1) - (b.period === 'month' ? 0 : 1));
  let unavailableReason = null;
  if (purchaseReady !== true) unavailableReason = 'Subscriptions are not available for purchase yet.';
  else if (kind === 'team' && teamID === null) unavailableReason = 'Select the team this subscription will cover.';
  else if (!options.length) unavailableReason = 'Prices could not be loaded. Try again when connected.';
  return Object.freeze({
    title: kind === 'team' ? 'Team Pro' : 'Family Video',
    coverage: kind === 'team'
      ? 'One wrestling team. The subscription stays with the team selected at purchase.'
      : 'Up to two linked athletes across teams. Coverage follows your athletes.',
    recording: kind === 'family'
      ? 'An authorized coach, manager or other approved filming device can record a covered athlete, even when the team does not have Team Pro.'
      : 'Team subscription coverage does not include unrelated teams.',
    extraAthletes: kind === 'family' ? 'Discounted coverage for athletes 3–8 is planned but is not available yet.' : null,
    notices,
    renewal: 'Subscriptions renew automatically unless cancelled. Manage or cancel through your Apple subscription settings.',
    restoreLabel: 'Restore Purchases',
    // Restore never carries a newly selected team binding.
    restoreTarget: null,
    purchaseTarget: kind === 'team' && teamID !== null ? Object.freeze({kind, teamID}) : kind === 'family' ? Object.freeze({kind}) : null,
    options: Object.freeze(options),
    canPurchase: unavailableReason === null,
    unavailableReason
  });
}
