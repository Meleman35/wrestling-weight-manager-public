/* Enrolled scope choices and confirmation previews. No erasure action. */
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
  #deletionPhoneTestCard select{font-size:16px;width:100%;min-height:44px;margin:8px 0 12px}#deletionPhoneTestCard select[hidden]{display:none}#deletionConfirmDialog input{font-size:16px}#deletionConfirmDialog button{min-height:44px}
  #deletionAllTargets{margin:12px 0;padding:12px;border:1px solid var(--line);border-radius:10px;min-width:0}#deletionAllTargets[hidden]{display:none}#deletionAllTargets label{display:flex;align-items:center;gap:10px;min-height:44px;overflow-wrap:anywhere}#deletionAllTargets input{width:20px;height:20px;flex:0 0 20px;margin:0}#deletionConfirmTargets{padding-left:22px;overflow-wrap:anywhere}
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
 function confirmation(opener,choice,scopes){
  if(!admitted||!actor()||!visible()||!card?.contains(opener))return;
  closeConfirmation();
  const uid=actor(),token=session.access_token,g=epoch;
  const current=()=>g===epoch&&uid===actor()&&token===session?.access_token&&visible();
  dialog=element('dialog');dialog.id='deletionConfirmDialog';dialog.setAttribute('aria-labelledby','deletionConfirmTitle');dialog.setAttribute('aria-describedby','deletionConfirmWarning deletionConfirmUnavailable');
  const title=element('h2',choice.kind==='all'?'Delete all selected':choice.kind==='personal'?'Delete personal account':choice.kind==='administrator'?'Remove administrator access':choice.kind==='team'?'Delete team':'Delete organization');title.id='deletionConfirmTitle';dialog.append(title);
  const unavailable=element('p','Confirmation preview: account deletion is not available yet. Nothing will be deleted.','deletion-unavailable');unavailable.id='deletionConfirmUnavailable';dialog.append(unavailable);
  if(!['personal','all'].includes(choice.kind))dialog.append(element('p','Selected '+choice.targetKind+': '+choice.name));
  if(choice.kind==='all'){
   dialog.append(element('h3','Included in this deletion'));
   const list=element('ul');list.id='deletionConfirmTargets';list.append(element('li','Your personal account and your memberships across all teams and organizations'));
   for(const item of choice.targets)list.append(element('li',(item.targetKind==='team'?'Team: ':'Organization: ')+item.name));
   dialog.append(list);
  }
  const warning=element('p',scopeWarning(choice));warning.id='deletionConfirmWarning';dialog.append(warning);
  if(['personal','all'].includes(choice.kind)){
   const included=new Set((choice.targets||[]).map(x=>x.targetKind+':'+x.id));
   const handoffs=[...scopes.teams.filter(x=>x.needs_handoff&&!included.has('team:'+x.id)).map(x=>'Team: '+x.name),...scopes.organizations.filter(x=>x.needs_handoff&&!included.has('organization:'+x.id)).map(x=>'Organization: '+x.name)];
   if(handoffs.length)dialog.append(element('p','You are the last administrator for '+handoffs.join('; ')+'. For workspaces you are keeping, transfer administration to another person before deleting your personal account. Alternatively, explicitly include them in Delete all or close them separately.','fine'));
  }else if(choice.kind==='administrator'){
   if(choice.inherited_admin)dialog.append(element('p','You also have administrator access through the organization. Removing this direct team role alone will not remove that organization access.','fine'));
   else if(choice.needs_handoff)dialog.append(element('p','You are the last administrator. Transfer administration to another person or separately choose to delete this '+choice.targetKind+' first.','fine'));
  }else if(choice.kind==='organization'&&(choice.team_count||choice.athlete_count)){
   dialog.append(element('p','This organization has '+choice.team_count+' linked team(s) and '+choice.athlete_count+' linked athlete record(s). Preserve or transfer these records before closing it. Teams require their own separate deletion choice.','fine'));
  }
  if(choice.kind==='all'&&choice.targets.some(x=>x.targetKind==='organization'&&(x.team_count||x.athlete_count)))dialog.append(element('p','Linked athlete profiles must be preserved. Any linked team not included above must be preserved or transferred before its organization can be closed.','fine'));
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
   status.textContent='This action is not available yet. Nothing has been changed, deleted or scheduled for deletion.';
   input.value='';confirm.disabled=true;
  };
  form.append(label,input,status,cancel,confirm);dialog.append(form);
  dialog.addEventListener('cancel',event=>{event.preventDefault();closeConfirmation();if(current())opener.focus();});
  document.body.append(dialog);dialog.showModal();input.focus();
 }
 const kinds=[['personal','Delete my personal account'],['administrator','Remove my administrator access'],['team','Delete a team'],['organization','Delete an organization'],['all','Delete all']];
 function scopeWarning(choice){
  if(choice.kind==='all')return 'Delete all is permanent. It deletes YOUR personal account, sign-in and personal data across all memberships, together with ONLY the teams and organizations in this selection. Everyone else keeps their personal account, athlete profile and memberships elsewhere, even if this was their only team. Your linked children’s profiles also stay. People left without a team can sign in and join a team or create their own. Unchecked workspaces and workspaces you only belong to are not closed. Shared records need review; downloaded copies cannot be removed.';
  if(choice.kind==='personal')return 'Personal account deletion is permanent. It removes your sign-in, personal profile and personal data across ALL teams and organizations you belong to, including inactive memberships. Other people’s accounts and personal profiles stay. Your linked children’s profiles are not deleted. Team and organization closure requires a separate choice. Shared records may need anonymization, and copies already downloaded by other people cannot be removed.';
  if(choice.kind==='administrator')return 'This removes your administrator role for the selected '+choice.targetKind+'. Your personal account, sign-in and personal profile stay. Other people’s profiles, the team or organization, and your memberships elsewhere stay. This is a role change, not personal account deletion.';
  if(choice.kind==='team')return 'Team deletion is permanent. It removes this team and its team-only memberships and data. Everyone’s personal account and profile stay, including people who belong only to this team. Their other team and organization memberships stay. Shared athlete profiles and their records elsewhere must be preserved.';
  return 'Organization deletion is permanent. It removes this organization and its organization-only memberships and data. Everyone’s personal account and profile stay, including people who belong only to this organization. Other memberships stay. Linked teams require separate handling; this choice does not automatically delete them or shared athlete profiles.';
 }
 function scopeChoices(box,scopes){
  const label=element('label','What would you like to remove?');label.htmlFor='deletionScopeType';
  const type=element('select');type.id='deletionScopeType';
  const roleTargets=[...scopes.teams.filter(x=>x.direct_admin).map(x=>({...x,targetKind:'team'})),...scopes.organizations.map(x=>({...x,targetKind:'organization'}))];
  const targetLabel=element('label','Choose the specific team or organization');targetLabel.htmlFor='deletionScopeTarget';
  const target=element('select');target.id='deletionScopeTarget';
  const allTargets=[...scopes.teams.map(x=>({...x,targetKind:'team'})),...scopes.organizations.map(x=>({...x,targetKind:'organization'}))];
  const allBox=element('fieldset');allBox.id='deletionAllTargets';
  const included=new Map();
  function renderAll(){
   allBox.replaceChildren();included.clear();
   allBox.append(element('legend','Included in Delete all'),element('p','Your personal account is included. Review every team and organization below; uncheck any you want to keep.','fine'));
   for(const item of allTargets){
    const row=element('label'),input=element('input');input.type='checkbox';input.checked=true;input.dataset.deletionInclude=item.targetKind+':'+item.id;
    included.set(item.targetKind+':'+item.id,input);input.onchange=update;
    row.append(input,element('span',(item.targetKind==='team'?'Team: ':'Organization: ')+item.name));allBox.append(row);
   }
  }
  const description=element('p',null,'fine');description.id='deletionScopeDescription';description.setAttribute('aria-live','polite');
  const button=element('button','Delete Account','wide deletion-action');button.type='button';
  const available=kind=>kind==='all'?allTargets:kind==='administrator'?roleTargets:kind==='team'?scopes.teams.map(x=>({...x,targetKind:'team'})):kind==='organization'?scopes.organizations.map(x=>({...x,targetKind:'organization'})):[];
  for(const [kind,text] of kinds){const option=element('option',text);option.value=kind;option.disabled=kind!=='personal'&&!available(kind).length;type.append(option);}
  const choice=()=>{
   if(type.value==='personal')return {kind:'personal'};
   if(type.value==='all'){const targets=allTargets.filter(x=>included.get(x.targetKind+':'+x.id)?.checked);return targets.length?{kind:'all',targets}:null;}
   return available(type.value).map(x=>({...x,kind:type.value})).find(x=>x.targetKind+':'+x.id===target.value);
  };
  const update=()=>{closeConfirmation();const selected=choice();button.disabled=!selected;button.textContent=type.value==='all'?'Delete All':type.value==='personal'?'Delete Account':type.value==='administrator'?'Remove administrator access':type.value==='team'?'Delete Team':'Delete Organization';description.textContent=scopeWarning(selected||{kind:type.value,targetKind:'team or organization'});};
  type.onchange=()=>{
   target.replaceChildren();const option=element('option','Choose…');option.value='';target.append(option);
   for(const item of available(type.value)){const option=element('option',(item.targetKind==='team'?'Team: ':'Organization: ')+item.name);option.value=item.targetKind+':'+item.id;target.append(option);}
   target.hidden=targetLabel.hidden=['personal','all'].includes(type.value);allBox.hidden=type.value!=='all';if(type.value==='all')renderAll();else{included.clear();allBox.replaceChildren();}update();
  };
  target.onchange=update;
  button.onclick=()=>{const selected=choice();if(selected)confirmation(button,selected,scopes);};
  box.append(label,type,targetLabel,target,description,allBox,element('p','Only choices for your current administrator roles are offered. Personal account deletion is available independently of administrator status. Delete all combines your personal account with the checked teams and organizations.','fine'));
  refreshButton(box);box.append(button);type.onchange();
 }
 function validScopes(data){
  const id=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const base=x=>x&&id.test(x.id)&&typeof x.name==='string'&&x.name.length>0&&typeof x.needs_handoff==='boolean';
  const unique=xs=>new Set(xs.map(x=>x.id)).size===xs.length;
  const teams=data.scopes?.teams,orgs=data.scopes?.organizations;
  return data.scope_version===1&&Array.isArray(teams)&&Array.isArray(orgs)&&unique(teams)&&unique(orgs)&&
   teams.every(x=>base(x)&&typeof x.direct_admin==='boolean'&&typeof x.inherited_admin==='boolean'&&(x.direct_admin||x.inherited_admin))&&
   orgs.every(x=>base(x)&&Number.isSafeInteger(x.team_count)&&x.team_count>=0&&Number.isSafeInteger(x.athlete_count)&&x.athlete_count>=0);
 }
 async function refresh(){
  const uid=actor();if(!uid||!visible()){reset();return;}
  closeConfirmation();const g=++epoch,token=session.access_token;
  const valid=()=>epoch===g&&actor()===uid&&session?.access_token===token&&visible();
  const wasAdmitted=admitted;
  if(wasAdmitted){const box=mount();box.replaceChildren();heading(box);box.append(element('p','Checking stored data…','fine'));}
  try{
   const {data,error}=await client.rpc('account_deletion_scope_preflight');
   if(!valid())return;
   if(error)throw Error('unavailable');
   if(data?.enabled!==true){reset();return;}
   if(data.deletion_enabled!==false||!validScopes(data)||data.subject_id!==uid||!Number.isFinite(Date.parse(data.checked_at))||fields.some(([key])=>!Number.isSafeInteger(data.counts?.[key])||data.counts[key]<0))throw Error('invalid response');
   admitted=true;const box=mount();box.replaceChildren();heading(box);
   box.append(element('h3','Your personal account data'));box.append(element('p','These counts belong to your personal account. Choose the action below after reviewing them.','fine'));
   const list=element('dl');list.style.cssText='display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px 16px;margin:16px 0';
   for(const [key,label] of fields){list.append(element('dt',label));const n=element('dd',String(data.counts[key]));n.style.margin='0';n.dataset.count=key;list.append(n);}box.append(list);
   if(data.counts.teams_needing_handoff)box.append(element('p','Before personal account deletion: arrange another administrator or separately review closing each affected team or organization.','fine'));
   box.append(element('p','Counts can overlap and include retained records. Linked team and child records need a separate review. Files saved only on this phone are not counted.','fine'));
   box.append(element('p','Last checked '+new Date(data.checked_at).toLocaleString(),'fine'));
   scopeChoices(box,data.scopes);
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
