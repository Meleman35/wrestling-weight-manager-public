/* Enrolled erasure controller. Resume credentials authorize one immutable job. */
window.WMScopedDeletion=(()=>{
 'use strict';
 const PREFIX='wm-deletion-resume-v1:',jobs=new Map(),nativeCalls=new Map();
 const native=()=>!!window.webkit?.messageHandlers?.wmAccountDeletion;
 const nativeShell=()=>!!(window.wrestlingManagerNativeShellVersion||window.wrestlingManagerNativeLifecycle===true||window.webkit?.messageHandlers?.security);
 window.wrestlingManagerDeletionResponse=r=>{const p=nativeCalls.get(r.id);if(!p)return;clearTimeout(p.timer);nativeCalls.delete(r.id);r.ok?p.resolve(r.value):p.reject(Object.assign(Error(r.error||'Resume the saved deletion request.'),{code:r.code}));};
 function nativeCall(command,data={}){return new Promise((resolve,reject)=>{const id=crypto.randomUUID(),timer=setTimeout(()=>{nativeCalls.delete(id);reject(Error('The app has not confirmed the result. Resume this same request.'));},90000);nativeCalls.set(id,{resolve,reject,timer});try{window.webkit.messageHandlers.wmAccountDeletion.postMessage({id,command,...data});}catch(e){clearTimeout(timer);nativeCalls.delete(id);reject(e);}});}
 const digest=async text=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),x=>x.toString(16).padStart(2,'0')).join('');
 const actor=()=>session?.user?.id||null;
 const el=(tag,text)=>{const x=document.createElement(tag);x.textContent=text;return x;};
 function save(job){localStorage.setItem(PREFIX+job.requestId,JSON.stringify(job));}
 const errors={team_handoff_required:'Another confirmed administrator must accept the team before you delete your personal account.',organization_handoff_required:'Another confirmed administrator must accept the organization before you delete your personal account.',linked_teams_not_selected:'Select the linked teams in Delete all, or transfer them before deleting their organization.',not_enabled:'Deletion has not been enabled for this account.',already_in_progress:'A deletion request is already in progress. Resume that request first.'};
 async function call(body,token){
  const response=await fetch(SUPABASE_URL+'/functions/v1/scoped-deletion',{method:'POST',headers:{apikey:SUPABASE_KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
  const data=await response.json();if(!response.ok)throw Object.assign(Error(errors[data.error]||'The result could not be confirmed. Reconnect and resume this same request.'),{code:data.error});return data;
 }
 const payload=job=>({action:'begin',kind:job.kind,teamIds:job.teamIds,organizationIds:job.organizationIds,confirmation:'delete',requestId:job.requestId,receipt:job.receipt});
 const oldNativeMessage='Use Safari for this deletion test. This native build does not yet support verified cleanup of files saved on the phone.';
 async function start(job,token){
  if(nativeShell()&&!native())throw Error(oldNativeMessage);
  if(!native())return call(payload(job),token);
  // Recheck server enrollment for each new native intake, including a retry
  // whose original request never reached the server. Recovery does not require
  // a live account or enrollment: the original receipt must survive sign-out.
  const {data,error}=await client.rpc('account_deletion_scope_preflight');
  if(actor()!==job.actorId||session?.access_token!==token||managedLogin)throw Object.assign(Error('The signed-in account changed. Review deletion again.'),{code:'native_not_started'});
  if(error||data?.enabled!==true||data.subject_id!==job.actorId||data.deletion_enabled!==true||data.actions?.[job.kind]!==true)throw Object.assign(Error(errors.not_enabled),{code:'not_enabled'});
  const result=await nativeCall('begin',{job,accessToken:token});
  if(result.rejected)throw Object.assign(Error(errors[result.error]||'The server did not accept this deletion request.'),{code:result.error});
  return result;
 }
 async function recover(job){
  if(nativeShell()&&!native())throw Error(oldNativeMessage);
  if(!native())return call({action:'recover',requestId:job.requestId,receipt:job.receipt});
  const result=await nativeCall('recover',{requestId:job.requestId});
  if(result.error)throw Object.assign(Error('Resume with the account that started this deletion request.'),{code:result.error});
  return result;
 }
 function panel(job){
  const old=jobs.get(job.requestId);if(old)return old;
  const box=el('section','');box.className='feature-card';box.style.cssText='position:fixed;inset:auto 16px 16px;z-index:100000;max-width:540px;margin:auto;padding:20px;background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:0 12px 50px #0006';
  box.setAttribute('aria-label','Deletion progress');
  const heading=el('h2','Deletion status'),status=el('p','Checking this request…'),button=el('button','Resume deletion');button.className='wide secondary';status.setAttribute('role','status');status.setAttribute('aria-live','polite');
  const entry={box,status,button,busy:false};button.onclick=()=>resume(job);box.append(heading,status,button);document.body.append(box);jobs.set(job.requestId,entry);return entry;
 }
 async function clearWebAccount(job,proof){
  // Stop current-account writers before replacing only this account's two slots.
  if(actor()===job.actorId){window.WMMatch?.close();window.WMOffline?.lock();window.WMChatDrafts?.reset();await window.WMChatDrafts?.flush();window.WMQuickSignIn?.signOut();}
  if(!window.WMAccountDeletionDevice)throw Error('The server deletion is complete, but this browser needs to reload before local cleanup can finish.');
  await window.WMAccountDeletionDevice.clearOfflineAccount({subjectId:job.actorId,requestId:job.requestId});
  const id=job.actorId;
  const prefixes=['wm-match-draft-v1:'+id+':','wm-roster-sort:'+id+':','wm-crew-device:'+id+':','wm_travel_destination_v1:'+id+':','wm_bulletin_theme_'+id+'_'];
  const exact=['wm_ui_layout_'+id,'wm_pinned_threads_'+id,'wm-home-organization:'+id,'wm.profile-pin.v1:'+id];
  for(const key of Object.keys(localStorage))if(exact.includes(key)||prefixes.some(p=>key.startsWith(p))||new RegExp('^wm_nav_seen_[a-z_]+_'+id+'_').test(key))localStorage.removeItem(key);
  for(const key of ['wm.offline.active.v1','wm.profile-pin.active','wm_kiosk_profile_owner'])if(localStorage.getItem(key)===id)localStorage.removeItem(key);
  const emailHash=proof?.loginEmailHash||job.loginEmailHash;
  if(emailHash&&await digest((localStorage.getItem('wm_login_email')||'').trim().toLowerCase())===emailHash){localStorage.removeItem('wm_login_email');if($('email')&&await digest($('email').value.trim().toLowerCase())===emailHash)$('email').value='';}
  if(actor()===id){const signedOut=await client.auth.signOut({scope:'local'});if(signedOut?.error)throw Error('The account is deleted, but local sign-out needs another attempt. Resume this request.');closeSheets();show('appView',false);show('setupView',false);show('authView',true);}
  // A stale persisted session can remain after a SIGNED_OUT event. Remove only
  // this project's exact token whose embedded user matches the completed subject.
  const authKey='sb-vfocpoyexnjsjpxhhyqr-auth-token';
  for(const storage of [localStorage,sessionStorage]){let value;try{value=JSON.parse(storage.getItem(authKey)||'null');}catch{}if(value?.user?.id===id)storage.removeItem(authKey);}

 }
 async function resume(job){
  const view=panel(job);if(view.busy)return;view.busy=true;view.button.disabled=true;
  try{
   let result;
   try{result=await recover(job);}
   catch(error){
    if(!['request_not_found','native_request_not_found'].includes(error.code))throw error;
    if(actor()!==job.actorId||!session?.access_token)throw Error('Sign in with the account that started this request to retry it.');
    if(!['personal','team','organization','all'].includes(job.kind)||!Array.isArray(job.teamIds)||!Array.isArray(job.organizationIds))throw Error('This saved request needs review before it can be restarted.');
    // The server confirmed that no request with this receipt exists. Resubmit
    // the original confirmed scope and nonce, never the current UI selection.
    result=await start(job,session.access_token);
   }
   if(result.state==='completed'){
    if(result.personal!==job.personal||result.subjectHash!==await digest(job.actorId))throw Error('The deletion receipt did not match this account.');
    if(native()&&result.nativeComplete!==true)throw Error('The server deletion is complete, but app cleanup is still pending. Resume this request.');
    if(job.personal)await clearWebAccount(job,result);
    else if(actor()===job.actorId)await refreshAccountView();
    if(native())await nativeCall('acknowledge',{requestId:job.requestId});
    localStorage.removeItem(PREFIX+job.requestId);
    view.status.textContent=job.personal?(native()?'Your account and selected server records have been deleted. This app removed the account’s saved sign-in, profile PIN, reviewed local recordings and account drafts. Exported copies in Photos or Files remain outside the app.':'Your server account, selected records and files have been deleted. You are signed out on this browser. Downloaded copies and files held by the native app require their own cleanup.'):'The selected workspace has been deleted. Personal accounts and profiles remain.';
    view.button.textContent='Close';view.button.onclick=()=>{view.box.remove();jobs.delete(job.requestId);if(job.personal&&!actor())location.reload();};
   }else if(result.state==='blocked'){
    localStorage.removeItem(PREFIX+job.requestId);
    view.status.textContent='Nothing was deleted. This selection includes a profile, shared record or file that needs further review to preserve other people’s information.';
    view.button.textContent='Close';view.button.onclick=()=>{view.box.remove();jobs.delete(job.requestId);};
   }else{
    view.status.textContent='Deletion is in progress. You can resume this same request after a connection loss. Completion has not been confirmed yet.';
    setTimeout(()=>{if(jobs.has(job.requestId))void resume(job);},5000);
   }
  }catch(error){view.status.textContent=error.message||'Reconnect and resume this same request.';}
  finally{view.busy=false;view.button.disabled=false;}
 }
 async function begin(choice){
  if(nativeShell()&&!native())throw Error(oldNativeMessage);
  const actorId=actor(),token=session?.access_token;if(!actorId||!token||managedLogin)throw Error('Sign in with your personal account.');
  if(Object.keys(localStorage).some(k=>k.startsWith(PREFIX)&&JSON.parse(localStorage.getItem(k)||'null')?.actorId===actorId))throw Error('Resume your existing deletion request first.');
  const personal=['personal','all'].includes(choice.kind);
  const targets=choice.kind==='all'?choice.targets:choice.kind==='personal'?[]:[choice];
  const job={requestId:crypto.randomUUID(),actorId,personal,kind:choice.kind,teamIds:targets.filter(x=>x.targetKind==='team').map(x=>x.id),organizationIds:targets.filter(x=>x.targetKind==='organization').map(x=>x.id),receipt:Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('')};
  if(session?.user?.email)job.loginEmailHash=await digest(session.user.email.trim().toLowerCase());
  // Persist before sending. A lost response after server acceptance must not
  // create a second request or depend on the soon-to-be-deleted Auth session.
  if(actor()!==actorId)throw Error('The signed-in account changed. Review deletion again.');
  save(job);
  try{
   await start(job,token);
  }catch(error){if(errors[error.code]||['request_not_accepted','sign_in_required','invalid_request','native_not_started'].includes(error.code)){localStorage.removeItem(PREFIX+job.requestId);throw error;}panel(job).status.textContent=error.message;return;}
  void resume(job);
 }
 for(const key of Object.keys(localStorage))if(key.startsWith(PREFIX))try{const job=JSON.parse(localStorage.getItem(key));if(job?.requestId&&job.actorId&&/^[a-f0-9]{64}$/.test(job.receipt))setTimeout(()=>void resume(job),1000);}catch{}
 if(native())setTimeout(async()=>{try{const saved=await nativeCall('pending');for(const job of saved.jobs||[]){if(!job?.requestId||!job.actorId||!/^[a-f0-9]{64}$/.test(job.receipt))continue;save(job);if(!jobs.has(job.requestId))void resume(job);}}catch{}},1500);
 return {begin};
})();
