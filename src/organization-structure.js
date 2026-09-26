/* Organization structure 0.20.36. Embedded in index.html; no local data authority. */
window.WMOrgStructure=(()=>{
 let state=null,epoch=0;
 const el=id=>document.getElementById(id), E=v=>esc(String(v??''));
 const access=[['','Title only · no operational access'],['board','Board · organization calendar'],['membership_coordinator','Membership coordinator · membership support'],['division_director','Division director · operations in selected scope'],['mat_director','Mat director · operations in selected scope'],['pairing_director','Pairing director · operations in selected scope'],['director','Director · operations in selected scope'],['president','President · organization operations and contracts'],['coach','Coach · assigned role'],['team_leader','Team leader · assigned role'],['chaperone','Chaperone · assigned role'],['official','Official · assigned role']];
 const presets={wawa:['Chairman','Vice-Chairman','Secretary','Treasurer','Registration','Open Director','Boys Junior','Boys 16U','Boys - Kids','Girls/16U Director','Girls - Kids','Mat Officials','Operations Official','Cultural Exchange','State Coach','Media Director','Member At-Large','Male Athlete Rep','Female Athlete Rep'],association:['President','Vice President','Secretary','Treasurer','Board Member','Membership Coordinator'],club:['President','Vice President','Secretary','Treasurer','Head Coach','Assistant Coach','Membership Coordinator'],school:['Principal','Assistant Principal','Athletic Director','Head Coach','Assistant Coach','Athletic Trainer','Team Manager'],school_district:['Superintendent','Assistant Superintendent','Board Chair','Board Vice Chair','Board Clerk','Board Treasurer','Board Trustee','District Athletic Director','School Principal','Athletic Director']};
 const choice=(id,label,rows,value='')=>`<label>${E(label)}<select id="${id}">${rows.map(([v,n])=>`<option value="${E(v)}" ${String(v)===String(value??'')?'selected':''}>${E(n)}</option>`).join('')}</select></label>`;
 const field=(id,label,value='',max=160)=>`<label>${E(label)}<input id="${id}" value="${E(value)}" maxlength="${max}"></label>`;
 const area=(id,label,value='',max=2000)=>`<label>${E(label)}<textarea id="${id}" maxlength="${max}">${E(value)}</textarea></label>`;
 const check=(id,label,checked=false)=>`<label class="ops-check"><input type="checkbox" id="${id}" ${checked?'checked':''}>${E(label)}</label>`;
 const val=id=>el(id)?.value?.trim()||'';
 const current=s=>state===s&&s.epoch===epoch&&session?.user?.id===s.uid&&activeTeam?.id===s.team&&!managedLogin;
 const note=(s,text,bad=false)=>{if(!current(s))return;const n=el('gsStatus');if(n){n.textContent=text;n.classList.toggle('ops-error',bad);}};
 function close(){epoch++;state=null;}
 async function call(s,q){
  if(!current(s))throw Error('Account or team changed. Reopen the organization.');
  const {data,error}=await client.rpc('organization_governance',{p_request:{organization_id:s.org,...q}});
  if(!current(s))throw Error('Account or team changed. Reopen the organization.');
  if(error)throw Error(error.message||'The server could not save this change.');
  if(data?.error)throw Error(data.error);return data;
 }
 function shell(s,title,body){if(!current(s))return;el('opsContent').innerHTML=`<section class="gs-root"><div class="ops-section-heading"><h3>${E(title)}</h3></div><div id="gsStatus" class="ops-sheet-note" role="status" aria-live="polite"></div>${body}</section>`;}
 async function open({org,hub,kind,scope=''}){
  close();const s=state={org,hub,kind,scope,epoch,uid:session?.user?.id,team:activeTeam?.id,data:null,filter:'current',query:'',pending:null};
  shell(s,kind==='positions'?'Positions':'Affiliate directory','<p>Loading saved organization records…</p>');
  try{s.data=await call(s,{action:'context'});render(s);}catch(err){if(current(s)){shell(s,'Organization structure','<button id="gsRetry" class="secondary">Retry loading</button>');note(s,err.message,true);el('gsRetry').onclick=()=>open({org,hub,kind,scope});}}
 }
 async function reload(s,message=''){try{s.data=await call(s,{action:'context'});if(!current(s))return;s.pending=null;render(s);note(s,message);}catch(err){if(current(s)){shell(s,'Organization structure','<button id="gsReloadFailed" class="secondary">Reload saved records</button>');note(s,'Saved change could not be reloaded. '+err.message,true);el('gsReloadFailed').onclick=()=>reload(s);}}}
 function render(s){
  if(!current(s))return;const pos=s.kind==='positions',admin=s.data.can_manage_structure;
  const inScope=r=>{if(!pos||!s.scope||!r.division_id)return true;let d=r.division_id;const seen=new Set();while(d&&!seen.has(d)){if(d===s.scope)return true;seen.add(d);d=s.hub.divisions.find(x=>x.id===d)?.parent_id;}return false;};
  const all=(pos?s.data.positions:s.data.affiliates).filter(inScope);
  const rows=all.filter(r=>(s.filter==='all'||(pos?r.active:r.status!=='archived'))&&(!s.query||(pos?r.title+' '+(r.assigned_name||''):r.name).toLowerCase().includes(s.query.toLowerCase())));
  const buttons=admin?`<button id="gsAdd">+ ${pos?'Add position':'Add affiliate'}</button>${pos?'<button id="gsPresets" class="secondary">Position templates</button>':''}`:'';
  shell(s,pos?'Positions':'Affiliate directory',`<p class="ops-sheet-note">${pos?'Define the posts your organization needs, including vacancies. One adult can hold several posts. Access is assigned separately from the title.':'Keep clubs and schools on record as affiliations change. Membership and voting eligibility each require review.'}</p>
   <div class="ops-actions">${buttons}<button id="gsRefresh" class="secondary">Refresh</button></div>
   <div class="gs-grid">${field('gsSearch','Search',s.query)}${choice('gsFilter','Show',[['current','Current records'],['all','Include archived']],s.filter)}</div>
   <p class="ops-sheet-note">${rows.length} of ${all.length} records${admin?'':' · View only'}</p>
   <div id="gsRows">${rows.map(r=>pos?positionCard(s,r):affiliateCard(s,r)).join('')||'<div class="empty-card">No matching records.</div>'}</div>`);
  el('gsAdd')?.addEventListener('click',()=>edit(s));el('gsPresets')?.addEventListener('click',()=>templates(s));
  el('gsRefresh').onclick=()=>reload(s);el('gsFilter').onchange=()=>{s.filter=val('gsFilter');render(s)};
  el('gsSearch').oninput=()=>{const v=val('gsSearch'),cursor=el('gsSearch').selectionStart;s.query=v;render(s);el('gsSearch').focus();el('gsSearch').setSelectionRange(cursor,cursor);};
  el('gsRows').querySelectorAll('[data-gs-edit]').forEach(b=>b.onclick=()=>edit(s,all.find(r=>r.id===b.dataset.gsEdit)));
  el('gsRows').querySelectorAll('[data-gs-invite]').forEach(b=>b.onclick=()=>invite(s,all.find(r=>r.id===b.dataset.gsInvite)));
  el('gsRows').querySelectorAll('[data-gs-history]').forEach(b=>b.onclick=()=>history(s,all.find(r=>r.id===b.dataset.gsHistory)));
  el('gsRows').querySelectorAll('[data-gs-archive]').forEach(b=>b.onclick=()=>archive(s,all.find(r=>r.id===b.dataset.gsArchive)));
 }
 const canInvite=(s,r)=>s.kind==='positions'&&s.data.can_manage_structure&&s.hub.admin&&r?.active&&r.assignment_enabled&&!r.assigned_user_id&&!/athlete.*rep/i.test(r.title);
 function invite(s,r){
  if(!current(s)||!canInvite(s,r))return;
  const {org,hub,kind,scope}=s;close();
  window.WMOrgInvites.open({org,positionId:r.id,onBack:()=>open({org,hub,kind,scope})});
 }
 function actions(s,r){return s.data.can_manage_structure?`<div class="ops-actions">${canInvite(s,r)?`<button data-gs-invite="${E(r.id)}">Invite to this position</button>`:''}<button class="secondary" data-gs-edit="${E(r.id)}">Edit</button><button class="secondary" data-gs-history="${E(r.id)}">History</button><button class="secondary" data-gs-archive="${E(r.id)}">${(s.kind==='positions'?!r.active:r.status==='archived')?'Reactivate':'Archive / remove'}</button></div>`:'';}
 function positionCard(s,r){const parent=s.data.positions.find(p=>p.id===r.parent_position_id);return `<article class="ops-card"><div class="ops-meta">${E(r.division_name||'Organization')} · Revision ${E(r.revision)}</div><h3>${E(r.title)}</h3><p><b>${E(r.assigned_name||(r.assigned_user_id?'Assigned account':'Vacant'))}</b>${!r.active?' · Archived':''}</p>${!r.assignment_enabled?'<p class="ops-sheet-note">Athlete-representative assignment is deferred.</p>':''}${parent?`<p>Reports to: ${E(parent.title)}</p>`:''}<p class="ops-sheet-note">${E(access.find(a=>a[0]===r.access_role)?.[1]||'Title only · no operational access')}</p>${actions(s,r)}</article>`;}
 function affiliateCard(s,r){return `<article class="ops-card"><div class="ops-meta">${E(r.affiliate_type.replaceAll('_',' '))} · Revision ${E(r.revision)}</div><h3>${E(r.name)}</h3><p>${E(r.status)} · ${E(({unreviewed:'Membership needs review',confirmed:'Membership confirmed',not_current:'Not a current member'})[r.membership_review])}</p><p class="ops-sheet-note">Voting: ${E(({unreviewed:'not reviewed',eligible:'eligible under recorded rule',ineligible:'not eligible'})[r.voting_review])}</p>${r.linked_team_name?`<p>Linked team: ${E(r.linked_team_name)}</p>`:''}${r.linked_organization_name?`<p>Linked organization: ${E(r.linked_organization_name)}</p>`:''}${actions(s,r)}</article>`;}
 function edit(s,r=null){
  if(!current(s)||!s.data.can_manage_structure)return;const pos=s.kind==='positions',isNew=!r;
  s.pending=null;let html='';
  if(pos){
   const candidates=[['','Vacant'],...s.data.directory.map(p=>[p.id,p.name])];
   if(r?.assigned_user_id&&!candidates.some(p=>p[0]===r.assigned_user_id))candidates.push([r.assigned_user_id,(r.assigned_name||'Existing account')+' · requires review']);
   html=field('gsTitle','Position title',r?.title||'',120)+choice('gsDivision','Scope',[['','Organization'],...s.hub.divisions.map(d=>[d.id,d.name])],r?.division_id)+
    choice('gsParent','Reports to',[['','No parent position'],...s.data.positions.filter(p=>p.active&&p.id!==r?.id).map(p=>[p.id,p.title])],r?.parent_position_id)+
    choice('gsPerson','Assigned adult',candidates,r?.assigned_user_id)+
    (!r?.assignment_enabled&&r?'<p class="ops-sheet-note">This athlete-representative post must remain vacant.</p>':'')+
    check('gsAdult','I confirm this is the adult’s own personal account and they are at least 18.')+
    choice('gsAccess','Explicit operational access',access,r?.assigned_user_id?r.access_role:'')+
    check('gsAccessConfirm','I approve the selected operational access for this adult and scope.')+
    '<p class="ops-sheet-note">Use Title only when no operational access is needed. Division and organization access can expose operational records. A title or SafeSport completion alone grants no access. Existing access from other assignments remains separate. Adult confirmation is recorded as your attestation.</p>';
  }else{
   const teams=[['','No team link'],...s.data.linkable_teams.map(t=>[t.id,t.name])],orgs=[['','No organization link'],...s.data.linkable_organizations.map(o=>[o.id,o.name])];
   if(r?.linked_team_id&&!teams.some(x=>x[0]===r.linked_team_id))teams.push([r.linked_team_id,r.linked_team_name||'Existing team link']);
   if(r?.linked_organization_id&&!orgs.some(x=>x[0]===r.linked_organization_id))orgs.push([r.linked_organization_id,r.linked_organization_name||'Existing organization link']);
   html=field('gsTitle','Club, school or organization name',r?.name||'')+
    choice('gsType','Type',['club','school','training_center','organization','other'].map(k=>[k,k.replaceAll('_',' ')]),r?.affiliate_type||'club')+
    choice('gsState','Directory status',[['active','Active'],['inactive','Inactive'],['archived','Archived']],r?.status||'active')+
    choice('gsMembership','Membership review',[['unreviewed','Needs review'],['confirmed','Confirmed member'],['not_current','Not a current member']],r?.membership_review||'unreviewed')+
    choice('gsVoting','Voting eligibility',[['unreviewed','Not reviewed'],['eligible','Eligible under recorded rule'],['ineligible','Not eligible under recorded rule']],r?.voting_review||'unreviewed')+
    area('gsRule','Rule or decision supporting eligibility',r?.review_note||'')+
    field('gsContactName','Contact name (administrators only)',r?.contact?.name||'',250)+field('gsContactEmail','Contact email (administrators only)',r?.contact?.email||'',250)+field('gsContactPhone','Contact phone (administrators only)',r?.contact?.phone||'',250)+
    choice('gsTeam','Link an approved team',teams,r?.linked_team_id)+choice('gsOrg','Link an organization you administer',orgs,r?.linked_organization_id)+
    '<p class="ops-sheet-note">Choose each link explicitly. For an outside team, first approve its affiliation under Wrestling teams. A directory link grants no management or roster access.</p>'+
    area('gsSource','Source / historical directory note',r?.source_note||'',1000);
  }
  shell(s,`${isNew?'Add':'Edit'} ${pos?'position':'affiliate'}`,`<form id="gsForm"><div class="gs-grid">${html}</div><div class="ops-actions"><button id="gsSave" type="submit">Save ${pos?'position':'affiliate'}</button><button id="gsCancel" type="button" class="secondary">Cancel</button><button id="gsReloadRecord" type="button" class="secondary hidden">Reload latest record</button></div></form>`);
  el('gsTitle').required=true;
  if(pos&&r&&!r.assignment_enabled){el('gsPerson').disabled=true;el('gsPerson').value='';}
  let dirty=false;el('gsForm').oninput=()=>{dirty=true;note(s,'Unsaved changes.');};
  if(canInvite(s,r)){
   const button=document.createElement('button');button.type='button';button.className='secondary';button.id='gsInvitePosition';button.textContent='Invite to this position';
   el('gsCancel').before(button);
   button.onclick=()=>{if(!dirty||confirm('Discard unsaved changes and invite to the saved position?'))invite(s,r);};
  }
  el('gsCancel').onclick=()=>{if(!dirty||confirm('Discard unsaved changes?'))render(s);};
  el('gsReloadRecord').onclick=()=>{if(confirm('Reload the saved record and discard these unsaved changes?'))reload(s);};
  el('gsForm').onsubmit=async ev=>{
   ev.preventDefault();if(!current(s)||el('gsSave').disabled)return;
   let q={action:pos?'save_position':'save_affiliate',id:r?.id||null,revision:r?.revision??null,title:val('gsTitle')};
   if(pos)q={...q,division_id:val('gsDivision')||null,parent_position_id:val('gsParent')||null,user_id:val('gsPerson')||null,access_role:val('gsAccess')||null,confirm_adult:el('gsAdult').checked,confirm_access:el('gsAccessConfirm').checked};
   else q={...q,affiliate_type:val('gsType'),status:val('gsState'),membership_review:val('gsMembership'),voting_review:val('gsVoting'),review_note:val('gsRule'),source_note:val('gsSource'),linked_team_id:val('gsTeam')||null,linked_organization_id:val('gsOrg')||null,contact:{name:val('gsContactName'),email:val('gsContactEmail'),phone:val('gsContactPhone')}};
   await save(s,q);
  };
 }
 async function save(s,q){
  // An uncertain network response can be retried without creating another record.
  const signature=JSON.stringify(q);if(!s.pending||s.pending.signature!==signature)s.pending={signature,request_id:crypto.randomUUID()};
  const form=el('gsForm'),button=el('gsSave');const controls=form?[...form.elements]:[];
  controls.forEach(x=>{x.dataset.wasDisabled=x.disabled?'1':'0';x.disabled=true;});if(button)button.disabled=true;note(s,'Saving to organization…');
  try{await call(s,{...q,request_id:s.pending.request_id});if(current(s))await reload(s,'Saved to organization.');}
  catch(err){if(current(s)){note(s,'Not saved or not yet confirmed. '+err.message+' Your changes are still here.',true);if(/changed|Reload/.test(err.message))el('gsReloadRecord')?.classList.remove('hidden');}}
  finally{if(current(s)&&form?.isConnected){controls.forEach(x=>{x.disabled=x.dataset.wasDisabled==='1';});if(button)button.disabled=false;}}
 }
 function archive(s,r){
  const pos=s.kind==='positions',restore=pos?!r.active:r.status==='archived';s.pending=null;
  shell(s,`${restore?'Reactivate':'Archive / remove'} ${pos?r.title:r.name}`,`<p>${restore?(pos?'Reactivate this position with its recorded assignment and permissions?':'Reactivate this affiliate? Membership and voting eligibility will return to Needs review.'):'Remove this record from the current list and keep its full history?'}</p><form id="gsForm"><div class="ops-actions"><button id="gsSave" type="submit">${restore?'Reactivate':'Archive record'}</button><button type="button" class="secondary" id="gsCancel">Cancel</button></div></form>`);
  el('gsCancel').onclick=()=>render(s);el('gsForm').onsubmit=ev=>{ev.preventDefault();save(s,{action:(restore?'restore_':'archive_')+(pos?'position':'affiliate'),id:r.id,revision:r.revision});};
 }
 function templates(s){
  const type=s.hub.organizations?.find(o=>o.id===s.org)?.organization_type||'club';s.pending=null;
  shell(s,'Position templates',`<p>Creates vacant posts with no access grants. Existing titles and assignments stay as recorded.</p><form id="gsForm">${choice('gsPreset','Template',[['wawa','WAWA · supplied January 2026 titles'],['association','Association · starter titles'],['club','Club · starter titles'],['school','School · starter titles'],['school_district','School district · starter titles']],type)}<ul id="gsPresetList"></ul><div class="ops-actions"><button id="gsSave" type="submit">Add missing posts</button><button id="gsCancel" class="secondary" type="button">Cancel</button></div></form>`);
  const preview=()=>{el('gsPresetList').innerHTML=presets[val('gsPreset')].map(t=>`<li>${E(t)}</li>`).join('');};preview();el('gsPreset').onchange=preview;el('gsCancel').onclick=()=>render(s);el('gsForm').onsubmit=ev=>{ev.preventDefault();save(s,{action:'add_presets',preset:val('gsPreset')});};
 }
 async function history(s,r){
  shell(s,'History · '+(r.title||r.name),'<button id="gsBack" class="secondary">Back to list</button><div id="gsHistory">Loading revisions…</div>');el('gsBack').onclick=()=>render(s);
  const panel=el('gsHistory');try{const rows=await call(s,{action:'history',entity_kind:s.kind==='positions'?'position':'affiliate',id:r.id});if(!current(s)||!panel.isConnected)return;
   panel.innerHTML=rows.map(v=>{const p=v.snapshot;return `<article class="ops-card"><h3>Revision ${E(v.revision)}</h3><p>${E(new Date(v.recorded_at).toLocaleString())} · ${E(v.actor_name||'System migration')}</p><p>${E(v.reason.replaceAll('_',' '))}</p><p>${E(p.title||p.name)} · ${E(p.status||(p.active?'Active':'Archived'))}</p>${s.kind==='positions'?`<p>Assignment: ${E(s.data.directory.find(d=>d.id===p.assigned_user_id)?.name||p.assigned_user_id||'Vacant')}</p><p>Access: ${E(p.access_role||'Title only')}</p>`:`<p>Membership: ${E(p.membership_review||'Unreviewed')} · Voting: ${E(p.voting_review||'Unreviewed legacy value')}</p><p>${E(p.review_note||'')}</p>`}</article>`;}).join('')||'<p>No recorded revisions.</p>';
  }catch(err){if(current(s)&&panel.isConnected)panel.textContent=err.message;}
 }
 return {open,close};
})();
