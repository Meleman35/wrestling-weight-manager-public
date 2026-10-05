import {parentPort,workerData} from 'node:worker_threads';
import {appleTrustRoots} from './apple-trust-roots.mjs';
import {readAppleServerConfiguration} from './apple-server-config.mjs';
import {createAppleEvidenceAdapter} from './apple-evidence.mjs';
import {runAppleNotificationTest} from './apple-notification-test.mjs';
// Each bounded request owns its worker. Termination closes its outstanding work.
// This process has no database credentials or access to athlete photographs.
try {
 const config=readAppleServerConfiguration({readSecret:name=>process.env[name],rootCertificates:appleTrustRoots(),environment:workerData.environment});
 const apple=await createAppleEvidenceAdapter(config);
 const result=['testRequest','testStatus'].includes(workerData.action)
  ?await runAppleNotificationTest(apple,workerData.action,workerData.input)
  :await apple[workerData.action](workerData.input);
 parentPort.postMessage({ok:true,result});
} catch { parentPort.postMessage({ok:false}); }
