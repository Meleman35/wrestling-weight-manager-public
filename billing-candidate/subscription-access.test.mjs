import test from 'node:test';
import assert from 'node:assert/strict';
import {SubscriptionAccessService} from './subscription-access.mjs';
const user='11111111-1111-4111-8111-111111111111',team='22222222-2222-4222-8222-222222222222',athlete='33333333-3333-4333-8333-333333333333',other='44444444-4444-4444-8444-444444444444',now=1800000000000;
const actor=()=>({userID:user,liveSession:true,confirmed:true});
const sub=()=>({plan:'family_video_month',userID:user,familyOwnerID:user,teamID:null,environment:'Sandbox',status:1,expiresAt:now+1000,revokedAt:null});
function setup(patch={}){
 const state={teamAuthorized:true,athleteAuthorized:true,recorderAuthorized:true,teamSubscriptions:[],familyCoverage:[{subscription:sub(),familyOwnerID:user,linkedAthleteIDs:[athlete]}],...patch};
 const tx={currentActor:async()=>actor(),resolveAccess:async()=>state};
 const service=new SubscriptionAccessService({auth:{currentActor:tx.currentActor},repository:{accessTransaction:async(_,f)=>f(tx)},environment:'Sandbox',clock:()=>now});
 return {service,state,tx};
}
test('family coverage follows an authorized athlete without granting Team Pro or exposing owner',async()=>{
 const {service}=setup();const result=await service.read({}, {teamID:team,athleteID:athlete});
 assert.deepEqual(result,{teamID:team,athleteID:athlete,teamPro:false,familyVideo:true,checkedAt:now});
 assert.equal((await service.read({}, {teamID:other,athleteID:athlete})).familyVideo,true);
});
test('revoked, expired, unrelated and unauthorized filming deny family coverage',async()=>{
 for(const patch of [{recorderAuthorized:false},{athleteAuthorized:false},{familyCoverage:[]},
  {familyCoverage:[{subscription:{...sub(),revokedAt:now},familyOwnerID:user,linkedAthleteIDs:[athlete]}]},
  {familyCoverage:[{subscription:{...sub(),expiresAt:now},familyOwnerID:user,linkedAthleteIDs:[athlete]}]}])
  assert.equal((await setup(patch).service.read({}, {teamID:team,athleteID:athlete})).familyVideo,false);
});
test('request-supplied permissions, team bypass and session changes are rejected',async()=>{
 await assert.rejects(setup().service.read({}, {teamID:team,paid:true}),/invalid_request/);
 await assert.rejects(setup({teamAuthorized:false}).service.read({}, {teamID:team}),/access_forbidden/);
 const s=setup();let checks=0;s.tx.currentActor=async()=>++checks===1?actor():{...actor(),deletionFrozen:true};
 await assert.rejects(s.service.read({}, {teamID:team}),/unauthorized/);
});
test('Team Pro applies only to its verified team and environment',async()=>{
 const s=setup({teamSubscriptions:[{plan:'team_pro_year',teamID:team,environment:'Sandbox',status:1,expiresAt:now+1000,revokedAt:null}]});
 assert.equal((await s.service.read({}, {teamID:team})).teamPro,true);
 assert.equal((await s.service.read({}, {teamID:other})).teamPro,false);
});
