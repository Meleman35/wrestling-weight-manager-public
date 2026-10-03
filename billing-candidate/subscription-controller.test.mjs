import test from 'node:test';
import assert from 'node:assert/strict';
import {openSubscriptionScreen} from './subscription-controller.mjs';
const id = 'com.damonmele.wrestlingmanager.familyvideo.monthly';
function fixture(outcome = 'delivered') {
  const state = {generation:'a', refreshes:0, disposed:0, calls:[]};
  state.config = {container:{},kind:'family',sessionGeneration:'a',currentSession:()=>state.generation,
    handler:{postMessage:async body=>{state.calls.push(body);return body.command==='products'
      ? {products:[{id,displayPrice:'$14.99',type:'autoRenewable'}]} : {outcome};}},
    refreshAccess:async context=>{assert.equal(context.isCurrent(),true);state.refreshes++;},
    mount:(_,config,callbacks)=>{state.model=config;state.callbacks=callbacks;return {dispose:()=>state.disposed++};}};
  return state;
}
test('delivered purchase and restore refresh server access; readiness defaults off',async()=>{
  const s=fixture();const screen=await openSubscriptionScreen(s.config);
  assert.equal(s.model.purchaseReady,false);
  await s.callbacks.purchase(id,{kind:'family'});await s.callbacks.restore();
  assert.equal(s.refreshes,2);assert.deepEqual(s.calls.at(-1),{command:'restore'});
  screen.dispose();await assert.rejects(screen.recover(),/session_ended/);
});
test('pending, cancellation and awaiting server never infer access',async()=>{
  for(const outcome of ['pending','cancelled','awaitingServer']) {
    const s=fixture(outcome);const screen=await openSubscriptionScreen(s.config);
    assert.equal(await s.callbacks.restore(),outcome);assert.equal(s.refreshes,0);screen.dispose();
  }
});
test('account changes while loading products do not mount a screen',async()=>{
  const s=fixture();let resolve;s.config.handler.postMessage=()=>new Promise(r=>resolve=r);
  const pending=openSubscriptionScreen(s.config);s.generation='b';resolve({products:[]});
  await assert.rejects(pending,/session_ended/);assert.equal(s.callbacks,undefined);
});
test('account changes during server refresh reject completion and expose invalidation guard',async()=>{
  const s=fixture();let guard;s.config.refreshAccess=async context=>{guard=context.isCurrent;s.generation='b';};
  const screen=await openSubscriptionScreen(s.config);
  await assert.rejects(s.callbacks.restore(),/session_ended/);assert.equal(guard(),false);screen.dispose();
});
