import test from 'node:test';
import assert from 'node:assert/strict';
import {createRemoteRetentionWorker} from '../src/remote-weighins-retention.mjs';
test('failed object removal preserves database for retry; confirmed purge precedes row deletion',async()=>{
 const events=[];
 const tx={query:async(sql,args)=>{events.push([sql,args]);return {rows:[{id:args[0]}]};}};
 const db={query:async()=>({rows:[{id:'failed'},{id:'expired'}]}),transaction:async f=>f(tx)};
 const photos={purge:async id=>{events.push(['purge',id]);if(id==='failed')throw Error('storage unavailable');}};
 const worker=createRemoteRetentionWorker({db,photos});
 assert.deepEqual(await worker.run(),{removed:1,failed:['failed']});
 assert.deepEqual(events.slice(0,2),[['purge','failed'],['purge','expired']]);
 assert.ok(events[2][0].includes('revoked and expires_at<=clock_timestamp() for update'));
 assert.ok(events[3][0].includes('delete from remote_reporting.submissions'));
 assert.ok(events[4][0].includes('delete from remote_reporting.evidence'));
 await assert.rejects(worker.run({limit:0}));
});
