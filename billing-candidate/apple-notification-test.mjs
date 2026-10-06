// Private operator diagnostics only. These operations cannot create purchases
// or entitlements. The public notification/evidence adapters do not expose them.
export const validTestToken=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,512}$/.test(value);
export function validNotificationTestCall(action,input){
 return action==='testRequest'?input===null:action==='testStatus'&&validTestToken(input);
}
async function appleCall(callback){
 try{return {value:await callback()};}
 catch(error){
  const status=error?.httpStatusCode;
  if(!Number.isInteger(status)||status<400||status>599)throw Error('Apple test unavailable');
  return {error:{state:'apple_error',httpStatus:status,appleCode:Number.isSafeInteger(error.apiError)?error.apiError:null}};
 }
}
export async function runAppleNotificationTest(apple,action,input){
 if(!validNotificationTestCall(action,input))throw Error('Invalid Apple test operation');
 const call=await appleCall(()=>action==='testRequest'?apple.api.requestTestNotification():apple.api.getTestNotificationStatus(input));
 if(call.error)return call.error;
 if(action==='testRequest'){
  if(!validTestToken(call.value?.testNotificationToken))throw Error('Invalid Apple test response');
  return {state:'requested',testNotificationToken:call.value.testNotificationToken};
 }
 // Verify the actual returned Apple JWS. No raw signed payload leaves this host.
 const result=await apple.notificationTransaction(call.value?.signedPayload);
 if(result?.kind!=='test')throw Error('Expected verified TEST notification');
 const attempts=call.value?.sendAttempts??[];
 if(!Array.isArray(attempts)||attempts.length>6||attempts.some(a=>!Number.isSafeInteger(a?.attemptDate)||a.attemptDate<0||typeof a.sendAttemptResult!=='string'||!/^[A-Z_]{1,80}$/.test(a.sendAttemptResult)))throw Error('Invalid Apple delivery status');
 return {state:'checked',verified:true,notificationID:result.notificationID,
  delivered:attempts.some(a=>a.sendAttemptResult==='SUCCESS'),
  attempts:attempts.map(a=>({at:a.attemptDate,result:a.sendAttemptResult}))};
}
