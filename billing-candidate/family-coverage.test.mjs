import test from 'node:test';import assert from 'node:assert/strict';
import {FamilyCoverageService} from './family-coverage.mjs';
const user='11111111-1111-4111-8111-111111111111',athlete='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const actor=()=>({userID:user,liveSession:true,confirmed:true});
function setup(){
 const calls=[];const tx={currentActor:async()=>actor(),replaceFamilyCoverage:async(u,ids)=>{calls.push([u,ids]);return {selectedCount:ids.length};}};
 const service=new FamilyCoverageService({auth:{currentActor:async()=>actor()},repository:{coverageTransaction:async(_,f)=>f(tx)}});
 return {service,tx,calls};
}
test('selection derives its owner from verified context and permits clearing all slots',async()=>{
 const s=setup();assert.deepEqual(await s.service.select({}, {athleteIDs:[athlete.toUpperCase()]}),{selectedCount:1});
 assert.deepEqual(s.calls,[[user,[athlete]]]);assert.deepEqual(await s.service.select({}, {athleteIDs:[]}),{selectedCount:0});
});
test('extra owners, profile IDs, duplicate athletes and more than two slots are rejected',async()=>{
 const s=setup();for(const request of [{athleteIDs:[athlete],userID:user},{profileIDs:[athlete]},{athleteIDs:[athlete,athlete.toUpperCase()]},{athleteIDs:[athlete,user,user]},{athleteIDs:['bad']}])
  await assert.rejects(s.service.select({},request),/invalid_request/);
 assert.equal(s.calls.length,0);
});
test('session/deletion changes within transaction prevent successful selection',async()=>{
 const s=setup();let checks=0;s.tx.currentActor=async()=>++checks===1?actor():{...actor(),deletionFrozen:true};
 await assert.rejects(s.service.select({}, {athleteIDs:[athlete]}),/unauthorized/);
});
