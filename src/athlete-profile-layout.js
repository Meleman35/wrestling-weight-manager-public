/* Athlete profile presentation. Existing fields, controls and authorization stay intact. */
(()=>{
 'use strict';
 const editor=document.getElementById('athleteProfileSheet');
 const style=document.createElement('style');style.textContent=`
 #athleteProfileSheet .athlete-profile-section{margin:18px 0;padding:16px;border:1px solid #dce3eb;border-radius:16px;background:#fff}
 #athleteProfileSheet .athlete-profile-section>h3{font-size:16px;margin:0 0 14px}
 #athleteProfileSheet .profile-tools{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
 #athleteProfileSheet .profile-tools button,#wpBody>.wp-actions button{min-height:48px;background:#eef3f8;color:var(--ink,#12161b);box-shadow:none!important;transform:none!important;border:1px solid #dce3eb;border-radius:12px;padding:12px;text-align:left;font-weight:600;margin:0}
 #wpBody>.wp-actions{display:grid;gap:14px;margin:18px 0}
 #wpBody .profile-action-section{padding:14px;border:1px solid #dce3eb;border-radius:16px}
 #wpBody .profile-action-section h3{font-size:15px;margin:0 0 10px}
 #wpBody .profile-action-rows{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
 #athleteProfileSheet .hidden,#wpBody .hidden{display:none!important}
 @media(max-width:480px){#athleteProfileSheet .profile-tools,#wpBody .profile-action-rows{grid-template-columns:minmax(0,1fr)}}
 `;document.head.append(style);
 if(editor){
  const quick=document.createElement('section');quick.className='athlete-profile-section';
  const title=document.createElement('h3');title.textContent='Athlete tools';quick.append(title);
  const rows=document.createElement('div');rows.className='profile-tools';quick.append(rows);
  const first=document.getElementById('profileAthleteGoalsBtn');first.before(quick);
  for(const id of ['profileAthleteGoalsBtn','profileAttendanceBtn','profileAthleteCardBtn','profileWeightTrendBtn'])rows.append(document.getElementById(id));
  function wrap(start,end,label){
   const children=[...editor.children],a=children.indexOf(start),b=children.indexOf(end);if(a<0||b<=a)return;
   const section=document.createElement('section');section.className='athlete-profile-section';
   const heading=document.createElement('h3');heading.textContent=label;section.append(heading);start.before(section);
   for(const node of children.slice(a,b))section.append(node);
  }
  const contact=[...editor.children].find(n=>n.matches('h3')&&n.textContent==='Contact');
  const gear=[...editor.children].find(n=>n.matches('h3')&&n.textContent==='Gear sizes');
  const medical=editor.querySelector(':scope > .medical-box');
  wrap(document.getElementById('profileFirstName').closest('.profile-grid'),contact,'Athlete details');
  wrap(contact,gear,'Contact & family');contact?.remove();
  wrap(gear,medical,'Gear sizes');gear?.remove();
 }
 const body=document.getElementById('wpBody');if(!body)return;
 function organize(){
  const actions=body.querySelector(':scope > .wp-actions');if(!actions||actions.dataset.organized)return;
  actions.dataset.organized='true';const sections={};
  for(const [key,label] of [['athlete','Athlete tools'],['profile','Profile settings'],['connections','Connections & sharing']]){
   const section=document.createElement('section');section.className='profile-action-section';
   const title=document.createElement('h3');title.textContent=label;
   const rows=document.createElement('div');rows.className='profile-action-rows';section.append(title,rows);sections[key]={section,rows};
  }
  for(const button of [...actions.children]){
   const key=button.matches('[data-wp-trophy],[data-wp-goals]')?'athlete':button.matches('[data-wp-name],[data-wp-edit],[data-profile-approvals]')?'profile':'connections';
   sections[key].rows.append(button);
  }
  for(const {section,rows} of Object.values(sections))if(rows.children.length)actions.append(section);
 }
 new MutationObserver(organize).observe(body,{childList:true});organize();
})();
