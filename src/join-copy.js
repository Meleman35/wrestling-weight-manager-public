/* Browser and WKWebView copying; no unacknowledged native bridge success. */
async function copyText(text,options={}){
 const value=String(text??'');let copied=false;
 try{if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(value);copied=true;}}catch{}
 if(options.isCurrent&&!options.isCurrent())return false;
 if(!copied){
  const previous=document.activeElement,box=document.createElement('textarea');
  box.value=value;box.readOnly=true;box.style.cssText='position:fixed;top:0;left:0;width:1px;height:1px;opacity:.01;font-size:16px';
  document.body.append(box);box.focus();box.select();box.setSelectionRange(0,value.length);
  try{copied=document.execCommand('copy')===true;}catch{}finally{box.remove();previous?.focus?.({preventScroll:true});}
 }
 const status=options.status;
 if(copied){if(status?.isConnected)status.textContent='Copied. Paste the link wherever you want to share it.';else message('Copied.');return true;}
 let field=options.field;
 if(!field?.isConnected){
  let dialog=document.getElementById('manualCopyDialog');
  if(!dialog){dialog=document.createElement('dialog');dialog.id='manualCopyDialog';dialog.innerHTML='<h2>Copy link</h2><p>Automatic copying is unavailable here. Select the link below and choose Copy.</p><label for="manualCopyValue">Link</label><textarea id="manualCopyValue" readonly rows="4"></textarea><button type="button">Done</button>';document.body.append(dialog);dialog.querySelector('button').onclick=()=>dialog.close();}
  field=dialog.querySelector('textarea');field.value=value;if(!dialog.open)dialog.showModal();
 }
 field.value=value;field.focus();field.select();field.setSelectionRange(0,value.length);
 if(status?.isConnected)status.textContent='Select the link above and choose Copy. Automatic copying is unavailable here.';
 return false;
}
let teamJoinGeneration=0;
async function showTeamJoin(){
 if(!activeTeam||!session?.user?.id)return;
 const team={id:activeTeam.id,name:activeTeam.name},uid=session.user.id,g=++teamJoinGeneration;
 const current=()=>g===teamJoinGeneration&&session?.user?.id===uid&&activeTeam?.id===team.id&&!$('joinSheet').classList.contains('hidden');
 openSheet('joinSheet');$('joinCodeBox').textContent='Loading the join link for '+team.name+'…';
 try{
  const {data,error}=await client.rpc('get_or_create_team_join_code',{p_team_id:team.id,p_expires_at:null});
  if(!current())return;if(error)throw error;
  const code=data?.[0]?.join_code||data?.join_code;if(!code)throw new Error('No join code was returned. Close this sheet and try again.');
  const url=teamJoinUrl(code);
  $('joinCodeBox').innerHTML=`<p><b>${esc(team.name)}</b></p><div class="joincode">${esc(code)}</div><div id="teamJoinQr" class="qr-wrap"></div><label for="teamJoinCopyValue">Team join link</label><textarea id="teamJoinCopyValue" readonly rows="3" autocapitalize="off" spellcheck="false"></textarea><p id="teamJoinCopyStatus" role="status" aria-live="polite"></p><div class="share-grid"><button type="button" data-team-share="text">Text</button><button type="button" data-team-share="email">Email</button><button type="button" data-team-share="copy">Copy Link</button><button type="button" data-team-share="share">Share</button></div><div class="info-banner">Athletes or parents scan the same QR, fill out the information, and wait for coach approval.</div><p class="invite-email-reminder">${esc(INVITE_EMAIL_REMINDER)}</p>`;
  $('teamJoinCopyValue').value=url;
  const bind=(action,fn)=>{$('joinCodeBox').querySelector(`[data-team-share="${action}"]`).onclick=()=>{if(current())return fn();$('joinCodeBox').textContent='Team changed. Reopen Team Join for the current team.';};};
  bind('text',()=>shareByText(`Join ${team.name} in Wrestling Manager: ${url}\n\n${INVITE_EMAIL_REMINDER}`));
  bind('email',()=>shareByEmail(`Join ${team.name}`,`Fill out your Wrestling Manager team registration here: ${url}\n\n${INVITE_EMAIL_REMINDER}`));
  bind('copy',async()=>{const btn=$('joinCodeBox').querySelector('[data-team-share="copy"]'),status=$('teamJoinCopyStatus');btn.disabled=true;try{const ok=await copyText(url,{field:$('teamJoinCopyValue'),status,isCurrent:current});if(current())btn.textContent=ok?'Copied':'Copy Link';}finally{btn.disabled=false;}});
  bind('share',()=>systemShare(`Join ${team.name}`,'Wrestling Manager team registration. '+INVITE_EMAIL_REMINDER,url));
  try{makeQr('teamJoinQr',url);}catch{$('teamJoinQr').textContent='Use the join link below.';}
 }catch(e){if(current())$('joinCodeBox').textContent=e.message||'Could not load the join link. Please try again.';}
}
