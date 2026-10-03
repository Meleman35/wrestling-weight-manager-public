/* Presentation only: retain existing nodes, handlers and permission classes. */
(()=>{
 'use strict';
 const sheet=document.getElementById('accountSheet');if(!sheet)return;
 const style=document.createElement('style');style.id='wm-account-layout-style';style.textContent=`
 #accountSheet .account-settings-group{margin:18px 0;border:1px solid var(--line,#dce3eb);border-radius:16px;padding:14px;background:#fff}
 #accountSheet .account-settings-group h3,#accountSheet .account-profile-editor>summary{font-size:16px;font-weight:750;margin:0 0 10px}
 #accountSheet .account-settings-group button.wide,#accountSheet .account-settings-group a.account-nav-row{display:flex;align-items:center;justify-content:space-between;text-align:left;width:100%;min-height:48px;margin:0;padding:13px 12px;border:0;border-bottom:1px solid #e6ebf1;border-radius:0;background:transparent;color:var(--ink,#12161b);box-shadow:none!important;transform:none!important;text-decoration:none;font-size:15px;font-weight:600;line-height:1.4;gap:12px}
 #accountSheet .account-settings-group button.wide::after,#accountSheet a.account-nav-row::after{content:'›';flex-shrink:0;color:#607087;font-size:22px}
 #accountSheet .account-settings-group button.wide:hover,#accountSheet a.account-nav-row:hover{background:#eef3f8}
 #accountSheet .account-settings-group button.wide:focus-visible,#accountSheet a.account-nav-row:focus-visible,#accountSheet summary:focus-visible{outline:3px solid #396dd5;outline-offset:2px}
 #accountSheet .account-settings-group .hidden{display:none!important}
 #accountSheet .account-profile-editor{margin:18px 0;border:1px solid #dce3eb;border-radius:16px;padding:16px}
 #accountSheet .account-profile-editor>summary{cursor:pointer;min-height:30px;margin:0}
 #accountSheet .account-profile-editor[open]>summary{margin-bottom:14px}
 #accountSheet .account-profile-editor .feature-card{margin:0;border:0;padding:0;box-shadow:none}
 #accountSheet .account-profile-editor #saveAccountProfileBtn{margin-top:14px}
 #accountSheet .account-settings-group[hidden]{display:none}
 #accountSheet .wm-info-links{margin:18px 0}
 `;document.head.append(style);
 const groups={};
 for(const [key,label] of [['personal','My profile & connections'],['family','Family & parent controls'],['team','Team administration'],['preferences','Preferences & security'],['tools','Match & device tools'],['creator','Creator & testing']]){
  const group=document.createElement('section');group.className='account-settings-group';group.dataset.accountGroup=key;
  const heading=document.createElement('h3');heading.id='accountGroup-'+key;heading.textContent=label;group.setAttribute('aria-labelledby',heading.id);group.append(heading);groups[key]=group;
 }
 const profile=document.getElementById('personalAccountProfileCard');
 const editor=document.createElement('details');editor.className='account-profile-editor';
 const summary=document.createElement('summary');summary.textContent='Edit account profile';editor.append(summary);
 if(profile){profile.before(editor);editor.append(profile);}
 const ids={personal:['editStaffProfileBtn','switchTeamProfileBtn','myPrivateBallots'],family:['parentControlsAccountBtn','accountMyAthletes'],team:['teamLoginsBtn','editTeamBtn','communicationBtn','weightScheduleSettingsBtn','athleteCardsSettingsBtn'],preferences:['communicationPreferencesBtn','customizeLayoutBtn','securityBtn','weightPinSettingsBtn'],tools:['offlineEntry'],creator:['creatorOffersBtn','creatorAccountRolePreviewBtn','weightTestsSettingsBtn']};
 const labels=[['Family circle','family'],['Find Profiles','personal'],['My profile ·','personal'],['Profile chats','personal']];
 for(const node of [...sheet.children]){
  let key=Object.keys(ids).find(k=>ids[k].includes(node.id));
  if(node.matches('[data-wm-mat-mode]')){key='tools';node.classList.add('account-nav-row');node.setAttribute('aria-label',node.textContent.trim());}
  if(!key&&node.matches('button'))key=labels.find(([text])=>node.textContent.startsWith(text))?.[1];
  if(key)groups[key].append(node);
 }
 const anchor=sheet.querySelector('.wm-info-links')||document.getElementById('signOutBtn');
 for(const group of Object.values(groups))sheet.insertBefore(group,anchor);
 function sync(){
  const hideEditor=!!profile&&(profile.hidden||profile.classList.contains('hidden'));
  if(editor.hidden!==hideEditor)editor.hidden=hideEditor;
  for(const group of Object.values(groups)){
   const empty=[...group.children].slice(1).every(n=>n.hidden||n.classList.contains('hidden')||n.style.display==='none');
   if(group.hidden!==empty)group.hidden=empty;
  }
 }
 new MutationObserver(sync).observe(sheet,{subtree:true,attributes:true,attributeFilter:['class','hidden','style']});sync();
})();
