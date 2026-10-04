// Server-only candidate. Credentials and certificate bytes are injected at
// runtime by the operator; nothing secret is stored in this packet.
export class AppleEvidenceError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = code => { throw new AppleEvidenceError(code); };
const numericID = value => typeof value === 'string' && /^[0-9]{1,40}$/.test(value);
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const millis = value => Number.isSafeInteger(value) && value >= 0;

// Use Apple's maintained verification implementation; do not decode JWT/JWS
// payloads as proof of payment. Local Xcode evidence is not accepted here.
export async function createAppleEvidenceAdapter(options) {
  const {SignedDataVerifier, AppStoreServerAPIClient, Environment} =
    await import('@apple/app-store-server-library');
  const {environment, bundleID, appAppleID, rootCertificates, signingKey, keyID, issuerID, products} = options;
  if (!['Sandbox','Production'].includes(environment) || !Array.isArray(rootCertificates) ||
      rootCertificates.length === 0 || !signingKey || !keyID || !issuerID || !bundleID ||
      (environment === 'Production' && (!Number.isSafeInteger(appAppleID) || appAppleID <= 0)))
    fail('missing_server_configuration');
  const env = environment === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
  const verifier = new SignedDataVerifier(rootCertificates, true, env, bundleID, appAppleID);
  const api = new AppStoreServerAPIClient(signingKey, keyID, issuerID, bundleID, env);
  return new AppleEvidenceAdapter({verifier, api, environment, bundleID, products});
}

// Dependency injection permits hostile-input tests without pretending to test
// Apple's cryptography. Production must use the factory above, not test stubs.
export class AppleEvidenceAdapter {
  constructor({verifier, api, environment, bundleID, products}) {
    this.verifier = verifier; this.api = api;
    this.environment = environment; this.bundleID = bundleID; this.products = products;
  }

  checkTransaction(t) {
    if (!t || t.bundleId !== this.bundleID || t.environment !== this.environment ||
        !Object.hasOwn(this.products, t.productId) || !numericID(t.transactionId) ||
        !numericID(t.originalTransactionId) || !uuid(t.appAccountToken) ||
        t.type !== 'Auto-Renewable Subscription' || !millis(t.expiresDate) || !millis(t.signedDate))
      fail('invalid_verified_transaction');
    if (t.revocationDate != null && !millis(t.revocationDate)) fail('invalid_revocation');
  }

  async resolve(signedTransaction) {
    if (typeof signedTransaction !== 'string' || signedTransaction.length < 10 ||
        signedTransaction.length > 65536 || signedTransaction.split('.').length !== 3)
      fail('invalid_signed_payload');
    const submitted = await this.verifier.verifyAndDecodeTransaction(signedTransaction);
    this.checkTransaction(submitted);
    // Reconcile current canonical state instead of trusting old notification
    // labels or an old restored transaction's expiry.
    const response = await this.api.getAllSubscriptionStatuses(submitted.originalTransactionId);
    if (response.bundleId !== this.bundleID || response.environment !== this.environment ||
        !Array.isArray(response.data)) fail('invalid_status_response');
    const matches = response.data.flatMap(group => group.lastTransactions ?? [])
      .filter(item => item.originalTransactionId === submitted.originalTransactionId);
    if (matches.length !== 1) fail('ambiguous_subscription_status');
    const item = matches[0];
    if (!item.signedTransactionInfo || !item.signedRenewalInfo || ![1,2,3,4,5].includes(item.status))
      fail('incomplete_subscription_status');
    const current = await this.verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
    const renewal = await this.verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo);
    this.checkTransaction(current);
    if (current.originalTransactionId !== submitted.originalTransactionId ||
        current.appAccountToken.toLowerCase() !== submitted.appAccountToken.toLowerCase() ||
        renewal.originalTransactionId !== current.originalTransactionId ||
        renewal.environment !== this.environment || renewal.productId !== current.productId ||
        !millis(renewal.signedDate)) fail('inconsistent_subscription_evidence');
    if (renewal.appAccountToken && renewal.appAccountToken.toLowerCase() !== current.appAccountToken.toLowerCase())
      fail('inconsistent_subscription_evidence');
    if (renewal.gracePeriodExpiresDate != null && !millis(renewal.gracePeriodExpiresDate))
      fail('invalid_grace_date');
    if (item.status === 4 && !millis(renewal.gracePeriodExpiresDate)) fail('missing_grace_date');
    return {
      // Ack the transaction submitted by the native client, even when Apple
      // canonical state refers to a later renewal. Scope always uses originalID.
      transactionID: submitted.transactionId,
      originalTransactionID: current.originalTransactionId,
      productID: current.productId, purchasedProductID: submitted.productId,
      appAccountToken: current.appAccountToken,
      bundleID: current.bundleId, environment: current.environment,
      status: item.status, expiresAt: current.expiresDate,
      revokedAt: current.revocationDate ?? null,
      graceExpiresAt: renewal.gracePeriodExpiresDate ?? null,
      snapshotSignedAt: Math.max(current.signedDate, renewal.signedDate)
    };
  }

  async refresh(evidence) {
    if (!numericID(evidence?.originalTransactionID) || !uuid(evidence?.appAccountToken) ||
        evidence.environment !== this.environment || evidence.bundleID !== this.bundleID)
      fail('invalid_refresh_binding');
    const response = await this.api.getAllSubscriptionStatuses(evidence.originalTransactionID);
    if (response.bundleId !== this.bundleID || response.environment !== this.environment ||
        !Array.isArray(response.data)) fail('invalid_status_response');
    const matches = response.data.flatMap(g => g.lastTransactions ?? [])
      .filter(t => t.originalTransactionId === evidence.originalTransactionID);
    if (matches.length !== 1 || !matches[0].signedTransactionInfo) fail('ambiguous_subscription_status');
    // resolve performs signature checks and another fresh canonical query. The
    // first response locates a transaction; it is never itself evidence.
    const current = await this.resolve(matches[0].signedTransactionInfo);
    if (current.originalTransactionID !== evidence.originalTransactionID ||
        current.appAccountToken.toLowerCase() !== evidence.appAccountToken.toLowerCase())
      fail('inconsistent_subscription_evidence');
    return current;
  }

  async notificationTransaction(signedPayload) {
    if (typeof signedPayload !== 'string' || signedPayload.length > 131072 ||
        signedPayload.split('.').length !== 3) fail('invalid_notification');
    const decoded = await this.verifier.verifyAndDecodeNotification(signedPayload);
    if (!uuid(decoded.notificationUUID) || decoded.data?.bundleId !== this.bundleID ||
        decoded.data?.environment !== this.environment)
      fail('notification_requires_separate_handling');
    // TEST is verified but has no purchase transaction and grants no access.
    if (decoded.notificationType === 'TEST') return {notificationID: decoded.notificationUUID, kind:'test'};
    if (decoded.notificationType === 'CONSUMPTION_REQUEST' || !decoded.data?.signedTransactionInfo)
      fail('notification_requires_separate_handling');
    return {notificationID: decoded.notificationUUID,
      evidence: await this.resolve(decoded.data.signedTransactionInfo)};
  }
}

