import {createNativePurchaseClient} from './native-purchase-client.mjs';
import {mountSubscriptionScreen} from './subscription-screen.mjs';
import {mountFamilyCoverageScreen} from './family-coverage-screen.mjs';

// Candidate composition only; the native host still owns activation and auth.
export async function openSubscriptionScreen({container, kind, teamID = null,
  handler, currentSession, sessionGeneration, purchaseReady = false,
  refreshAccess, familyCoverage = null, mount = mountSubscriptionScreen,
  mountCoverage = mountFamilyCoverageScreen} = {}) {
  if (typeof refreshAccess !== 'function') throw new Error('access_refresh_required');
  const client = createNativePurchaseClient({handler, currentSession, sessionGeneration});
  let stopped = false;
  let screen;
  let coverageScreen;
  const valid = () => !stopped && currentSession() === sessionGeneration;
  const stop = () => { stopped = true; client.stop(); screen?.dispose(); coverageScreen?.dispose(); };
  async function run(action) {
    if (!valid()) throw new Error('purchase_session_ended');
    const outcome = await action();
    if (!valid()) throw new Error('purchase_session_ended');
    if (outcome === 'delivered') {
      // The callback fetches authoritative access. No local paid flag is written.
      await refreshAccess({sessionGeneration, isCurrent: valid});
      if (!valid()) throw new Error('purchase_session_ended');
    }
    return outcome;
  }
  try {
    const products = await client.loadProducts();
    if (!valid()) throw new Error('purchase_session_ended');
    screen = mount(container, {kind, teamID, products, purchaseReady}, {
      purchase: (id, target) => run(() => client.purchase(id, target)),
      restore: () => run(() => client.restore())
    });
    if (kind === 'family' && familyCoverage) {
      coverageScreen = mountCoverage(container, {...familyCoverage, isCurrent:valid,
        refreshAccess:() => refreshAccess({sessionGeneration, isCurrent:valid})});
    }
    return Object.freeze({dispose: stop, recover: () => run(() => client.recover())});
  } catch (error) { stop(); throw error; }
}
