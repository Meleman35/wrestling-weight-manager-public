/* Enrolled account inventory and confirmation preview. No erasure action. */
window.WMDeletionPhoneTest=(()=>{
 'use strict';
 const fields=[['account_photos','Account profile photos'],['wrestling_profile_photos','Wrestling profile photos'],['messages','Messages sent'],['message_attachments','Message attachments uploaded'],['team_posts','Team posts written'],['post_attachments','Attachments on those posts'],['uploaded_objects','Stored files uploaded'],['teams','Team memberships'],['teams_needing_handoff','Teams needing an administrator handoff'],['guardian_links','Guardian links'],['organization_roles','Organization roles']];
 let epoch=0,card=null,admitted=false,dialog=null;
 const actor=()=>session?.user?.id&&!managedLogin?session.user.id:null;
 const visible=()=>!document.hidden&&document.getElementById('appLockOverlay')?.classList.contains('hidden')&&document.getElementById('accountSheet')&&!document.getElementById('accountSheet').classList.contains('hidden');
 function closeConfirmation(){if(dialog){dialog.close();dialog.remove();dialog=null;}}
 function reset(){++epoch;closeConfirmation();card?.remove();card=null;admitted=false;}
 function element(tag,text,cls){const e=document.createElement(tag);if(text)e.textContent=text;if(cls)e.className=cls;return e;}
 const style=element('style');style.textContent=`
  #deletionPhoneTestCard>summary{cursor:pointer;color:var(--danger);font-weight:700;padding:4px 0;min-height:32px}
  #deletionPhoneTestCard[open]>summary{margin-bottom:12px}
  #deletionPhoneTestCard .deletion-action,#deletionConfirmDialog .deletion-action{background:var(--danger);color:#fff;border-color:var(--danger);margin-top:12px}
  #deletionConfirmDialog{box-sizing:border-box;width:calc(100% - 32px);max-width:440px;max-height:calc(100dvh - 32px);overflow:auto;margin:auto;border:1px solid var(--line);border-radius:18px;padding:22px;background:var(--card);color:var(--ink)}
  #deletionConfirmDialog::backdrop{background:rgba(0,0,0,.55)}
  #deletionConfirmDialog h2{margin:0 0 12px}#deletionConfirmDialog p{line-height:1.5}
  #deletionConfirmDialog input{font-size:16px}#deletionConfirmDialog button{min-height:44px}
  #deletionConfirmDialog .deletion-unavailable{padding:12px;border:1px solid var(--line);border-radius:10px;background:var(--soft)}
 `;document.head.append(style);
 function mount(){
  if(card)return card;
  card=element('details',null,'feature-card');card.id='deletionPhoneTestCard';
  card.addEventListener('toggle',()=>{if(!card?.open)closeConfirmation();});
  document.getElementById('signOutBtn').after(card);return card;
 }
 function heading(box){box.append(element('summary','Account deletion'));box.append(element('p','Deletion is not available yet. You can review your stored data and preview the confirmation below.','fine'));}
 function refreshButton(box){const b=element('button','Refresh stored data','secondary wide');b.type='button';b.onclick=()=>refresh();box.append(b);}
 function confirmation(opener,counts){
  if(!admitted||!actor()||!visible())return;
  closeConfirmation();
  const uid=actor(),token=session.access_token,g=epoch;
  const current=()=>g===epoch&&uid===actor()&&token===session?.access_token&&visible();
  dialog=element('dialog');dialog.id='deletionConfirmDialog';dialog.setAttribute('aria-labelledby','deletionConfirmTitle');dialog.setAttribute('aria-describedby','deletionConfirmWarning deletionConfirmUnavailable');
  const title=element('h2','Delete Account');title.id='deletionConfirmTitle';dialog.append(title);
  const unavailable=element('p','Confirmation preview: account deletion is not available yet. Nothing will be deleted.','deletion-unavailable');unavailable.id='deletionConfirmUnavailable';dialog.append(unavailable);
  const warning=element('p','Account deletion is permanent. Once completed, you will lose sign-in access to this account. Your personal data, including photos and messages, must be reviewed for removal. Shared team, organization and athlete records need separate handling. Copies already downloaded by other people are not removed.');warning.id='deletionConfirmWarning';dialog.append(warning);
  if(counts.teams_needing_handoff)dialog.append(element('p','You are the only administrator for a team. Arrange another administrator or review closing the team before deletion.','fine'));
  if(counts.organization_roles)dialog.append(element('p','Your organization roles also need to be reviewed before deletion.','fine'));
  const form=element('form');form.noValidate=true;
  const label=element('label','Type delete to confirm that you understand this warning, then press Enter or Confirm deletion.');label.htmlFor='deletionConfirmInput';
  const input=element('input');input.id='deletionConfirmInput';input.type='text';input.autocomplete='off';input.setAttribute('autocapitalize','none');input.setAttribute('autocorrect','off');input.spellcheck=false;input.setAttribute('enterkeyhint','done');input.setAttribute('aria-describedby','deletionConfirmStatus');
  const status=element('p',null,'fine');status.id='deletionConfirmStatus';status.setAttribute('role','status');status.setAttribute('aria-live','polite');
  const cancel=element('button','Cancel','wide secondary');cancel.type='button';cancel.onclick=()=>{closeConfirmation();if(current())opener.focus();};
  const confirm=element('button','Confirm deletion','wide deletion-action');confirm.type='submit';confirm.disabled=true;
  input.oninput=()=>{confirm.disabled=input.value!=='delete';status.textContent='';};
  form.onsubmit=event=>{
   event.preventDefault();if(!current()){reset();return;}
   if(input.value!=='delete'){status.textContent='Type delete exactly to confirm that you understand.';input.focus();return;}
   // Preview only: typing the phrase never creates a deletion request or consent record.
   status.textContent='Account deletion is not available yet. Nothing has been deleted or scheduled for deletion.';
   input.value='';confirm.disabled=true;
  };
  form.append(label,input,status,cancel,confirm);dialog.append(form);
  dialog.addEventListener('cancel',event=>{event.preventDefault();closeConfirmation();if(current())opener.focus();});
  document.body.append(dialog);dialog.showModal();input.focus();
 }
 function deletionButton(box,counts){const b=element('button','Delete Account','wide deletion-action');b.type='button';b.onclick=()=>confirmation(b,counts);box.append(b);}
 async function refresh(){
  const uid=actor();if(!uid||!visible()){reset();return;}
  closeConfirmation();const g=++epoch,token=session.access_token;
  const valid=()=>epoch===g&&actor()===uid&&session?.access_token===token&&visible();
  const wasAdmitted=admitted;
  if(wasAdmitted){const box=mount();box.replaceChildren();heading(box);box.append(element('p','Checking stored data…','fine'));}
  try{
   const {data,error}=await client.rpc('account_deletion_phone_preflight');
   if(!valid())return;
   if(error)throw Error('unavailable');
   if(data?.enabled!==true){reset();return;}
   if(data.deletion_enabled!==false||data.subject_id!==uid||!Number.isFinite(Date.parse(data.checked_at))||fields.some(([key])=>!Number.isSafeInteger(data.counts?.[key])||data.counts[key]<0))throw Error('invalid response');
   admitted=true;const box=mount();box.replaceChildren();heading(box);
   box.append(element('p','Review the data linked to your account. Refresh after adding photos or sending messages.','fine'));
   const list=element('dl');list.style.cssText='display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px 16px;margin:16px 0';
   for(const [key,label] of fields){list.append(element('dt',label));const n=element('dd',String(data.counts[key]));n.style.margin='0';n.dataset.count=key;list.append(n);}box.append(list);
   if(data.counts.teams_needing_handoff)box.append(element('p','Before deletion: arrange another administrator or review closing your test team. Deleting your account must not leave a team without an administrator.','fine'));
   box.append(element('p','Counts can overlap and include retained records. Linked team and child records need a separate review. Files saved only on this phone are not counted.','fine'));
   box.append(element('p','Last checked '+new Date(data.checked_at).toLocaleString(),'fine'));
   refreshButton(box);
   deletionButton(box,data.counts);
  }catch{
   if(!valid())return;
   if(!wasAdmitted){reset();return;}
   const box=mount();box.replaceChildren();heading(box);box.append(element('p','Stored data could not be checked. Reconnect and try again.','fine'));refreshButton(box);
  }
 }
 // Clear account data immediately, before asynchronous auth/UI refreshes.
 client.auth.onAuthStateChange(()=>reset());
 document.addEventListener('visibilitychange',()=>{if(document.hidden)reset();});
 window.addEventListener('pagehide',reset);
 return {refresh,reset};
})();
