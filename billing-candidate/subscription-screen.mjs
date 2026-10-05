import {subscriptionPresentation} from './subscription-presentation.mjs';

// Standalone candidate. The authenticated integration supplies callbacks; this
// component never reads tokens, handles receipts, or sets an access entitlement.
export function mountSubscriptionScreen(container, configuration, callbacks = {}) {
  const model = subscriptionPresentation(configuration);
  const doc = container.ownerDocument;
  let disposed = false;
  let busy = false;
  const listeners = [];
  const controls = [];
  const root = doc.createElement('section');
  root.className = 'wm-subscription-screen';
  root.setAttribute('aria-label', model.title + ' subscription');
  function element(tag, text, parent = root) {
    const node = doc.createElement(tag);
    if (text != null) node.textContent = text;
    parent.append(node);
    return node;
  }
  element('h2', model.title);
  element('p', model.coverage);
  element('p', model.recording);
  if (model.extraAthletes) element('p', model.extraAthletes);
  const pricing = element('div');
  pricing.className = 'wm-subscription-options';
  const status = element('p', model.unavailableReason ?? 'Choose a billing period.');
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  const unavailable = element('details');
  element('summary', 'Streaming, storage and texting', unavailable);
  const list = element('ul', null, unavailable);
  for (const notice of model.notices) element('li', notice, list);
  element('p', model.renewal);
  function control(label, allowed, action, parent = root) {
    const button = element('button', label, parent);
    button.type = 'button';
    button.disabled = !allowed;
    controls.push({button, allowed});
    const listener = async () => {
      if (disposed || busy || !allowed) return;
      busy = true;
      root.setAttribute('aria-busy', 'true');
      controls.forEach(({button}) => { button.disabled = true; });
      status.textContent = 'Waiting for Apple and purchase confirmation…';
      try {
        const outcome = await action();
        if (disposed) return;
        status.textContent = outcome === 'cancelled' ? 'Purchase cancelled.'
          : outcome === 'pending' ? 'Purchase is awaiting approval. Access will update after confirmation.'
          : outcome === 'delivered' ? 'Purchase processed. Checking your current access.'
          : 'Purchase confirmation is pending. You can restore purchases after reconnecting.';
      } catch {
        if (!disposed) status.textContent = 'The request could not be completed. Reconnect and try again.';
      } finally {
        busy = false;
        if (!disposed) {
          root.removeAttribute('aria-busy');
          controls.forEach(({button, allowed}) => { button.disabled = !allowed; });
        }
      }
    };
    button.addEventListener('click', listener);
    listeners.push(() => button.removeEventListener('click', listener));
    return button;
  }
  for (const option of model.options) {
    control(`${option.label} — ${option.price}/${option.period}`,
      model.canPurchase && typeof callbacks.purchase === 'function',
      () => callbacks.purchase(option.productID, model.purchaseTarget), pricing);
  }
  control(model.restoreLabel,
    configuration.purchaseReady === true && typeof callbacks.restore === 'function',
    () => callbacks.restore());
  container.append(root);
  return Object.freeze({
    model,
    // On logout, team/account change or navigation, dispose this screen before
    // constructing a new authenticated store. Late replies cannot update it.
    dispose() {
      if (disposed) return;
      disposed = true;
      listeners.forEach(remove => remove());
      root.remove();
    }
  });
}
