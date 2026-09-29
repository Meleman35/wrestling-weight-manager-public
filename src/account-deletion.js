/* Draft account-deletion intake UI. Not installed in the live app.
 * The adapter must supply the current personal account and authenticated RPC.
 * This component never deletes data or claims a pending request is completed.
 */
window.WMAccountDeletion = (() => {
  'use strict';
  function create({ host, rpc, currentUser, allowed = () => true, onClose = () => {} }) {
    let generation = 0, owner = '', busy = false;
    const doc = host.ownerDocument;
    const el = (tag, text, attrs = {}) => {
      const node = doc.createElement(tag);
      if (text !== undefined) node.textContent = text;
      Object.entries(attrs).forEach(([k, v]) => node.setAttribute(k, v));
      return node;
    };
    const valid = g => generation === g && owner === currentUser() && allowed() && !host.hidden;
    function close() {
      generation++; owner = ''; busy = false;
      host.replaceChildren(); host.hidden = true; onClose();
    }
    function receipt(data) {
      const r = data?.request;
      if (!r || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(r.id || '') ||
          !['requested', 'processing', 'completed'].includes(r.status) ||
          !Number.isFinite(Date.parse(r.requested_at)) ||
          !Number.isFinite(Date.parse(r.deadline_at)) ||
          (r.status === 'completed' && !Number.isFinite(Date.parse(r.completed_at)))) return null;
      return r;
    }
    function render(data, g) {
      if (!valid(g)) return;
      host.replaceChildren();
      host.append(el('h2', 'Delete your account'));
      const closeButton = el('button', 'Close', { type: 'button', 'data-deletion-close': '' });
      closeButton.onclick = close; host.append(closeButton);
      const r = receipt(data);
      if (data?.request && !r) throw Error('The server returned an incomplete receipt. Reopen this screen to check your request.');
      if (r) {
        host.append(el('p', r.status === 'completed' ? 'Your account deletion is complete.' :
          r.status === 'processing' ? 'Your deletion request is being processed.' : 'Your deletion request was received.'));
        host.append(el('p', 'Request reference: ' + r.id, { 'data-deletion-receipt': '' }));
        if (r.status !== 'completed') {
          host.append(el('p', 'Requested on ' + new Date(r.requested_at).toLocaleDateString() +
            '. Completion due by ' + new Date(r.deadline_at).toLocaleDateString() + '.'));
          host.append(el('p', 'Your account has not been deleted yet. You will receive confirmation when deletion is complete.'));
        }
        return;
      }
      if (!data?.enabled || !Number.isInteger(data.completion_days) || data.completion_days < 1 || data.completion_days > 30) {
        host.append(el('p', 'Account deletion requests are not enabled in this preview. No request has been sent.'));
        return;
      }
      host.append(el('p', 'This requests permanent deletion of your personal account and its associated personal data. It does not delete other people’s accounts. Shared team or child records require review so that the correct information is removed or retained where legally required.'));
      host.append(el('p', 'Save any records you want to keep first. Completion is due within ' + data.completion_days +
        ' days. Sending this request is not confirmation that deletion is finished.'));
      const subscriptions = el('a', 'Manage Apple subscriptions', { href: 'https://apps.apple.com/account/subscriptions', target: '_blank', rel: 'noopener noreferrer' });
      host.append(el('p', 'Deleting an account does not automatically cancel Apple subscriptions. You can request deletion now without waiting for a subscription to expire.'), subscriptions);
      const form = el('form'), label = el('label', 'Type DELETE to confirm', { for: 'accountDeletionConfirmation' });
      const input = el('input', undefined, { id: 'accountDeletionConfirmation', autocomplete: 'off', maxlength: '6', 'aria-describedby': 'accountDeletionStatus' });
      const status = el('p', '', { id: 'accountDeletionStatus', role: 'status', 'aria-live': 'polite' });
      const submit = el('button', 'Request account deletion', { type: 'submit', 'data-deletion-submit': '' });
      submit.disabled = true;
      input.oninput = () => { submit.disabled = busy || input.value !== 'DELETE'; };
      form.append(label, input, submit, status); host.append(form);
      form.onsubmit = async event => {
        event.preventDefault();
        if (busy || !valid(g) || input.value !== 'DELETE') return;
        busy = true; submit.disabled = true; input.disabled = true;
        status.textContent = 'Sending your request…';
        try {
          const result = await rpc('request', 'DELETE');
          if (!valid(g)) return;
          if (!receipt(result)) throw Error('No receipt was confirmed. Reopen to check the request, or retry; this will not create a duplicate.');
          render(result, g);
        } catch (error) {
          if (valid(g)) status.textContent = error.message || 'The request could not be confirmed. Check your connection and retry.';
        } finally {
          if (valid(g)) { busy = false; input.disabled = false; submit.disabled = input.value !== 'DELETE'; }
        }
      };
    }
    async function open() {
      close(); owner = currentUser();
      if (!owner || !allowed()) return;
      host.hidden = false; const g = generation;
      host.replaceChildren(el('p', 'Checking your account deletion status…'));
      try {
        const data = await rpc('status');
        if (valid(g)) render(data, g);
      } catch (error) {
        if (!valid(g)) return;
        host.replaceChildren(el('p', error.message || 'Could not check your request. Try again while connected.'), el('button', 'Close', { type: 'button' }));
        host.querySelector('button').onclick = close;
      }
    }
    return { open, close, invalidate: close };
  }
  return { create };
})();
