import {installRemoteReportingApp} from './remote-weighins-app.mjs';
window.WMRemoteReporting=installRemoteReportingApp({
  enabled:false, // Turn on with the reviewed service deployment, not independently.
  button:document.getElementById('remoteReportingBtn'),root:document.getElementById('remoteReportingContent'),
  beforeOpen:()=>closeSheets(),show:()=>openSheet('remoteReportingSheet'),hide:()=>show('remoteReportingSheet',false),
  getSession:async()=>{const {data,error}=await client.auth.getSession();if(error)throw error;return data.session},
  unlocked:()=>!securityState.appLockEnabled||securityUnlockedThisLaunch,
  personal:()=>!!session?.user?.id&&!managedLogin,publishableKey:SUPABASE_KEY
});
import {installSubscriptionApp} from '../billing-candidate/subscription-app.mjs';
window.WMSubscriptionPlans=installSubscriptionApp({
 button:document.getElementById('subscriptionPlansBtn'),root:document.getElementById('subscriptionPlansContent'),
 beforeOpen:()=>closeSheets(),show:()=>openSheet('subscriptionPlansSheet'),hide:()=>show('subscriptionPlansSheet',false),
 getSession:()=>session,getTeam:()=>activeTeam,
 unlocked:()=>!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)'),
 personal:()=>!!session?.user?.id&&!managedLogin&&!teamProfileChoice&&!teamProfileSelecting&&!teamLoginSigningOut,
 publishableKey:SUPABASE_KEY
});
