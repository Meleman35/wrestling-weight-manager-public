// Candidate client for WKScriptMessageHandlerWithReply. The native host owns
// authentication, readiness and lifecycle; this client cannot enable payments.
const products = new Set([
  'com.damonmele.wrestlingmanager.teampro.annual',
  'com.damonmele.wrestlingmanager.teampro.monthly',
  'com.damonmele.wrestlingmanager.familyvideo.annual',
  'com.damonmele.wrestlingmanager.familyvideo.monthly'
]);
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

export function createNativePurchaseClient({handler, currentSession, sessionGeneration} = {}) {
  if (!handler || typeof handler.postMessage !== 'function' ||
      typeof currentSession !== 'function' || typeof sessionGeneration !== 'string' || !sessionGeneration)
    throw new Error('native_purchase_unavailable');
  let stopped = false;
  let busy = false;
  const valid = () => !stopped && currentSession() === sessionGeneration;
  async function request(body) {
    if (!valid()) throw new Error('purchase_session_ended');
    if (busy) throw new Error('purchase_request_busy');
    busy = true;
    try {
      const response = await handler.postMessage(body);
      if (!valid()) throw new Error('purchase_session_ended');
      return response;
    } catch (error) {
      if (!valid()) throw new Error('purchase_session_ended');
      // Never expose arbitrary native/provider diagnostics in app UI.
      throw new Error('purchase_request_unconfirmed');
    } finally { busy = false; }
  }
  async function outcome(body) {
    const value = await request(body);
    if (!exact(value, ['outcome']) || !['delivered','awaitingServer','pending','cancelled'].includes(value.outcome))
      throw new Error('invalid_native_purchase_response');
    return value.outcome;
  }
  return Object.freeze({
    async loadProducts() {
      const response = await request({command:'products'});
      if (!exact(response,['products']) || !Array.isArray(response.products) || response.products.length > 4)
        throw new Error('invalid_native_product_response');
      const seen = new Set();
      return Object.freeze(response.products.map(p => {
        if (!exact(p,['id','displayPrice','type']) || !products.has(p.id) || seen.has(p.id) ||
            p.type !== 'autoRenewable' || typeof p.displayPrice !== 'string' ||
            !p.displayPrice.trim() || p.displayPrice.length > 100)
          throw new Error('invalid_native_product_response');
        seen.add(p.id);
        return Object.freeze({...p});
      }));
    },
    purchase(productID, target) {
      if (!products.has(productID)) throw new Error('invalid_purchase_product');
      let selected;
      if (exact(target,['kind']) && target.kind === 'family' && productID.includes('.familyvideo.'))
        selected = {kind:'family'};
      else if (exact(target,['kind','teamID']) && target.kind === 'team' && uuid(target.teamID) && productID.includes('.teampro.'))
        selected = {kind:'team',teamID:target.teamID};
      else throw new Error('invalid_purchase_target');
      return outcome({command:'purchase',productID,target:selected});
    },
    // Restores never carry a new team or family owner.
    restore() { return outcome({command:'restore'}); },
    recover() { return outcome({command:'recover'}); },
    stop() { stopped = true; }
  });
}
