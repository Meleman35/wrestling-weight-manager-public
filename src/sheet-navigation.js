/* Keep the previous screen alive during a transition; final Close clears it. */
window.WMSheetNavigation=(()=>{
 const stack=[];let owner='',focus=null,scroll=0;
 const context=()=>[session?.user?.id,activeTeam?.id,!!managedLogin].join(':');
 const usable=()=>!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)');
 const visible=()=>[...document.querySelectorAll('.sheet:not(.hidden)')];
 function reset(){stack.length=0;owner='';focus=null;}
 function open(id){
  if(!usable())return;
  const next=document.getElementById(id);if(!next)return;
  if(owner!==context()){reset();owner=context();}
  const panels=visible().filter(p=>p.id!==id);
  if(!panels.length&&!stack.length){focus=document.activeElement;scroll=window.scrollY;}
  const existing=stack.findIndex(x=>x.id===id);
  if(existing>=0)stack.splice(existing);
  else for(const panel of panels)stack.push({id:panel.id,scroll:panel.scrollTop,focus:document.activeElement});
  if(panels.some(p=>p.id==='matchScoreSheet'))window.WMMatch?.suspend();
  for(const panel of panels)panel.classList.add('hidden');
  if(!next.querySelector(':scope > .sheet-returnbar')){
   const bar=document.createElement('div');bar.className='sheet-returnbar';
   const button=document.createElement('button');button.type='button';button.className='secondary';button.dataset.sheetBack='';button.textContent='‹ Back';
   button.onclick=()=>back().catch(e=>message(e.message,true));bar.append(button);next.prepend(bar);
  }
 }
 async function back(){
  if(!usable())return;if(owner!==context()){closeSheets();return;}
  const current=visible().at(-1);
  if(current?.id==='wrestlingProfilesSheet'&&await window.WMProfiles?.back())return;
  if(current?.id==='matchScoreSheet')window.WMMatch?.suspend();
  const prior=stack.pop();
  if(!prior){const target=focus,y=scroll;closeSheets();window.scrollTo(0,y);if(target?.isConnected)target.focus({preventScroll:true});return;}
  for(const panel of visible())panel.classList.add('hidden');
  const panel=document.getElementById(prior.id);if(!panel){closeSheets();return;}
  panel.classList.remove('hidden');panel.scrollTop=prior.scroll;
  syncLockerRoomTabs(prior.id);
  if(prior.focus?.isConnected&&panel.contains(prior.focus))prior.focus.focus({preventScroll:true});
 }
 return {open,back,reset};
})();
