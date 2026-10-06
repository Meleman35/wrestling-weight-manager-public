// Owner-approved first release: ordinary team scale/NFC tools stay in the app;
// nationwide remote reporting ships in a later update with its hosted services.
// Do not register the remote client or expose its unfinished reporting screen.
document.getElementById('remoteReportingBtn')?.remove();
document.getElementById('remoteReportingSheet')?.remove();
import {installSubscriptionApp} from '../billing-candidate/subscription-app.mjs';
window.WMSubscriptionPlans=installSubscriptionApp({
 button:document.getElementById('subscriptionPlansBtn'),root:document.getElementById('subscriptionPlansContent'),
 beforeOpen:()=>closeSheets(),show:()=>openSheet('subscriptionPlansSheet'),hide:()=>show('subscriptionPlansSheet',false),
 getSession:()=>session,getTeam:()=>activeTeam,
 unlocked:()=>!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)'),
 personal:()=>!!session?.user?.id&&!managedLogin&&!teamProfileChoice&&!teamProfileSelecting&&!teamLoginSigningOut,
 publishableKey:SUPABASE_KEY
});
// Module loading can finish after Clipboard has rendered its category proxies.
window.WMClipboard?.sync();
