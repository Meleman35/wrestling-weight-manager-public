import test from 'node:test';
import assert from 'node:assert/strict';
import {runAppleNotificationTest,validNotificationTestCall} from './apple-notification-test.mjs';
const token='test-token',notificationID='11111111-1111-4111-8111-111111111111';
test('operator actions reject arbitrary methods, request payloads and unsafe status tokens',()=>{
 for(const [action,input] of [['resolve','x'],['testRequest',{}],['testStatus','../secret'],['testStatus','a/b'],['testStatus','x'.repeat(513)],['testStatus',null]])assert.equal(validNotificationTestCall(action,input),false);
 assert.equal(validNotificationTestCall('testRequest',null),true);assert.equal(validNotificationTestCall('testStatus',token),true);
});
test('test request returns only a bounded token and selected API error numbers',async()=>{
 const apple={api:{requestTestNotification:async()=>({testNotificationToken:token,private:'hidden'})}};
 assert.deepEqual(await runAppleNotificationTest(apple,'testRequest',null),{state:'requested',testNotificationToken:token});
 apple.api.requestTestNotification=async()=>{throw {httpStatusCode:401,apiError:123,message:'private contents'};};
 assert.deepEqual(await runAppleNotificationTest(apple,'testRequest',null),{state:'apple_error',httpStatus:401,appleCode:123});
 apple.api.requestTestNotification=async()=>{throw Error('private transport diagnostics');};
 await assert.rejects(runAppleNotificationTest(apple,'testRequest',null),/Apple test unavailable/);
});
test('delivery status requires verified TEST evidence and reports unsuccessful attempts without claiming delivery',async()=>{
 let kind='test',sent=false;const apple={api:{getTestNotificationStatus:async value=>{assert.equal(value,token);return {signedPayload:'private.jws.value',sendAttempts:[{attemptDate:100,sendAttemptResult:sent?'SUCCESS':'UNSUCCESSFUL_HTTP_RESPONSE_CODE'}]};}},notificationTransaction:async value=>{assert.equal(value,'private.jws.value');return {kind,notificationID};}};
 let result=await runAppleNotificationTest(apple,'testStatus',token);assert.equal(result.verified,true);assert.equal(result.delivered,false);assert.equal(JSON.stringify(result).includes('private'),false);
 sent=true;result=await runAppleNotificationTest(apple,'testStatus',token);assert.equal(result.delivered,true);
 kind='purchase';await assert.rejects(runAppleNotificationTest(apple,'testStatus',token),/Expected verified TEST/);
 apple.notificationTransaction=async()=>{throw Error('invalid signature');};await assert.rejects(runAppleNotificationTest(apple,'testStatus',token),/invalid signature/);
});
