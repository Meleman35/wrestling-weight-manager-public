(function(){
 const sheet=document.getElementById('athleteCardSheet');
 const panel=document.createElement('details');panel.id='bulkAthleteCards';panel.className='feature-card';
 panel.innerHTML='<summary>Print team athlete cards</summary><p class="fine">Choose athletes and print at 100% actual size. NFC chips must be programmed separately.</p><button type="button" class="secondary" data-all>Select all</button><div data-list></div><label>PDF format<select data-format><option value="sheet">Letter sheets · 8 cards per page</option><option value="individual">Individual credit-card size pages</option></select></label><button type="button" class="wide" data-export>Download selected cards</button><p role="status" data-status></p>';
 sheet.append(panel);let busy=false;
 const list=panel.querySelector('[data-list]'),status=panel.querySelector('[data-status]'),button=panel.querySelector('[data-export]');
 function paint(){panel.hidden=!actualIsStaff||!session?.user?.id;list.replaceChildren();for(const a of athleteCardRows){const label=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.value=a.athlete_id;label.append(box,document.createTextNode(' '+[a.first_name,a.last_name].filter(Boolean).join(' ')));list.append(label);}status.textContent='';}
 new MutationObserver(paint).observe(document.getElementById('athleteCardSelect'),{childList:true});
 panel.querySelector('[data-all]').onclick=()=>{if(!busy)list.querySelectorAll('input').forEach(x=>x.checked=true);};
 button.onclick=async()=>{
  if(busy||!actualIsStaff)return;busy=true;
  const teamID=activeTeam?.id,userID=session?.user?.id,version=athleteCardRequestVersion;
  const current=()=>actualIsStaff&&activeTeam?.id===teamID&&session?.user?.id===userID&&version===athleteCardRequestVersion&&!sheet.classList.contains('hidden');
  panel.querySelectorAll('button,input,select').forEach(x=>x.disabled=true);
  try{
   const cards=await collectAthleteCards({roster:athleteCardRows,selectedIDs:[...list.querySelectorAll('input:checked')].map(x=>x.value),isCurrent:current,
    loadCard:async id=>{const {data,error}=await client.rpc('get_athlete_scan_card',{p_team_id:teamID,p_athlete_id:id,p_replace:false});if(error)throw error;return data;},
    onProgress:(n,total)=>{status.textContent=`Preparing card ${n} of ${total}…`;}});
   const bytes=await renderAthleteCardPDF({cards,teamName:activeTeam.name,individual:panel.querySelector('[data-format]').value==='individual',PDFLib:window.PDFLib,document,QRCode,isCurrent:current});
   if(!current())return;const blob=new Blob([bytes],{type:'application/pdf'}),file=new File([blob],'Team-Athlete-Cards.pdf',{type:'application/pdf'});
   if(navigator.canShare?.({files:[file]}))await navigator.share({files:[file],title:'Team athlete cards'});
   else{const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=file.name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);}
   if(current())status.textContent='Cards ready. Print at 100% actual size.';
  }catch(e){if(current())status.textContent=e.name==='AbortError'?'Sharing cancelled.':'Export could not finish. Check your connection and try again.';}
  finally{busy=false;panel.querySelectorAll('button,input,select').forEach(x=>x.disabled=false);}
 };
})();
