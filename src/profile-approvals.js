/* Private profile drafts and guardian reviews. Server checks current family links. */
window.WMProfileApprovals=(()=>{
 const $=id=>document.getElementById(id),E=v=>esc(String(v??''));let revision=0;
 const allowed=()=>!!session?.user?.id&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)');
 async function call(action,data={}){if(!allowed())throw Error('Unlock the app and use your personal account.');const uid=session.user.id;const out=await client.rpc('wm_profile_approval_request',{p_action:action,p_data:data});if(uid!==session?.user?.id||!allowed())throw Error('Account changed. Reopen your profile.');if(out.error)throw Error(out.error.message);return out.data;}
 async function finish(draft,file,saveOnly,isCurrent=()=>true){
  const uid=session?.user?.id,check=()=>{if(!allowed()||uid!==session?.user?.id||!isCurrent())throw Error('Screen changed. Reopen your profile draft.');};check();
  if(file){const {error}=await client.storage.from(draft.bucket).upload(draft.path,file,{contentType:'image/jpeg',upsert:false});check();if(error)throw Error(error.message);}
  const saved=await call('save_draft',{id:draft.id});check();if(saveOnly)return saved;
  let result;
  try{result=await call('submit',{id:draft.id});check();}catch(e){throw Error('Your private draft is saved. '+e.message);}
  if(result.auto_photo){
   try{
    let photo=file;
    if(!photo){const out=await client.storage.from(draft.bucket).download(draft.path);check();if(out.error||!out.data)throw Error('Reopen your saved photo and try again.');photo=out.data;}
    await saveUnifiedProfilePhoto(photo,{kind:'social',id:draft.profile_id,approval_id:draft.id},isCurrent);check();
    return {status:'approved',auto_approved:true,pending:false};
   }catch(e){throw Error('Your changes are saved for review. The photo could not finish updating: '+e.message);}
  }
  return result;
 }
 async function preview(path,img,isCurrent=()=>true){
  const uid=session?.user?.id;const {data,error}=await client.storage.from('profile-photo-requests').download(path);
  if(!allowed()||uid!==session?.user?.id||!isCurrent()||!img.isConnected)throw Error('Screen changed.');
  if(error||!data)throw Error('Photo could not load. Reopen the request before approving.');
  const url=URL.createObjectURL(data);try{await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(Error('Photo could not be displayed.'));img.src=url;});}finally{URL.revokeObjectURL(url);}
  if(!allowed()||uid!==session?.user?.id||!isCurrent())throw Error('Screen changed.');return data;
 }
 const sheet=document.createElement('section');sheet.id='profileApprovalsSheet';sheet.className='sheet hidden';sheet.setAttribute('role','dialog');sheet.setAttribute('aria-modal','true');sheet.setAttribute('aria-label','Profile drafts and approvals');
 sheet.innerHTML='<div class="sheet-head"><h2>Profile drafts & approvals</h2><button type="button" id="profileApprovalsClose" class="icon-close" aria-label="Close profile approvals">×</button></div><p id="profileApprovalsStatus" role="status" aria-live="polite"></p><div id="profileApprovalsBody"></div>';document.body.append(sheet);
 $('profileApprovalsClose').onclick=()=>{revision++;closeSheets();};
 const entry=document.createElement('button');entry.type='button';entry.className='wide secondary';entry.textContent='My profile · drafts & parent approvals';entry.onclick=()=>open().catch(e=>message(e.message,true));$('personalAccountProfileCard').after(entry);
 const labels={draft:'Private draft · not sent',pending:'Waiting for parent approval',approved:'Approved · changes are live',rejected:'Changes requested · edit and send again'};
 const fields={roles:'Roles',affiliation:'Team / organization',bio:'About me / goals',age_division:'Age division',mat_rank:'Mat-official classification',pairing_rank:'Pairing-official classification',music_title:'Entrance Song',music_url:'Song link',photo:'Profile photo',corner:'My Corner',follow:'Accept follow requests',outgoing_follow:'Athlete may request follows and arrange My Corner',results:'Tournament results'};
 async function open(filter={}){
  if(!allowed())return;const uid=session.user.id,t=++revision;openSheet(sheet.id);$('profileApprovalsBody').replaceChildren();$('profileApprovalsStatus').textContent='Loading profile drafts…';
  const valid=()=>allowed()&&uid===session?.user?.id&&t===revision&&!sheet.classList.contains('hidden');
  const [rows,settings]=await Promise.all([call('list',filter),call('settings',{profile_id:filter.profile_id||null})]);if(!valid())return;
  $('profileApprovalsStatus').textContent='Edit anytime. Your last approved profile stays visible while changes wait for review.';
  const own=document.createElement('button');own.className='wide secondary';own.textContent='My Profile';own.onclick=()=>WMProfiles.myProfile();$('profileApprovalsBody').append(own);
  for(const item of Array.isArray(settings)?settings:[]){
   const policy=item.policy||{},box=document.createElement('section');box.className='wp-panel';box.dataset.profilePolicy=item.profile_id;
   box.innerHTML=`<h3>${E(item.name)} · parent controls</h3><p class="fine">Name, phone, contact email and contact-sharing changes always need parent approval.</p>${item.can_manage?`<label class="toggle-row"><span><b>Auto-approve profile edits</b><small>Off: approve every change.</small></span><input type="checkbox" data-auto-profile ${policy.auto_approve?'checked':''}></label><label class="toggle-row"><span><b>Review photo changes</b><small>When automatic approval is on, keep reviewing photos.</small></span><input type="checkbox" data-review-photos ${policy.review_photos!==false?'checked':''}></label><button type="button" data-save-profile-policy>Save parent settings</button><p class="profile-policy-note" role="status"></p>`:`<p>${policy.auto_approve?(policy.source==='parent_browser'?'Routine profile edits save with browser parent permission. Visibility changes still need parent review. ':'Other profile edits save automatically. ')+(policy.review_photos?'Photos need review.':'Photos save automatically.'):'Your parent reviews every change.'}</p>`}`;
   $('profileApprovalsBody').append(box);
   if(item.can_manage){
    const auto=box.querySelector('[data-auto-profile]'),photos=box.querySelector('[data-review-photos]'),save=box.querySelector('button'),note=box.querySelector('[role="status"]');
    auto.onchange=()=>{photos.disabled=!auto.checked;};auto.onchange();
    save.onclick=async()=>{if(save.disabled||!valid())return;save.disabled=true;auto.disabled=true;photos.disabled=true;note.textContent='Saving…';
     try{await call('set_settings',{profile_id:item.profile_id,auto_approve:auto.checked,review_photos:photos.checked});if(valid())note.textContent='Parent settings saved. These apply the next time your athlete saves changes.';}
     catch(e){if(valid())note.textContent=e.message;}
     finally{if(valid()){save.disabled=false;auto.disabled=false;photos.disabled=!auto.checked;}}
    };
   }
  }
  if(!rows.length){const p=document.createElement('p');p.textContent='No profile requests yet. Open your profile to get started.';$('profileApprovalsBody').append(p);return;}
  for(const r of rows){
   const proposal=r.proposal||{},details=proposal.details||{};const card=document.createElement('article');card.className='wp-panel';card.dataset.profileRequest=r.id;
   card.innerHTML=`<h3>${E(proposal.name||r.name)}</h3><p><strong>${E(r.auto_approved?'Saved automatically · parent settings':labels[r.status]||r.status)}</strong></p>${r.path?'<img class="wp-photo" data-approval-photo alt="Requested profile photo">':'<p class="fine">Photo stays unchanged.</p>'}${proposal.contact?`<h4>Contact settings</h4><p>Email: ${E(proposal.contact.email||'Not added')}<br>Phone: ${E(proposal.contact.phone||'Not added')}</p><p>Share email with coaches: ${proposal.contact.share_email_with_coaches?'Yes':'No'}<br>Share phone with coaches: ${proposal.contact.share_phone_with_coaches?'Yes':'No'}</p><p class="fine">Sign-in email stays the same.</p>`:''}<dl>${Object.entries(fields).filter(([k])=>!['results','photo','corner','follow','outgoing_follow'].includes(k)&&details[k]).map(([k,l])=>`<dt><b>${E(l)}</b></dt><dd style="margin:0 0 12px;overflow-wrap:anywhere">${E(details[k]||'Not added')}</dd>`).join('')}</dl>${(details.results||[]).length?'<h4>Tournament results</h4>'+details.results.map(x=>`<p style="overflow-wrap:anywhere">${E([x.event,x.date,x.style,x.division,x.placement,x.url].filter(Boolean).join(' · '))}</p>`).join(''):''}<h4>Requested visibility</h4><p>${proposal.discoverable?'Allow discovery by signed-in members':'Keep shared profile private'}</p><p><b>Share:</b> ${E(Object.entries(fields).filter(([k])=>proposal.sharing?.[k]).map(([,label])=>label).join(', ')||'No optional fields selected')}</p><p class="fine">All other optional fields stay hidden.</p><div data-approval-actions></div><p data-approval-note role="status"></p>`;
   $('profileApprovalsBody').append(card);const actions=card.querySelector('[data-approval-actions]'),note=card.querySelector('[data-approval-note]');let photo=null,loaded=!r.path;
   if(r.path)preview(r.path,card.querySelector('img'),valid).then(blob=>{photo=blob;loaded=true;const b=actions.querySelector('[data-approve-profile]');if(b)b.disabled=false;}).catch(e=>{if(valid()){card.querySelector('img').hidden=true;note.textContent=e.message;}});
   if(r.can_review&&r.status==='pending'){
    actions.innerHTML='<label><input type="checkbox" data-review-confirm> I reviewed the name, photo, details and sharing choices, including any song.</label><div class="wp-actions"><button type="button" data-approve-profile>Approve profile</button><button type="button" class="secondary" data-reject-profile>Ask for changes</button></div>';
    const approve=actions.querySelector('[data-approve-profile]');approve.disabled=!loaded;
    let busy=false;
    for(const b of actions.querySelectorAll('button'))b.onclick=async()=>{
     if(busy||!valid())return;const accept=b===approve;if(accept&&!actions.querySelector('input').checked){note.textContent='Review the profile and check the box before approving.';return;}
     if(accept&&!loaded)return;busy=true;actions.querySelectorAll('button').forEach(x=>x.disabled=true);note.textContent='Saving your decision…';let saved=false;
     try{if(accept&&r.path)await saveUnifiedProfilePhoto(photo,{kind:'social',id:r.profile_id,approval_id:r.id},valid);else await call(accept?'approve':'reject',{id:r.id});saved=true;if(!valid())return;await open(filter);$('profileApprovalsStatus').textContent=accept?'Profile approved. The new profile is now live.':'Changes requested. The athlete can edit their draft and send it again.';window.WMNotificationSync?.readChanged();}
     catch(e){if(!valid())return;note.textContent=saved||e.photoCommitted?'Your decision was saved. Reopen approvals to refresh.':e.photoSaveUncertain?'The update could not be confirmed. Reopen approvals to check before trying again.':e.message;}
     finally{busy=false;if(valid())actions.querySelectorAll('button').forEach(x=>x.disabled=x===approve&&!loaded);}
    };
   }else if(!r.can_review){const b=document.createElement('button');b.type='button';b.textContent='Edit my profile';b.onclick=()=>WMProfiles.editProfile(r.profile_id);actions.append(b);}
  }
 }
 return {call,finish,preview,open,reset(){revision++;$('profileApprovalsBody').replaceChildren();sheet.classList.add('hidden');}};
})();
