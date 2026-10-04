(function(){
 const allowed=()=>actualIsStaff&&!managedLogin&&!!session?.user?.id&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)');
 const sheet=document.getElementById('athleteCardSheet');
 const panel=document.createElement('details');panel.id='bulkAthleteCards';panel.className='feature-card';
 panel.innerHTML='<summary>Print team athlete cards</summary><p class="fine">Choose up to 500 athletes per PDF and print at 100% actual size. NFC chips must be programmed separately.</p><button type="button" class="secondary" data-all>Select all</button><div data-list></div><label>PDF format<select data-format><option value="sheet">Letter sheets · 8 cards per page</option><option value="individual">Individual credit-card size pages</option></select></label><button type="button" class="wide" data-export>Prepare selected cards</button><p role="status" data-status></p>';
 sheet.append(panel);let busy=false,exportEpoch=0,prepared=null,preparedTimer=null;
 const list=panel.querySelector('[data-list]'),status=panel.querySelector('[data-status]'),button=panel.querySelector('[data-export]');
 function discardPrepared(){prepared=null;if(preparedTimer)clearTimeout(preparedTimer);preparedTimer=null;button.textContent='Prepare selected cards';}
 function syncVisibility(){panel.hidden=!allowed();if(!allowed()||sheet.classList.contains('hidden')){++exportEpoch;discardPrepared();status.textContent='';}}
 function paint(){++exportEpoch;discardPrepared();syncVisibility();list.replaceChildren();for(const a of athleteCardRows){const label=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.value=a.athlete_id;box.disabled=busy;label.append(box,document.createTextNode(' '+[a.first_name,a.last_name].filter(Boolean).join(' ')));list.append(label);}status.textContent='';}
 new MutationObserver(paint).observe(document.getElementById('athleteCardSelect'),{childList:true});
 const visibilityObserver=new MutationObserver(syncVisibility);
 for(const el of [document.body,sheet,document.getElementById('appLockOverlay')].filter(Boolean))visibilityObserver.observe(el,{attributes:true,attributeFilter:['class']});
 paint();
 panel.querySelector('[data-all]').onclick=()=>{if(!busy){discardPrepared();status.textContent='';list.querySelectorAll('input').forEach(x=>x.checked=true);}};
 panel.addEventListener('change',()=>{discardPrepared();status.textContent='';});
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'){++exportEpoch;discardPrepared();status.textContent='';}});
 button.onclick=async()=>{
  if(busy||!allowed())return;
  if(prepared){
   const ready=prepared;if(!ready.current()){discardPrepared();status.textContent='The team or account changed. Prepare the cards again.';return;}
   busy=true;button.disabled=true;
   try{
    // Sharing starts directly from this new tap. Preparing a large PDF can
    // outlast the browser's transient user activation from the first tap.
    const bridge=window.webkit?.messageHandlers?.officialWeighInExport;
    if(bridge&&ready.nativePayload){bridge.postMessage(ready.nativePayload);if(ready.current())status.textContent='Share requested. Choose a destination in the share window, then print at 100% actual size.';}
    else if(navigator.canShare?.({files:[ready.file]})){await navigator.share({files:[ready.file],title:'Team athlete cards'});if(ready.current())status.textContent='Cards ready. Print at 100% actual size.';}
    else if(window.webkit?.messageHandlers){if(ready.current())status.textContent='This app build cannot share PDFs yet. Open the app in Safari to save your cards.';}
    else{const url=URL.createObjectURL(ready.file),a=document.createElement('a');a.href=url;a.download=ready.file.name;a.target='_blank';a.rel='noopener noreferrer';panel.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);if(ready.current())status.textContent='PDF download requested. Print at 100% actual size.';}
   }catch(e){if(ready.current())status.textContent=e.name==='AbortError'?'Sharing cancelled. Tap Save or share PDF to try again.':'PDF could not be shared. Try saving from your browser.';}
   finally{busy=false;button.disabled=false;}return;
  }
  const selectedIDs=[...list.querySelectorAll('input:checked')].map(x=>x.value);
  if(!selectedIDs.length||selectedIDs.length>500){status.textContent='Select between 1 and 500 athletes for this PDF.';return;}
  busy=true;
  const teamID=activeTeam?.id,userID=session?.user?.id,version=athleteCardRequestVersion,epoch=exportEpoch,exportSession=session;
  const current=()=>allowed()&&session===exportSession&&epoch===exportEpoch&&activeTeam?.id===teamID&&session?.user?.id===userID&&version===athleteCardRequestVersion&&!sheet.classList.contains('hidden');
  panel.querySelectorAll('button,input,select').forEach(x=>x.disabled=true);
  try{
   const cards=await collectAthleteCards({roster:athleteCardRows,selectedIDs,isCurrent:current,
    loadCard:async id=>{const {data,error}=await client.rpc('get_athlete_scan_card',{p_team_id:teamID,p_athlete_id:id,p_replace:false});if(error)throw error;return data;},
    onProgress:(n,total)=>{status.textContent=`Preparing card ${n} of ${total}…`;}});
   const bytes=await renderAthleteCardPDF({cards,teamName:activeTeam.name,individual:panel.querySelector('[data-format]').value==='individual',PDFLib:window.PDFLib,document,QRCode,isCurrent:current,loadPhoto:async path=>{
    const url=await athletePhotoUrl(path);if(!url||!current())return null;
    return await new Promise(resolve=>{const img=new Image();img.crossOrigin='anonymous';const timer=setTimeout(()=>{img.src='';resolve(null);},10000);img.onload=()=>{clearTimeout(timer);resolve(current()?img:null);};img.onerror=()=>{clearTimeout(timer);resolve(null);};img.src=url;});
   }});
   if(!current())return;
   // Match the installed native PDF handler's exact decoded-byte limit.
   if(bytes.byteLength>20000000){status.textContent='This PDF is too large. Select fewer athletes and prepare it again.';return;}
   let nativePayload=null;
   if(window.webkit?.messageHandlers?.officialWeighInExport){let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));nativePayload={filename:'Team-Athlete-Cards.pdf',base64:btoa(binary)};}
   prepared={file:new File([bytes],'Team-Athlete-Cards.pdf',{type:'application/pdf'}),nativePayload,current};
   button.textContent='Save or share PDF';status.textContent='PDF prepared. Tap Save or share PDF, then print at 100% actual size.';
   preparedTimer=setTimeout(()=>{discardPrepared();if(current())status.textContent='Prepared PDF cleared. Prepare the cards again when ready.';},120000);
  }catch(e){if(current())status.textContent=e.name==='AbortError'?'Sharing cancelled.':'Export could not finish. Check your connection and try again.';}
  finally{busy=false;panel.querySelectorAll('button,input,select').forEach(x=>x.disabled=false);}
 };
})();
