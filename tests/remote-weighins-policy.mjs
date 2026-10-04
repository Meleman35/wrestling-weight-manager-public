import test from 'node:test';
import assert from 'node:assert/strict';
import {eventCaptureWindow,remoteExpiresAt,REMOTE_RETENTION_MS} from '../src/remote-weighins-policy.mjs';
test('event captures cover previous and event local calendar days across DST',()=>{
 for(const [eventDate,hours] of [['2026-03-08',47],['2026-11-01',49],['2026-10-04',48]]){
  const w=eventCaptureWindow({eventDate,timeZone:'America/Denver'});
  assert.equal((Date.parse(w.closesAt)-Date.parse(w.opensAt))/3600000,hours);
 }
 assert.throws(()=>eventCaptureWindow({eventDate:'2026-02-30',timeZone:'America/Denver'}));
 assert.throws(()=>eventCaptureWindow({eventDate:'2026-10-04',timeZone:'bad/zone'}));
});
test('weight and photo share ten elapsed days from original capture, never upload time',()=>{
 const b={capturedAt:'2026-10-04T23:59:59Z',photoCapturedAt:'2026-10-05T00:00:10Z'};
 assert.equal(remoteExpiresAt(b),'2026-10-14T23:59:59.000Z');
 assert.equal(Date.parse(remoteExpiresAt(b))-Date.parse(b.capturedAt),REMOTE_RETENTION_MS);
 assert.equal(remoteExpiresAt({...b,receivedAt:'2026-10-06T00:00:00Z'}),remoteExpiresAt(b));
 assert.throws(()=>remoteExpiresAt({capturedAt:'invalid'}));
});
