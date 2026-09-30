/* Enrolled erasure controller. Resume credentials authorize one immutable job. */
window.WMScopedDeletion=(()=>{
 'use strict';
 const PREFIX='wm-deletion-resume-v1:',jobs=new Map();
 const digest=async text=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),x=>x.toString(16).padStart(2,'0')).join('');
 const actor=()=>session?.user?.id||null;
 const el=(tag,text)=>{const x=document.createElement(tag);x.textContent=text;return x;};
 function save(job){localStorage.setItem(PREFIX+job.requestId,JSON.stringify(job));}
 const errors={team_handoff_required:'Another confirmed administrator must accept the team before you delete your personal account.',organization_handoff_required:'Another confirmed administrator must accept the organization before you delete your personal account.',linked_teams_not_selected:'Select the linked teams in Delete all, or transfer them before deleting their organization.',not_enabled:'Deletion has not been enabled for this account.',already_in_progress:'A deletion request is already in progress. Resume that request first.'};
 async function call(body,token){
  const response=await fetch(SUPABASE_URL+'/functions/v1/scoped-deletion',{method:'POST',headers:{apikey:SUPABASE_KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
  const data=await response.json();if(!response.ok)throw Object.assign(Error(errors[data.error]||'The result could not be confirmed. Reconnect and resume this same request.'),{code:data.error});return data;
 }
 function panel(job){
  const old=jobs.get(job.requestId);if(old)return old;
  const box=el('section','');box.className='feature-card';box.style.cssText='position:fixed;inset:auto 16px 16px;z-index:100000;max-width:540px;margin:auto;padding:20px;background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:0 12px 50px #0006';
  box.setAttribute('aria-label','Deletion progress');
  const heading=el('h2','Deletion status'),status=el('p','Checking this request…'),button=el('button','Resume deletion');button.className='wide secondary';status.setAttribute('role','status');status.setAttribute('aria-live','polite');
  const entry={box,status,button,busy:false};button.onclick=()=>resume(job);box.append(heading,status,button);document.body.append(box);jobs.set(job.requestId,entry);return entry;
 }
 async function clearWebAccount(job){
  // Stop current-account writers before replacing only this account's two slots.
  if(actor()===job.actorId){window.WMOffline?.lock();window.WMChatDrafts?.reset();await window.WMChatDrafts?.flush();window.WMQuickSignIn?.signOut();}
  if(window.WMAccountDeletionDevice)await window.WMAccountDeletionDevice.clearOfflineAccount({subjectId:job.actorId,requestId:job.requestId});
  const prefixes=['wm-match-draft-v1:'+job.actorId+':','wm-roster-sort:'+job.actorId+':'];
  for(const key of Object.keys(localStorage))if(prefixes.some(p=>key.startsWith(p)))localStorage.removeItem(key);
  if(actor()===job.actorId){await client.auth.signOut({scope:'local'});closeSheets();show('appView',false);show('setupView',false);show('authView',true);}
 }
 async function resume(job){
  const view=panel(job);if(view.busy)return;view.busy=true;view.button.disabled=true;
  try{
   const result=await call({action:'recover',requestId:job.requestId,receipt:job.receipt});
   if(result.state==='completed'){
    if(result.personal!==job.personal||result.subjectHash!==await digest(job.actorId))throw Error('The deletion receipt did not match this account.');
    if(job.personal)await clearWebAccount(job);
    else if(actor()===job.actorId)await refreshAccountView();
    localStorage.removeItem(PREFIX+job.requestId);
    view.status.textContent=job.personal?'Your server account, selected records and files have been deleted. You are signed out on this browser. Downloaded copies and files held by the native app require their own cleanup.':'The selected workspace has been deleted. Personal accounts and profiles remain.';
    view.button.textContent='Close';view.button.onclick=()=>{view.box.remove();jobs.delete(job.requestId);};
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
  if(typeof inNativeApp==='function'&&inNativeApp())throw Error('Use Safari for this deletion test. This native build does not yet support verified cleanup of files saved on the phone.');
  const actorId=actor(),token=session?.access_token;if(!actorId||!token||managedLogin)throw Error('Sign in with your personal account.');
  if(Object.keys(localStorage).some(k=>k.startsWith(PREFIX)&&JSON.parse(localStorage.getItem(k)||'null')?.actorId===actorId))throw Error('Resume your existing deletion request first.');
  const personal=['personal','all'].includes(choice.kind);
  const targets=choice.kind==='all'?choice.targets:choice.kind==='personal'?[]:[choice];
  const job={requestId:crypto.randomUUID(),actorId,personal,receipt:Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('')};
  // Persist before sending. A lost response after server acceptance must not
  // create a second request or depend on the soon-to-be-deleted Auth session.
  save(job);
  try{
   await call({action:'begin',kind:choice.kind,teamIds:targets.filter(x=>x.targetKind==='team').map(x=>x.id),organizationIds:targets.filter(x=>x.targetKind==='organization').map(x=>x.id),confirmation:'delete',requestId:job.requestId,receipt:job.receipt},token);
  }catch(error){if(errors[error.code]||['request_not_accepted','sign_in_required','invalid_request'].includes(error.code)){localStorage.removeItem(PREFIX+job.requestId);throw error;}panel(job).status.textContent=error.message;return;}
  void resume(job);
 }
 for(const key of Object.keys(localStorage))if(key.startsWith(PREFIX))try{const job=JSON.parse(localStorage.getItem(key));if(job?.requestId&&job.actorId&&/^[a-f0-9]{64}$/.test(job.receipt))setTimeout(()=>void resume(job),1000);}catch{}
 return {begin};
})();
