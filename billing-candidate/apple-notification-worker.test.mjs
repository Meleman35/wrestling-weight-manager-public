import test from 'node:test';
import assert from 'node:assert/strict';
import {createAppleNotificationWorker} from './apple-notification-worker.mjs';
function fixture(extra={}){const calls=[];const lease={evidence:{old:true}};const run=createAppleNotificationWorker({apple:{refresh:async e=>{assert.equal(e,lease.evidence);calls.push('refresh');return {fresh:true};}},inbox:{claim:async()=>lease,release:async()=>calls.push('release')},repository:{applyKnown:async x=>{assert.equal(x.evidence.fresh,true);calls.push('apply');return {status:'updated'};}},config:{},...extra});return {run,calls};}
test('worker refreshes Apple before atomic application',async()=>{const {run,calls}=fixture();assert.deepEqual(await run(),{status:'updated'});assert.deepEqual(calls,['refresh','apply']);});
test('idle worker never queries Apple or writes',async()=>{const {run,calls}=fixture({inbox:{claim:async()=>null,release:async()=>{throw Error('Unexpected');}}});assert.deepEqual(await run(),{status:'idle'});assert.deepEqual(calls,[]);});
test('Apple failure releases lease and never applies',async()=>{const {run,calls}=fixture({apple:{refresh:async()=>{throw Error('PRIVATE');}}});assert.deepEqual(await run(),{status:'retry'});assert.deepEqual(calls,['release']);});
test('transaction failure or missing acknowledgement schedules retry',async()=>{for(const applyKnown of [async()=>{throw Error('SQL SECRET');},async()=>({status:'pending'})]){const {run,calls}=fixture({repository:{applyKnown}});assert.deepEqual(await run(),{status:'retry'});assert.deepEqual(calls,['refresh','release']);}});
