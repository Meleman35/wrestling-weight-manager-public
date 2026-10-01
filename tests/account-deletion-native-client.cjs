'use strict';
// Executes the actual controller with a simulated native transport. Apple SDK,
// Keychain and on-device integration remain separate release gates.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto,createHash}=require('node:crypto');
const A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222',J='44444444-4444-4444-8444-444444444444';
const digest=x=>createHash('sha256').update(x).digest('hex');
const source=fs.readFileSync(require('node:path').join(__dirname,'../src/scoped-deletion-client.js'),'utf8');
function storage(){const target={};Object.defineProperties(target,{getItem:{value:k=>Object.hasOwn(target,k)?target[k]:null},setItem:{value:(k,v)=>{target[k]=String(v);}},removeItem:{value:k=>{delete target[k];}}});return target;}
function setup({personal=true,complete=true,wrong=false,failAck=false,cancel=false,lost=false,legacy=false,admitted=true,wrongSubject=false,gateError=false,switchDuringGate=false}={}){
 const elements=[],calls=[],timers=[],removed=[],localStorage=storage(),sessionStorage=storage();let signouts=0,refreshes=0,matchClosed=0,started;
 const element=tag=>{const el={tag,children:[],style:{},textContent:'',setAttribute(){},append(...args){this.children.push(...args);},remove(){this.removed=true;}};elements.push(el);return el;};
 const context={console,crypto:webcrypto,TextEncoder,Uint8Array,Error,Map,Set,JSON,Object,Array,RegExp,localStorage,sessionStorage,
  session:{user:{id:A,email:'test@example.invalid'},access_token:'fake-token'},managedLogin:null,
  setTimeout(fn,ms){timers.push({fn,ms});return timers.length;},clearTimeout(){},document:{createElement:element,body:{append(){}}},location:{reload(){}},
  $:()=>null,closeSheets(){},show(){},refreshAccountView:async()=>{refreshes++;},
  client:{rpc:async name=>{assert.equal(name,'account_deletion_scope_preflight');if(switchDuringGate)context.session={user:{id:B},access_token:'other'};return {data:{enabled:admitted,deletion_enabled:admitted,subject_id:wrongSubject?B:A,actions:{personal:true,team:true,organization:true,all:true}},error:gateError?{message:'unavailable'}:null};},auth:{signOut:async()=>{signouts++;context.session=null;return {error:null};}}},fetch:async()=>{throw Error('Native must own transport');}
 };
 context.window=context;context.wrestlingManagerNativeShellVersion='test';
 context.WMMatch={close(){matchClosed++;localStorage.setItem('wm-match-draft-v1:'+A+':team','last pause');}};
 context.WMOffline={lock(){}};context.WMChatDrafts={reset(){},async flush(){}};context.WMQuickSignIn={signOut(){}};
 context.WMAccountDeletionDevice={async clearOfflineAccount({subjectId}){removed.push(subjectId);}};
 context.webkit={messageHandlers:legacy?{security:{}}:{wmAccountDeletion:{postMessage(msg){
  calls.push(msg);queueMicrotask(()=>{
   const send=value=>context.wrestlingManagerDeletionResponse({id:msg.id,ok:true,value});
   if(msg.command==='begin'){
    started=msg.job;
    if(cancel)return context.wrestlingManagerDeletionResponse({id:msg.id,ok:false,error:'Deletion cancelled.',code:'native_not_started'});
    if(lost){lost=false;return context.wrestlingManagerDeletionResponse({id:msg.id,ok:false,error:'Connection lost.'});}
    return send({id:J,state:'planning'});
   }
   if(msg.command==='recover')return send({id:J,state:'completed',personal,subjectHash:digest(wrong?B:A),nativeComplete:complete,loginEmailHash:digest('test@example.invalid')});
   if(msg.command==='acknowledge'&&failAck){failAck=false;return context.wrestlingManagerDeletionResponse({id:msg.id,ok:false,error:'Acknowledgement interrupted.'});}
   if(msg.command==='pending')return send({jobs:started?[started]:[]});
   send({acknowledged:true});
  });
 }}}};
 vm.createContext(context);vm.runInContext(source,context);
 return {context,calls,elements,removed,timers,localStorage,sessionStorage,get signouts(){return signouts;},get refreshes(){return refreshes;},get matchClosed(){return matchClosed;},resume:()=>elements.find(e=>e.tag==='button').onclick()};
}
const settle=async()=>{for(let i=0;i<20;i++)await new Promise(r=>setTimeout(r,2));};
const pending=x=>Object.keys(x.localStorage).filter(k=>k.startsWith('wm-deletion-resume-v1:'));
(async()=>{
 const passed=[];
 let x=setup();for(const id of [A,B])for(const key of ['wm-match-draft-v1:'+id+':team','wm-crew-device:'+id+':room','wm_ui_layout_'+id,'wm.profile-pin.v1:'+id,'wm_nav_seen_schedule_'+id+'_team','wm_travel_destination_v1:'+id+':team'])x.localStorage.setItem(key,'keep');
 x.localStorage.setItem('wm_login_email','test@example.invalid');x.sessionStorage.setItem('sb-vfocpoyexnjsjpxhhyqr-auth-token',JSON.stringify({user:{id:A}}));
 await x.context.WMScopedDeletion.begin({kind:'personal'});await settle();
 assert.deepEqual(x.calls.map(c=>c.command),['begin','recover','acknowledge']);assert.equal(x.calls[0].accessToken,'fake-token');assert.equal(x.calls[0].job.actorId,A);
 assert.equal(x.signouts,1);assert.equal(x.matchClosed,1);assert.deepEqual(x.removed,[A]);assert.equal(pending(x).length,0);
 assert.equal(Object.keys(x.localStorage).some(k=>k.includes(A)),false);assert.equal(Object.keys(x.localStorage).filter(k=>k.includes(B)).length,6);assert.equal(x.localStorage.getItem('wm_login_email'),null);assert.equal(x.sessionStorage.getItem('sb-vfocpoyexnjsjpxhhyqr-auth-token'),null);
 passed.push('Native verified personal completion closes writers, removes only matched account data, signs out and acknowledges after web cleanup');
 x=setup({wrong:true});await x.context.WMScopedDeletion.begin({kind:'personal'});await settle();assert.equal(x.signouts,0);assert.equal(x.removed.length,0);assert.equal(pending(x).length,1);assert.equal(x.calls.some(c=>c.command==='acknowledge'),false);passed.push('Mismatched native completion cannot erase browser data or clear its receipt');
 x=setup({complete:false});await x.context.WMScopedDeletion.begin({kind:'personal'});await settle();assert.equal(x.signouts,0);assert.equal(x.removed.length,0);assert.equal(pending(x).length,1);passed.push('Server completion without native cleanup confirmation remains pending');
 x=setup({personal:false});await x.context.WMScopedDeletion.begin({kind:'team',targetKind:'team',id:B});await settle();assert.equal(x.signouts,0);assert.equal(x.removed.length,0);assert.equal(x.refreshes,1);passed.push('Workspace deletion preserves sign-in and local personal data');
 x=setup({cancel:true});await assert.rejects(()=>x.context.WMScopedDeletion.begin({kind:'personal'}),/cancelled/);assert.equal(pending(x).length,0);assert.equal(x.calls.length,1);passed.push('Native cancellation before intake removes the browser intent without attempting deletion');
 x=setup({lost:true});await x.context.WMScopedDeletion.begin({kind:'personal'});assert.equal(pending(x).length,1);await x.resume();await settle();assert.equal(x.calls.filter(c=>c.command==='begin').length,1);assert.equal(pending(x).length,0);passed.push('Lost native begin response recovers the same immutable request');
 x=setup({failAck:true});await x.context.WMScopedDeletion.begin({kind:'personal'});await settle();assert.equal(pending(x).length,1);await x.resume();await settle();assert.equal(x.signouts,1);assert.equal(pending(x).length,0);passed.push('Interrupted acknowledgement resumes idempotently after sign-out');
 x=setup({lost:true});await x.context.WMScopedDeletion.begin({kind:'personal'});x.context.session={user:{id:B},access_token:'other'};x.localStorage.setItem('wm_login_email','other@example.invalid');x.sessionStorage.setItem('sb-vfocpoyexnjsjpxhhyqr-auth-token',JSON.stringify({user:{id:B}}));await x.resume();await settle();assert.equal(x.signouts,0);assert.equal(x.matchClosed,0);assert.equal(x.localStorage.getItem('wm_login_email'),'other@example.invalid');assert.equal(JSON.parse(x.sessionStorage.getItem('sb-vfocpoyexnjsjpxhhyqr-auth-token')).user.id,B);passed.push('Account switching preserves the other account session, email hint and active scoreboard');
 x=setup({legacy:true});await assert.rejects(()=>x.context.WMScopedDeletion.begin({kind:'personal'}),/Use Safari/);assert.equal(pending(x).length,0);passed.push('Older native builds remain blocked before any request');
 for(const option of [{admitted:false},{wrongSubject:true},{gateError:true}]){x=setup(option);await assert.rejects(()=>x.context.WMScopedDeletion.begin({kind:'personal'}),/not been enabled/);assert.equal(pending(x).length,0);assert.equal(x.calls.length,0);}passed.push('Unenrolled accounts, mismatched subjects and failed preflights cannot call native intake');
 x=setup({switchDuringGate:true});await assert.rejects(()=>x.context.WMScopedDeletion.begin({kind:'personal'}),/account changed/);assert.equal(pending(x).length,0);assert.equal(x.calls.length,0);passed.push('Account changes during preflight cannot start native deletion');
 x=setup();x.context.client.rpc=async()=>({data:{enabled:true,deletion_enabled:true,subject_id:A,actions:{personal:false}},error:null});await assert.rejects(()=>x.context.WMScopedDeletion.begin({kind:'personal'}),/not been enabled/);assert.equal(x.calls.length,0);passed.push('The chosen scope requires its own current server capability');
 x=setup({lost:true});await x.context.WMScopedDeletion.begin({kind:'personal'});x.context.session=null;x.context.client.rpc=async()=>{throw Error('Recovery must use its receipt, not enrollment');};await x.resume();await settle();assert.equal(pending(x).length,0);assert.deepEqual(x.removed,[A]);passed.push('Accepted deletion resumes after sign-out without requiring enrollment or a live account');
 x=setup({lost:true});await x.context.WMScopedDeletion.begin({kind:'personal'});delete x.context.webkit.messageHandlers.wmAccountDeletion;await x.resume();await settle();assert.equal(pending(x).length,1);assert.equal(x.removed.length,0);assert.match(x.elements.find(e=>e.tag==='p').textContent,/Use Safari/);passed.push('Recovery in an older native shell cannot fall back to browser-only cleanup');
 fs.writeFileSync(require('node:path').join(__dirname,'../validation/account-deletion-native-client.json'),JSON.stringify({passed,transport:'simulated native bridge',appleSDKTested:false},null,2));for(const p of passed)console.log('PASS',p);
})().catch(e=>{console.error(e);process.exit(1);});
