import test from 'node:test';
import assert from 'node:assert/strict';
import {createSubscriptionAPIClient} from './subscription-api-client.mjs';
const id='00000000-0000-4000-8000-000000000001';
const other='00000000-0000-4000-8000-000000000002';
const endpoint='https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-billing';
function response(body,extra={}) {
 const value=new Response(JSON.stringify(body),{headers:{'Content-Type':'application/json'},...extra});
 Object.defineProperty(value,'url',{value:endpoint});return value;
}
function fixture(fetchImpl) {
 let session={accountID:id,sessionID:id,generation:'one',accessToken:'synthetic'};
 const client=createSubscriptionAPIClient({currentSession:()=>session,sessionGeneration:'one',publishableKey:'synthetic-public',fetchImpl});
 return {client,setSession:value=>session=value,getSession:()=>session};
}
test('coverage save/clear uses authenticated fixed endpoint without cookies or redirects',async()=>{
 const calls=[];const {client}=fixture(async(url,options)=>{calls.push({url,...options});return response({selectedCount:JSON.parse(options.body).data.athleteIDs.length});});
 assert.deepEqual(await client.saveCoverage({athleteIDs:[id]}),{selectedCount:1});
 assert.deepEqual(await client.saveCoverage({athleteIDs:[]}),{selectedCount:0});
 assert.equal(calls[0].url,endpoint);assert.equal(calls[0].headers.Authorization,'Bearer synthetic');
 assert.equal(calls[0].headers.apikey,'synthetic-public');assert.equal(calls[0].credentials,'omit');assert.equal(calls[0].redirect,'error');
 assert.deepEqual(JSON.parse(calls[0].body),{action:'coverage',data:{athleteIDs:[id]}});
});
test('duplicate/third/invalid athletes are rejected without a request',async()=>{
 const {client}=fixture(()=>{throw Error('must not request');});
 for(const athleteIDs of [[id,id.toUpperCase()],[id,other,id],['bad']]) await assert.rejects(client.saveCoverage({athleteIDs}),/invalid_coverage/);
});
test('access response must match requested scope and contain boolean grants',async()=>{
 let body={teamID:id,athleteID:null,eventID:null,teamPro:false,familyVideo:false,checkedAt:10};
 const {client}=fixture(async()=>response(body));
 assert.equal((await client.readAccess({teamID:id})).teamPro,false);
 for(const change of [{teamID:other},{teamPro:'true'},{checkedAt:-1},{receipt:'private'}]) {
  const prior=body;body={...body,...change};await assert.rejects(client.readAccess({teamID:id}),/billing_unconfirmed/);body=prior;
 }
});
test('account/session changes and stopped clients discard late responses and abort transport',async()=>{
 let resolve,signal;const f=fixture((url,options)=>{signal=options.signal;return new Promise(r=>resolve=r);});
 const pending=f.client.saveCoverage({athleteIDs:[id]});
 f.setSession({...f.getSession(),accountID:other});resolve(response({selectedCount:1}));
 await assert.rejects(pending,/billing_session_ended/);
 f.setSession({...f.getSession(),accountID:id});
 const second=f.client.saveCoverage({athleteIDs:[]});f.client.stop();assert.equal(signal.aborted,true);
 resolve(response({selectedCount:0}));await assert.rejects(second,/billing_session_ended/);
 await assert.rejects(f.client.saveCoverage({athleteIDs:[]}),/billing_session_ended/);
});
test('host invalidation, oversized bodies and raw backend errors never become confirmations',async()=>{
 let body=response({selectedCount:0});const {client}=fixture(async()=>body);
 await assert.rejects(client.saveCoverage({athleteIDs:[],isCurrent:()=>false}),/billing_session_ended/);
 body=response({private:'x'.repeat(65536)});await assert.rejects(client.saveCoverage({athleteIDs:[]}),/billing_unconfirmed/);
 body=response({error:'private server detail'},{status:503});await assert.rejects(client.saveCoverage({athleteIDs:[]}),/^Error: billing_unconfirmed$/);
});
