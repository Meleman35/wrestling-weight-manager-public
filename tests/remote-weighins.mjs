import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRemoteCapture,summarizeWindow,reportCsv,validateWindow} from '../src/remote-weighins.mjs';
const start=Date.parse('2026-10-05T06:00:00Z');
const window={id:'week-1',programId:'program-1',timeZone:'America/Denver',opensAt:new Date(start).toISOString(),closesAt:new Date(start+7*86400000).toISOString()};
function fixture(submit) {
 let time=start+1000,n=0;
 const c=createRemoteCapture({context:{accountId:'coach',clubId:'club',generation:'session-1'},window,now:()=>time,uuid:()=>`id-${++n}`,submit:submit|| (async p=>({submissionId:p.submissionId,status:'submitted',receiptId:'receipt',receivedAt:new Date(time).toISOString()}))});
 const ready=()=>{const token=c.scan('athlete','qr');time+=100;c.reading(token,{value:120,unit:'lb',settled:true,source:'scale',observedAt:time});time+=100;c.snapshot(token,{evidenceId:'private-photo',capturedAt:time,source:'camera',noticeAccepted:true});return token;};
 return {c,ready,tick:ms=>time+=ms,time:()=>time};
}
test('new scan rejects stale reading and late camera callback',()=>{
 const {c,ready,time,tick}=fixture();const old=ready();const current=c.scan('next-athlete','nfc');
 assert.equal(c.state().phase,'weight');assert.throws(()=>c.snapshot(old,{evidenceId:'x',capturedAt:time(),source:'camera',noticeAccepted:true}),/changed/);
 assert.throws(()=>c.reading(current,{value:120,unit:'lb',settled:true,source:'scale',observedAt:time()}),/predates/);
 tick(1);c.reading(current,{value:122,unit:'lb',settled:true,source:'scale',observedAt:time()});assert.equal(c.state().phase,'photo');
});
test('no manual reading, gallery photo or omitted notice',()=>{
 const f=fixture(),token=f.c.scan('athlete','qr');f.tick(1);
 const r={value:120,unit:'lb',settled:true,source:'manual',observedAt:f.time()};assert.throws(()=>f.c.reading(token,r),/scale/);
 f.c.reading(token,{...r,source:'scale'});
 assert.throws(()=>f.c.snapshot(token,{evidenceId:'gallery',capturedAt:f.time(),source:'gallery',noticeAccepted:true}),/camera/);
 assert.throws(()=>f.c.snapshot(token,{evidenceId:'photo',capturedAt:f.time(),source:'camera',noticeAccepted:false}),/notice/);
});
test('freshness expiry and a new reading clears snapshot',async()=>{
 const f=fixture();const token=f.ready();f.tick(30001);await assert.rejects(f.c.send(),/expired/);
 f.c.reading(token,{value:121,unit:'lb',settled:true,source:'scale',observedAt:f.time()});assert.equal(f.c.state().phase,'photo');await assert.rejects(f.c.send(),/snapshot/);
});
test('network retry uses identical immutable payload and never claims submitted early',async()=>{
 let calls=0,first;const f=fixture(async p=>{calls++;if(!first)first=p;else assert.strictEqual(p,first);if(calls===1)throw Error('offline');return {submissionId:p.submissionId,status:'submitted',receiptId:'r',receivedAt:new Date(start+80000).toISOString()};});
 f.ready();await assert.rejects(f.c.send(),/offline/);assert.equal(f.c.state().phase,'pending_retry');assert.throws(()=>f.c.scan('other','qr'),/pending/);f.tick(60000);
 const receipt=await f.c.send();assert.equal(f.c.state().phase,'submitted');assert.strictEqual(await f.c.send(),receipt);assert.equal(calls,2);
});
test('unconfirmed server response stays pending',async()=>{
 const f=fixture(async p=>({submissionId:p.submissionId,status:'queued'}));f.ready();await assert.rejects(f.c.send(),/not confirmed/);assert.equal(f.c.state().phase,'pending_retry');
});
test('account disposal rejects late acceptance and hides athlete',async()=>{
 let resolve;const f=fixture(()=>new Promise(r=>resolve=r));f.ready();const p=f.c.send();f.c.dispose();resolve({});await assert.rejects(p,/closed/);assert.deepEqual(f.c.state(),{phase:'closed',athleteId:null,submissionId:null});
});
test('report window requires named timezone; upper deadline is exclusive',()=>{
 assert.throws(()=>validateWindow({...window,timeZone:''}),/timezone/);const f=fixture();f.tick(7*86400000);assert.throws(()=>f.c.scan('a','qr'),/closed/);
});
test('scale reading and snapshot stop at the exact window deadline',()=>{
 const f=fixture();f.tick(7*86400000-1010);const token=f.c.scan('a','qr');f.tick(10);
 assert.throws(()=>f.c.reading(token,{value:120,unit:'lb',settled:true,source:'scale',observedAt:f.time()}),/closed/);
 const g=fixture();g.tick(7*86400000-1010);const t=g.c.scan('a','nfc');g.tick(1);g.c.reading(t,{value:120,unit:'lb',settled:true,source:'scale',observedAt:g.time()});g.tick(9);
 assert.throws(()=>g.c.snapshot(t,{evidenceId:'photo',capturedAt:g.time(),source:'camera',noticeAccepted:true}),/closed/);
});
test('director summary includes missing roster; isolates program, club and accepted receipts',()=>{
 const expected=[{clubId:'club',athleteId:'a',clubName:'Club',athleteName:'A'},{clubId:'club',athleteId:'b',athleteName:'B'},{clubId:'other',athleteId:'c',athleteName:'C'}];
 const record={programId:window.programId,windowId:window.id,clubId:'club',athleteId:'a',status:'submitted',submissionId:'s',receiptId:'r',weight:120,unit:'lb',capturedAt:new Date(start+1000).toISOString(),receivedAt:window.closesAt};
 const summary=summarizeWindow({window,expected,submissions:[record,record,{...record,programId:'other',athleteId:'b'},{...record,status:'queued',athleteId:'b'}],clubId:'club'});
 assert.deepEqual(summary.counts,{expected:3,submitted:0,late:1,missing:2});assert.equal(summary.rows.length,2);assert.equal(summary.rows[0].status,'late');assert.equal(summary.rows[1].status,'missing');
 assert.throws(()=>summarizeWindow({window,expected,submissions:[record,{...record,submissionId:'other'}]}),/Conflicting/);
});
test('CSV quotes names and neutralizes spreadsheet formulas',()=>{
 const csv=reportCsv([{clubName:'=HYPERLINK("x")',athleteName:'A, B',status:'missing'}]);assert.match(csv,/"'=HYPERLINK\(""x""\)"/);assert.match(csv,/"A, B"/);
});
