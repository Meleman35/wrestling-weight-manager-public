/* Category and nested tool preferences share the existing account layout. */
(() => {
 const groups=[
  {id:'people',icon:'👥',name:'People & Roles',detail:'Roster, leaders, parents & goals',ids:['staffAccessBtn','rosterBtn','joinRequestsBtn','joinBtn','staffDirectoryBtn','teamGoalsBtn','memberProfilesBtn','familyBtn','findProfilesBtn']},
  {id:'practice',icon:'🤼',name:'Practice & Competition',detail:'Attendance, lineup & Match Book',ids:['tournamentDayBtn','clipboardAttendanceBtn','clipboardLineupBtn','matchBookBtn']},
  {id:'health',icon:'✍️',name:'Forms & Health',detail:'Agreements & medical clearance',ids:['agreementsBtn','medicalClearanceBtn']},
  {id:'gear',icon:'🎒',name:'Gear & Files',detail:'Equipment & team resources',ids:['clipboardEquipmentBtn','clipboardFilesBtn']},
  {id:'settings',icon:'⚙️',name:'Settings',detail:'Account, team settings & feedback',ids:['accountBtn','feedbackBtn']},
  {id:'organization',icon:'🏛️',name:'Organization',detail:'Teams, leadership & organization tools',ids:['organizationHubBtn'],direct:'organizationHubBtn'}
 ];
 let selected=null,context='';const e=id=>document.getElementById(id),key=g=>'clip_'+g.id;
 const mode=()=>isStaff||isManager;
 // Hidden originals live in the legacy Toolbox; category preferences govern the proxies.
 function accessible(node){return node&&!node.disabled&&!node.classList.contains('hidden')&&!node.classList.contains('hidden-role')&&(!node.classList.contains('member-only')||node.classList.contains('show'));}
 function tools(g){return g.ids.map(e).filter(accessible);}
 UI_LAYOUT_META.clipboard=Object.fromEntries(groups.map(g=>[g.id,[g.icon,g.name]]));DEFAULT_UI_LAYOUT.clipboard=groups.map(g=>g.id);
 for(const g of groups){UI_LAYOUT_META[key(g)]=Object.fromEntries(g.ids.map(id=>{const n=e(id);return [id,[n?.querySelector('span')?.textContent||'›',n?.querySelector('b')?.textContent||id]];}));DEFAULT_UI_LAYOUT[key(g)]=g.ids;}
 const edit=e('clipboardCustomizeBtn');edit.onclick=()=>{openLayoutEditor();requestAnimationFrame(()=>e('clipboardLayoutEditors').scrollIntoView({block:'start'}));};
 function upgrade(source){
  // Carry legacy Toolbox order/visibility into each category until separately customized.
  source={...source,hidden:{...source.hidden}};
  for(const g of groups){const k=key(g);if(Array.isArray(source[k]))continue;const ids=g.ids,order=source.more||[];source[k]=[...ids].sort((a,b)=>{const at=id=>{const n=order.indexOf(e(id)?.dataset.layoutKey);return n<0?999:n;};return at(a)-at(b);});source.hidden[k]=ids.filter(id=>(source.hidden.more||[]).includes(e(id)?.dataset.layoutKey));}
  return source;
 }
 function parent(group){return group==='clipboard'?e('clipboardCategoryGrid'):selected&&group==='clip_'+selected?e('clipboardCategoryTools'):null;}
 function editors(){const box=e('clipboardLayoutEditors');if(!box)return;box.innerHTML='<h3>Clipboard categories</h3><div id="clipboardMainEditor"></div>'+groups.filter(g=>!g.direct).map(g=>`<h3>${esc(g.name)} tools</h3><div id="clipEditor_${g.id}"></div>`).join('');renderLayoutGroup('clipboard','clipboardMainEditor');for(const g of groups)if(!g.direct)renderLayoutGroup(key(g),'clipEditor_'+g.id);}
 function reset(){selected=null;render();}
 function render(){
  if(!e('clipboardCategories'))return;const next=[session?.user?.id,activeTeam?.id,mode(),viewMode].join(':');if(context!==next){context=next;selected=null;}
  const enabled=mode();show('clipboardCategories',enabled);show('clipboardQuickTools',false);show('clipboardQuickHeading',false);show('moreMenuCard',!enabled);show('clipboardLeadersBtn',enabled&&!!window.WMTeamPeople?.allowed());
  if(!enabled){selected=null;show('clipboardCategoryPanel',false);return;}
  const available=groups.filter(g=>tools(g).length);
  e('clipboardCategoryGrid').innerHTML=available.map(g=>`<button type="button" class="clipboard-tile" data-layout-key="${g.id}" data-clipboard-category="${g.id}" ${g.direct?'aria-haspopup="dialog"':`aria-expanded="${selected===g.id}"`}><span>${g.icon}</span><span><b>${esc(g.name)}</b><small>${esc(g.detail)}</small></span></button>`).join('');
  e('clipboardCategoryGrid').querySelectorAll('[data-clipboard-category]').forEach(b=>b.onclick=()=>{
   const group=available.find(g=>g.id===b.dataset.clipboardCategory);if(!group||!mode())return;
   if(group.direct){const node=e(group.direct);if(accessible(node))node.click();else render();return;}
   selected=group.id;render();e('clipboardCategoryTitle').focus();
  });
  const group=available.find(g=>g.id===selected);show('clipboardCategoryGrid',!group);show('clipboardCategoryPanel',!!group);
  e('clipboardCategoryTools').innerHTML='';
  if(group){
   e('clipboardCategoryTitle').textContent=group.name;
   e('clipboardCategoryTools').innerHTML=tools(group).map(node=>`<button type="button" class="menu-row" data-layout-key="${node.id}" data-clipboard-tool="${node.id}"><span>${esc(node.querySelector('span')?.textContent||'›')}</span><div><b>${esc(node.querySelector('b')?.textContent||node.textContent)}</b><small>${esc(node.querySelector('small')?.textContent||'')}</small></div><i>›</i></button>`).join('');
   e('clipboardCategoryTools').querySelectorAll('[data-clipboard-tool]').forEach(b=>b.onclick=()=>{const node=e(b.dataset.clipboardTool);if(accessible(node)&&mode())node.click();else render();});
  }else selected=null;
  applyUiPreferences();
 }
 e('clipboardCategoryBack').onclick=()=>{const previous=selected;reset();e('clipboardCategoryGrid').querySelector(`[data-clipboard-category="${previous}"]`)?.focus();};
 window.WMClipboard={sync:render,reset,parent,editors,upgrade};render();
})();
