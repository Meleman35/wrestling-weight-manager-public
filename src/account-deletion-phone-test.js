/* Read-only test setup. Enrollment is checked on the server; no erasure action. */
window.WMDeletionPhoneTest=(()=>{
 'use strict';
 const fields=[['account_photos','Account profile photos'],['wrestling_profile_photos','Wrestling profile photos'],['messages','Messages sent'],['message_attachments','Message attachments uploaded'],['team_posts','Team posts written'],['post_attachments','Attachments on those posts'],['uploaded_objects','Stored files uploaded'],['teams','Team memberships'],['teams_needing_handoff','Teams needing an administrator handoff'],['guardian_links','Guardian links'],['organization_roles','Organization roles']];
 let epoch=0,card=null,admitted=false;
 const actor=()=>session?.user?.id&&!managedLogin?session.user.id:null;
 const visible=()=>!document.hidden&&document.getElementById('appLockOverlay')?.classList.contains('hidden')&&document.getElementById('accountSheet')&&!document.getElementById('accountSheet').classList.contains('hidden');
 function reset(){++epoch;card?.remove();card=null;admitted=false;}
 function element(tag,text,cls){const e=document.createElement(tag);if(text)e.textContent=text;if(cls)e.className=cls;return e;}
 function mount(){
  if(card)return card;
  card=element('section',null,'feature-card');card.id='deletionPhoneTestCard';
  document.getElementById('accountSheet').querySelector('.sheet-head').after(card);return card;
 }
 function heading(box){box.append(element('h3','Deletion test setup'));box.append(element('p','Deletion is not enabled yet.','fine'));}
 function refreshButton(box){const b=element('button','Refresh stored data','secondary wide');b.type='button';b.onclick=()=>refresh();box.append(b);}
 async function refresh(){
  const uid=actor();if(!uid||!visible()){reset();return;}
  const g=++epoch,token=session.access_token;
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
   box.append(element('p','Add your test photos and messages, then refresh these counts. This screen only checks stored data. It does not delete anything.','fine'));
   const list=element('dl');list.style.cssText='display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px 16px;margin:16px 0';
   for(const [key,label] of fields){list.append(element('dt',label));const n=element('dd',String(data.counts[key]));n.style.margin='0';n.dataset.count=key;list.append(n);}box.append(list);
   if(data.counts.teams_needing_handoff)box.append(element('p','Before deletion: arrange another administrator or review closing your test team. Deleting your account must not leave a team without an administrator.','fine'));
   box.append(element('p','Counts can overlap and include retained records. Linked team and child records need a separate review. Files saved only on this phone are not counted.','fine'));
   box.append(element('p','Last checked '+new Date(data.checked_at).toLocaleString(),'fine'));
   refreshButton(box);
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
