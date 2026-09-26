/* Organization leadership 0.20.45. Server-owned grants; no team or paid-plan writes. */
window.WMOrgInvites=(()=>{
 let state=null,epoch=0,review=null,homeEpoch=0;
 const el=id=>document.getElementById(id),E=v=>esc(String(v??''));
 const access=[['','Title only · organization directory'],['board','Board · organization calendar'],['membership_coordinator','Membership coordinator · membership support'],['division_director','Division director · selected scope'],['mat_director','Mat director · selected scope'],['pairing_director','Pairing director · selected scope'],['director','Director · selected scope'],['president','President · operations and contracts'],['coach','Coach · assigned role'],['team_leader','Team leader · assigned role'],['chaperone','Chaperone · assigned role'],['official','Official · assigned role']];
 const options=rows=>rows.map(([id,name])=>`<option value="${E(id)}">${E(name)}</option>`).join('');
 const current=s=>state===s&&s.epoch===epoch&&session?.user?.id===s.uid&&activeTeam?.id===s.team&&!managedLogin;
 const note=(s,text,bad=false)=>{if(!current(s))return;const n=el('oiStatus');if(n){n.textContent=text;n.classList.toggle('ops-error',bad)}};
 function close(){++epoch;state=null;if(review){review.dialog.close();review=null;}}
 function resetHome(){++homeEpoch;el('setupOrganizations')?.replaceChildren();el('setupOrganizations')?.classList.add('hidden');}
 async function rpc(q,uid=session?.user?.id){
  if(!uid||uid!==session?.user?.id||managedLogin)throw Error('Use your own personal account.');
  const {data,error}=await client.rpc('organization_leadership_invites',{p_request:q});
  if(uid!==session?.user?.id||managedLogin)throw Error('Your account changed. Reopen this invitation.');
  if(error)throw Error(error.message||'The invitation request failed.');return data;
 }
 function accessText(a){
  if(a?.access_role==='organization_admin')return 'Full organization administration, including administrator invitations and administration of teams managed by this organization. Affiliate links do not grant team administration.';
  if(a?.access_role==='organization_member')return 'Organization membership and permitted Board Room information. No board position, ballot eligibility, team roster or administration access is assigned.';
  return (access.find(([key])=>key===(a?.access_role||''))?.[1]||'Assigned organization access')+'. A position does not make this person a team coach or organization administrator.';
 }
 function accessHtml(a){return `<p><b>${E(a?.title)}</b> · ${E(a?.scope||'Organization')}</p><p>${E(accessText(a))}</p><p class="ops-sheet-note">Meeting management: ${a?.can_manage_meetings?'Yes':'No'} · Vote management: ${a?.can_manage_votes?'Yes':'No'} · Voting position: ${a?.voting_member?'Yes · eligibility still checked for each vote':'No'}</p>`;}
 function shell(s,body){if(current(s))el('opsContent').innerHTML=`<section class="gs-root oi-root"><h3>${s.mode==='members'?'Organization members':'Leadership invitations'}</h3><p>${s.mode==='members'?'Invite an adult to join the organization with their own account. Membership does not assign a board position or team role.':'Invite an adult directly to organization leadership. They use their own account and do not need to join a team.'}</p><p id="oiStatus" role="status" aria-live="polite"></p>${body}</section>`;}
 async function open({org,mode='leadership'}){
  close();const s=state={org,mode,epoch,uid:session?.user?.id,team:activeTeam?.id,data:null,pending:null};
  shell(s,'<p>Loading invitations…</p>');await reload(s);
 }
 async function reload(s,msg=''){
  try{const data=await rpc({action:'context',organization_id:s.org},s.uid);if(!current(s))return;s.data=data;s.pending=null;render(s);note(s,msg);}
  catch(error){if(current(s)){shell(s,'<button id="oiRetry" class="secondary">Reload invitations</button>');note(s,error.message,true);el('oiRetry').onclick=()=>reload(s)}}
 }
 function render(s){
  if(!current(s))return;
  if(s.mode==='members'){
   shell(s,`<div class="ops-actions"><button id="oiNew">Invite member</button><button id="oiRefresh" class="secondary">Refresh</button></div><h4>Members</h4>${s.data.members.map(m=>`<article class="ops-card"><b>${E(m.name)}</b><p>Joined ${E(new Date(m.joined_at).toLocaleDateString())}</p><button class="secondary" data-oi-member-remove="${E(m.user_id)}">Remove membership</button></article>`).join('')||'<p>No direct organization members yet.</p>'}<h4>Member invitations</h4>${s.data.invitations.filter(i=>i.kind==='member').map(i=>`<article class="ops-card"><b>${E(i.invited_email)}</b><p>${E(i.status)}${i.status==='pending'?' · Expires '+E(new Date(i.expires_at).toLocaleDateString()):''}</p>${i.status==='pending'?`<button class="secondary" data-oi-revoke="${E(i.id)}">Revoke invitation</button>`:''}</article>`).join('')||'<p>No member invitations yet.</p>'}`);
   el('opsContent').querySelectorAll('[data-oi-member-remove]').forEach(b=>b.onclick=async()=>{const m=s.data.members.find(x=>x.user_id===b.dataset.oiMemberRemove);if(!confirm(`Remove ${m.name} from direct organization membership? Their separate team or leadership roles remain.`))return;b.disabled=true;try{await rpc({action:'remove_member',organization_id:s.org,user_id:m.user_id,confirm_remove:true},s.uid);if(current(s))await reload(s,'Membership removed.')}catch(error){note(s,error.message,true);if(b.isConnected)b.disabled=false;}});
  }else{
  shell(s,`<div class="ops-actions"><button id="oiNew">Invite organization leader</button><button id="oiRefresh" class="secondary">Refresh</button></div><h4>Organization administrators</h4>${s.data.administrators.map(a=>`<article class="ops-card"><b>${E(a.name)}</b>${a.user_id===s.uid?' · You':`<button class="secondary" data-oi-remove="${E(a.user_id)}">Remove administrator access</button>`}</article>`).join('')}<p class="ops-sheet-note">Position assignments are managed in Positions. Other team roles and access remain separate when a leadership role is removed.</p><h4>Leadership invitations</h4>${s.data.invitations.filter(i=>i.kind!=='member').map(i=>`<article class="ops-card"><b>${E(i.invited_email)}</b><p>${E(i.access_summary.title)} · ${E(i.status)}${i.status==='pending'?' · Expires '+E(new Date(i.expires_at).toLocaleDateString()):''}</p>${i.status==='pending'?`<button class="secondary" data-oi-revoke="${E(i.id)}">Revoke invitation</button>`:''}</article>`).join('')||'<p>No leadership invitations yet.</p>'}`);
  }
  el('oiNew').onclick=()=>edit(s);el('oiRefresh').onclick=()=>reload(s);
  el('opsContent').querySelectorAll('[data-oi-revoke]').forEach(b=>b.onclick=async()=>{
   if(!confirm('Revoke this pending invitation? Its link will stop working.'))return;b.disabled=true;
   try{await rpc({action:'revoke',organization_id:s.org,id:b.dataset.oiRevoke},s.uid);if(current(s))await reload(s,'Invitation revoked.')}catch(e){note(s,e.message,true);if(b.isConnected)b.disabled=false;}
  });
  el('opsContent').querySelectorAll('[data-oi-remove]').forEach(b=>b.onclick=async()=>{
   const a=s.data.administrators.find(x=>x.user_id===b.dataset.oiRemove);
   if(!confirm(`Remove ${a.name} as an organization administrator? Their pending invitations will also be revoked. Separate team roles and position assignments remain.`))return;b.disabled=true;
   try{await rpc({action:'remove_admin',organization_id:s.org,user_id:a.user_id,confirm_remove:true},s.uid);if(current(s))await reload(s,'Organization administrator access removed.')}catch(e){note(s,e.message,true);if(b.isConnected)b.disabled=false;}
  });
 }
 function edit(s){
  s.pending=null;
  shell(s,`<form id="oiForm"><div class="gs-grid"><label>Invited email<input id="oiEmail" type="email" autocomplete="email" maxlength="254" required></label><label>Invitation role<select id="oiKind">${s.mode==='members'?'<option value="member">Organization member · no board or team role</option>':'<option value="position">Leadership position</option><option value="administrator">Organization administrator · full access</option>'}</select></label><div id="oiPositionFields"><label>Vacant position<select id="oiPosition">${options([['','Choose a position'],...s.data.positions.map(p=>[p.id,p.title+' · '+p.division_name])])}</select></label><label>Operational access<select id="oiAccess">${options(access)}</select></label><p class="ops-sheet-note">Create vacant positions under Positions first. Titles and permissions are separate.</p></div></div><div id="oiAccessSummary" class="privacy-note"></div><label class="ops-check"><input id="oiAdult" type="checkbox" required>I confirm the recipient is at least 18 and will use their own personal account.</label><label class="ops-check"><input id="oiPermissions" type="checkbox" required>I approve the permissions displayed above.</label><p class="ops-sheet-note">The invitation expires in 14 days. It grants access only after the recipient signs in with this verified email and accepts.</p><div class="ops-actions"><button id="oiCreate" type="submit">Create private invitation</button><button id="oiCancel" class="secondary" type="button">Cancel</button></div></form>`);
  const summary=()=>{
   const kind=el('oiKind').value,admin=kind==='administrator',member=kind==='member',p=s.data.positions.find(x=>x.id===el('oiPosition').value);
   el('oiPositionFields').classList.toggle('hidden',admin||member);el('oiPosition').required=kind==='position';
   el('oiAccessSummary').innerHTML=member?accessHtml({title:'Organization member',scope:'Organization',access_role:'organization_member'}):admin?accessHtml({title:'Organization administrator',scope:'Organization',access_role:'organization_admin',can_manage_meetings:true,can_manage_votes:true}):p?accessHtml({...p,scope:p.division_name,access_role:el('oiAccess').value}):'<p>Choose a vacant position to review its scope.</p>';
   el('oiPermissions').checked=false;
  };
  ['oiKind','oiPosition','oiAccess'].forEach(id=>el(id).onchange=summary);summary();el('oiCancel').onclick=()=>render(s);
  el('oiForm').onsubmit=async event=>{
   event.preventDefault();if(!current(s)||el('oiCreate').disabled)return;
   const p=s.data.positions.find(x=>x.id===el('oiPosition').value),kind=el('oiKind').value;
   if(kind==='position'&&!p){note(s,'Choose a vacant position.',true);return;}
   const q={action:'create',organization_id:s.org,email:el('oiEmail').value.trim().toLowerCase(),kind,
    position_id:kind==='position'?p.id:null,revision:kind==='position'?p.revision:null,
    access_role:kind==='position'?(el('oiAccess').value||null):null,confirm_adult:el('oiAdult').checked,confirm_access:el('oiPermissions').checked};
   const signature=JSON.stringify(q);
   if(!s.pending||s.pending.signature!==signature){const bytes=crypto.getRandomValues(new Uint8Array(32));s.pending={signature,id:crypto.randomUUID(),token:'WMO-'+Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('')};}
   const pending=s.pending,form=el('oiForm');[...form.elements].forEach(x=>x.disabled=true);note(s,'Saving invitation…');
   try{const data=await rpc({...q,id:pending.id,token:pending.token},s.uid);if(current(s))share(s,{...pending,...data,email:q.email,emailRequest:crypto.randomUUID()});}
   catch(error){note(s,'Invitation not yet confirmed. '+error.message+' Your form is still here; retry uses the same invitation.',true);}
   finally{if(current(s)&&form.isConnected)[...form.elements].forEach(x=>x.disabled=false);}
  };
 }
 function share(s,invite){
  const publicUrl=new URL('./',EMAIL_CONFIRM_REDIRECT_URL);publicUrl.searchParams.set('invite',invite.token);const url=publicUrl.toString();
  shell(s,`<h4>Invitation ready for ${E(invite.email)}</h4>${accessHtml(invite.access)}<p>Expires ${E(new Date(invite.expires_at).toLocaleDateString())}. The recipient must sign in or create an account using this email.</p><label>Private invitation link<input id="oiLink" readonly value="${E(url)}"></label><div class="ops-actions"><button id="oiSend">Email invitation</button><button id="oiCopy" class="secondary">Copy link</button><button id="oiDone" class="secondary">Back to invitations</button></div><p class="ops-sheet-note">Keep this screen open if you need to retry sending. For privacy, saved invitation lists do not reveal the link. Revoke and replace an invitation if you lose its link.</p>`);
  el('oiDone').onclick=()=>reload(s);el('oiLink').onclick=()=>el('oiLink').select();
  el('oiCopy').onclick=async()=>{
   try{await navigator.clipboard.writeText(url);note(s,'Private invitation link copied.');}
   catch{if(current(s)){el('oiLink').focus();el('oiLink').select();note(s,'Copy was unavailable. The link is selected; use your device’s Copy command.',true)}}
  };
  el('oiSend').onclick=async()=>{
   const button=el('oiSend');button.disabled=true;note(s,'Submitting invitation email…');
   try{
    const {data,error}=await client.functions.invoke('send-organization-invitation',{body:{organization_id:s.org,id:invite.id,token:invite.token,request_id:invite.emailRequest}});
    if(!current(s))return;
    if(error||data?.ok!==true||data?.sent!==1)throw Error(data?.error||error?.message||'Email submission was not confirmed.');
    note(s,'Invitation email submitted to '+invite.email+'. Ask them to check their inbox and Junk or Spam folder.');button.textContent='Email submitted';
   }catch(error){if(current(s)){note(s,'Email submission not confirmed. '+error.message+' Retry or copy the link.',true);button.disabled=false;button.textContent='Retry email';}}
  };
 }
 async function accept(token){
  const uid=session?.user?.id,team=activeTeam?.id;
  const data=await rpc({action:'preview',token},uid);
  if(session?.user?.id!==uid||activeTeam?.id!==team)return null;
  if(data.already_accepted)return data;
  closeSheets();
  const dialog=el('organizationInviteReview');
  dialog.innerHTML=`<form id="oiReviewForm"><h2 id="oiReviewTitle">Join ${E(data.organization_name)}</h2><p>Invitation for ${E(data.email)}</p>${accessHtml(data.access)}<p>This invitation does not add you to a team roster. Existing roles remain separate.</p><label class="ops-check"><input id="oiReviewAdult" type="checkbox" required>I am at least 18 and this is my own personal account.</label><label class="ops-check"><input id="oiReviewAccess" type="checkbox" required>I accept the displayed organization access.</label><p id="oiReviewStatus" role="status" aria-live="polite"></p><div class="ops-actions"><button id="oiReviewAccept" type="submit">Accept organization invitation</button><button id="oiReviewCancel" class="secondary" type="button">Not now</button></div></form>`;
  return new Promise(resolve=>{
   const r=review={dialog,uid,team};let settled=false,busy=false;
   const finish=value=>{if(settled)return;settled=true;if(review===r)review=null;dialog.onclose=null;dialog.oncancel=null;dialog.close();dialog.replaceChildren();resolve(value);};
   dialog.onclose=()=>finish(null);dialog.oncancel=event=>{event.preventDefault();if(!busy)finish(null)};
   el('oiReviewCancel').onclick=()=>finish(null);
   el('oiReviewForm').onsubmit=async event=>{
    event.preventDefault();if(busy||review!==r)return;busy=true;el('oiReviewAccept').disabled=true;el('oiReviewCancel').disabled=true;
    el('oiReviewStatus').textContent='Accepting organization access…';
    try{const accepted=await rpc({action:'accept',token,confirm_adult:el('oiReviewAdult').checked,confirm_access:el('oiReviewAccess').checked},uid);if(review===r&&activeTeam?.id===team)finish(accepted);else finish(null)}
    catch(error){if(review===r){el('oiReviewStatus').textContent=error.message;el('oiReviewAccept').disabled=false;el('oiReviewCancel').disabled=false;busy=false;}}
   };
   dialog.showModal();el('oiReviewTitle').setAttribute('tabindex','-1');el('oiReviewTitle').focus();
  });
 }
 async function showHome(){
  const uid=session?.user?.id,ticket=++homeEpoch,box=el('setupOrganizations');
  if(!uid||managedLogin)return;box.classList.remove('hidden');box.innerHTML='<h2>Your organizations</h2><p>Checking organization access…</p>';
  const {data,error}=await client.rpc('get_operations',{p_request:{action:'context'}});
  if(ticket!==homeEpoch||uid!==session?.user?.id||managedLogin)return;
  if(error){box.innerHTML='<h2>Organization access</h2><p>Could not check your organizations. Tap Check Access to retry.</p>';return;}
  const rows=Array.isArray(data)?data:[];box.classList.toggle('hidden',!rows.length);
  box.innerHTML='<h2>Your organizations</h2><p>Open your organization tools. Your assigned role controls access.</p>'+rows.map(o=>`<button class="wide secondary" data-oi-org="${E(o.id)}">${E(o.name)}</button>`).join('');
  box.querySelectorAll('[data-oi-org]').forEach(b=>b.onclick=()=>WMOperations.open(b.dataset.oiOrg));
  if(rows.length){el('setupAccessStatus').textContent='Your organization access is ready.';el('setupChoices').open=!!pendingInviteToken;}
 }
 return {open,close,accept,showHome,resetHome};
})();
