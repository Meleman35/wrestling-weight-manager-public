import test from 'node:test';
import assert from 'node:assert/strict';
import {SignedDataVerifier,Environment,AppStoreServerAPIClient} from '@apple/app-store-server-library';
import {createAppleEvidenceAdapter} from './apple-evidence.mjs';
test('pinned Apple library exposes expected API and rejects forged JWS',async()=>{
  assert.equal(typeof AppStoreServerAPIClient.prototype.getAllSubscriptionStatuses,'function');
  // No roots and no online checks in this negative-only test. This is not a
  // valid-signature/certificate test; those require actual Apple sandbox evidence.
  const verifier=new SignedDataVerifier([],false,Environment.SANDBOX,'com.damonmele.wrestlingmanager');
  await assert.rejects(verifier.verifyAndDecodeTransaction('forged.jws.signature'));
});
test('production factory rejects absent key/certificate/App Apple ID configuration',async()=>{
  await assert.rejects(createAppleEvidenceAdapter({environment:'Production',bundleID:'com.damonmele.wrestlingmanager',rootCertificates:[]}),e=>e.code==='missing_server_configuration');
});
