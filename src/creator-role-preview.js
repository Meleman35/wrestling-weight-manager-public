/* Creator-only entry into a static, credential-free role walkthrough. No impersonation. */
(() => {
 'use strict';
 const $p=id=>document.getElementById(id),sheet=document.createElement('section');
 sheet.id='creatorRolePreviewSheet';sheet.className='sheet hidden';sheet.setAttribute('role','dialog');sheet.setAttribute('aria-modal','true');sheet.setAttribute('aria-labelledby','creatorRolePreviewTitle');
 sheet.innerHTML='<header class="role-preview-head"><div><div class="eyebrow">APP CREATOR · DEMO</div><h2 id="creatorRolePreviewTitle">Explore Role Views</h2></div><button type="button" class="secondary" id="creatorRolePreviewClose">← Creator</button></header><p id="creatorRolePreviewStatus" role="status"></p><div id="creatorRolePreviewMount"></div>';
 document.body.append(sheet);
 const homeButton=document.createElement('button');homeButton.type='button';homeButton.id='creatorHomeRolePreviewBtn';homeButton.className='wide secondary hidden';homeButton.textContent='Explore Role Views · Demo';$p('creatorHomeOffersBtn').after(homeButton);
 const accountButton=document.createElement('button');accountButton.type='button';accountButton.id='creatorAccountRolePreviewBtn';accountButton.className='wide secondary hidden';accountButton.textContent='Explore Role Views · Demo';$p('creatorOffersBtn').after(accountButton);
 let epoch=0,owner='',frame=null,checking=false,lastCheck=0,opener=null;
 const context=()=>session?.user?.id&&!managedLogin?session.user.id+'|'+(activeTeam?.id||''):'';
 const unlocked=()=>!!context()&&!document.hidden&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)');
 const current=g=>g===epoch&&owner===context()&&unlocked()&&navigator.onLine&&!sheet.classList.contains('hidden');
 function entries(visible){show(homeButton.id,visible);show(accountButton.id,visible)}
 function syncEntries(){entries(unlocked()&&navigator.onLine&&(!$p('creatorOffersBtn').classList.contains('hidden')||!$p('creatorHomePanel').classList.contains('hidden')))}
 function dispose(){frame?.remove();frame=null;$p('creatorRolePreviewMount').replaceChildren()}
 function close(){epoch++;owner='';checking=false;lastCheck=0;dispose();$p('creatorRolePreviewStatus').textContent='';show(sheet.id,false);recoverInteractionLayer()}
 function exit(){const target=opener,returnToDashboard=target?.id==='creatorDashboardRolePreviewBtn'&&owner===context()&&unlocked()&&navigator.onLine;closeSheets();if(returnToDashboard){void window.WMCreatorOffers?.open();return}if(target?.isConnected&&!target.classList.contains('hidden'))target.focus()}
 async function authorize(g){
  const {data,error}=await client.rpc('creator_offers_request',{p_action:'access',p_data:{client:'creator-linked-v1'}});
  if(!current(g))return false;
  if(error||data?.creator!==true){dispose();entries(false);$p('creatorRolePreviewStatus').textContent='Creator access could not be confirmed. Reconnect and reopen this preview.';return false}
  lastCheck=Date.now();return true;
 }
 async function open(){
  if(!unlocked()||!navigator.onLine){message('Unlock your personal account and reconnect to open Creator previews.',true);return}
  opener=document.activeElement;closeSheets();owner=context();const g=++epoch;
  openSheet(sheet.id);$p('creatorRolePreviewStatus').textContent='Checking Creator access…';$p('creatorRolePreviewClose').focus();checking=true;
  try{
   if(!await authorize(g)||!current(g))return;
   if(typeof window.WMRolePreviewDocument!=='string')throw Error('preview_unavailable');
   frame=document.createElement('iframe');frame.id='creatorRolePreviewFrame';frame.title='Fictional account role walkthrough';frame.setAttribute('sandbox','allow-scripts');frame.setAttribute('referrerpolicy','no-referrer');
   frame.setAttribute('allow',"camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'; clipboard-read 'none'; clipboard-write 'none'; usb 'none'; serial 'none'");
   frame.srcdoc=window.WMRolePreviewDocument;$p('creatorRolePreviewMount').replaceChildren(frame);$p('creatorRolePreviewStatus').textContent='';
  }catch{if(current(g)){dispose();$p('creatorRolePreviewStatus').textContent='The preview could not open. Reconnect and try again.'}}
  finally{if(g===epoch)checking=false}
 }
 homeButton.onclick=open;accountButton.onclick=open;$p('creatorRolePreviewClose').onclick=exit;
 new MutationObserver(syncEntries).observe($p('creatorOffersBtn'),{attributes:true,attributeFilter:['class']});
 setInterval(()=>{
  syncEntries();
  if(owner&&(!unlocked()||owner!==context()||!navigator.onLine||sheet.classList.contains('hidden'))){close();return}
  if(!owner||!frame||checking||Date.now()-lastCheck<15000)return;
  checking=true;const g=epoch;authorize(g).catch(()=>{if(current(g)){dispose();entries(false);$p('creatorRolePreviewStatus').textContent='Creator access could not be rechecked. Reopen the preview when connected.'}}).finally(()=>{if(g===epoch)checking=false});
 },300);
 window.addEventListener('offline',()=>{close();entries(false)});
 document.addEventListener('visibilitychange',()=>{if(document.hidden){close();entries(false)}});
 document.addEventListener('keydown',e=>{if(e.key==='Escape'&&owner){e.preventDefault();exit()}});
 window.addEventListener('message',e=>{if(frame&&e.source===frame.contentWindow&&e.origin==='null'&&e.data?.type==='wm-role-preview-close'&&owner)exit()});
 window.WMCreatorRolePreview={open,close};syncEntries();
})();
