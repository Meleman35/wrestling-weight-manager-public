/* Text drafts for personal profiles. Sending remains an explicit server action. */
window.WMChatDrafts=(()=>{
 'use strict';
 const S=window.WMOfflineStore,input=document.getElementById('communicationMessageBody');
 const status=document.createElement('p');status.id='communicationDraftStatus';status.className='fine';status.setAttribute('role','status');status.setAttribute('aria-live','polite');input.closest('.message-composer').after(status);
 const copies=document.createElement('details');copies.id='communicationDraftCopies';copies.hidden=true;status.after(copies);
 let context=null,flight=Promise.resolve(),opening=0;
 const uid=()=>session?.user?.id||'';
 const eligible=t=>!!uid()&&!managedLogin&&!!activeTeam?.id&&!!t?.can_post&&!String(t.title||'').startsWith('🧪 TEST:');
 const belongs=c=>context===c&&uid()===c.uid&&!managedLogin&&activeTeam?.id===c.team&&String(activeCommunicationThread?.thread_id)===c.thread;
 function tell(c,text){if(context===c&&uid()===c.uid)status.textContent=text;}
 function size(){input.style.height='auto';input.style.height=Math.min(Math.max(input.scrollHeight,38),108)+'px';}
 function clearEditor(){input.value='';input.style.height='38px';status.textContent='';copies.replaceChildren();copies.hidden=true;}
 function save(text=input.value){
  const c=context;if(!c||uid()!==c.uid||managedLogin)return flight;
  const revision=crypto.randomUUID();c.latestRevision=revision;c.latestBody=text;tell(c,'Saving draft…');
  flight=flight.catch(()=>{}).then(async()=>{
   await S.update(c.uid,b=>{
    b.chatDrafts||={};b.chatDraftCopies||={};const old=b.chatDrafts[c.key];
    // Keep both versions if another window edited the same conversation.
    if(old&&old.revision!==c.savedRevision&&old.body!==text){(b.chatDraftCopies[c.key]||={})[old.revision]=old;}
    if(text)b.chatDrafts[c.key]={body:text,revision,updated_at:new Date().toISOString()};else delete b.chatDrafts[c.key];
   });
   c.savedRevision=revision;
   if(context===c&&c.latestRevision===revision){tell(c,text?'Draft saved on this device · not sent':'');await showCopies(c).catch(()=>{});}
  }).catch(e=>{tell(c,'Draft could not save. Keep this screen open and try typing again.');throw e;});
  flight.catch(()=>{});return flight;
 }
 async function showCopies(c){
  const b=await S.get(c.uid);if(!belongs(c))return;
  const rows=Object.values(b.chatDraftCopies?.[c.key]||{});copies.replaceChildren();copies.hidden=!rows.length;if(!rows.length)return;
  const summary=document.createElement('summary');summary.textContent=`Other saved drafts (${rows.length})`;copies.append(summary);
  for(const row of rows){
   const card=document.createElement('div'),text=document.createElement('textarea'),use=document.createElement('button'),discard=document.createElement('button');
   text.readOnly=true;text.value=row.body;text.setAttribute('aria-label','Other saved draft');use.type=discard.type='button';use.className=discard.className='secondary';use.textContent='Use this draft';discard.textContent='Discard this copy';
   use.onclick=()=>{
    if(!belongs(c))return;input.readOnly=true;
    flight=flight.then(async()=>{
     const revision=crypto.randomUUID();
     await S.update(c.uid,b=>{
      const chosen=b.chatDraftCopies?.[c.key]?.[row.revision];if(!chosen)throw Error('This draft copy changed. Reopen the saved drafts.');
      const old=b.chatDrafts?.[c.key];if(old&&old.body!==chosen.body)b.chatDraftCopies[c.key][old.revision]=old;
      b.chatDrafts||={};b.chatDrafts[c.key]={...chosen,revision,updated_at:new Date().toISOString()};delete b.chatDraftCopies[c.key][row.revision];
     });
     c.savedRevision=c.latestRevision=revision;c.latestBody=row.body;
     if(belongs(c)){input.value=row.body;size();tell(c,'Draft restored from this device · not sent');await showCopies(c).catch(()=>{});}
    }).catch(e=>{tell(c,'Could not switch drafts. Your saved copies are retained.');throw e;}).finally(()=>{if(context===c)input.readOnly=false;});
    flight.catch(()=>{});
   };
   discard.onclick=async()=>{if(!belongs(c))return;try{await S.update(c.uid,b=>{delete b.chatDraftCopies?.[c.key]?.[row.revision];});await showCopies(c).catch(()=>{});}catch{tell(c,'Could not remove this copy. Try again.');}};
   card.append(text,use,discard);copies.append(card);
  }
 }
 async function open(thread){
  const team=activeTeam?.id,id=String(thread.thread_id),user=uid(),nextKey=team+'/'+id;
  if(context?.uid===user&&context.key===nextKey&&eligible(thread))return true;
  const seq=++opening;input.readOnly=true;
  try{await flight;}catch{input.readOnly=false;message('Your message draft has not saved. Keep this conversation open and try typing again.',true);return false;}
  if(seq!==opening||uid()!==user||activeTeam?.id!==team)return false;
  context=null;clearEditor();
  if(!eligible(thread)){input.readOnly=false;return true;}
  const c={uid:user,team,thread:id,key:nextKey,savedRevision:null,latestRevision:null,latestBody:''};context=c;
  try{
   const b=await S.get(user);if(seq!==opening||context!==c||uid()!==user||managedLogin)return false;
   const row=b.chatDrafts?.[nextKey];if(row){input.value=row.body;c.savedRevision=c.latestRevision=row.revision;c.latestBody=row.body;size();tell(c,'Draft restored from this device · not sent');}
  }catch{tell(c,'Saved drafts could not load. Keep any new text here until it saves.');}
  finally{if(context===c)input.readOnly=false;}
  return context===c;
 }
 async function leave(){try{await flight;reset();return true;}catch{message('Your message draft has not saved. Return to Messages and try typing again.',true);return false;}}
 function reset(){++opening;context=null;clearEditor();input.readOnly=false;flight=flight.catch(()=>{});}
 function capture(){
  const c=context;if(!c||!belongs(c))return null;
  if(input.value!==c.latestBody)void save();
  return {context:c,uid:c.uid,key:c.key,revision:c.latestRevision,raw:input.value};
 }
 async function sent(token){
  if(!token)return false;await flight.catch(()=>{});
  try{await S.update(token.uid,b=>{if(b.chatDrafts?.[token.key]?.revision===token.revision)delete b.chatDrafts[token.key];delete b.chatDraftCopies?.[token.key]?.[token.revision];});}
  catch{if(belongs(token.context))tell(token.context,'Message sent, but the saved draft could not be cleared.');return false;}
  const c=token.context;
  if(belongs(c)&&c.latestRevision===token.revision&&input.value===token.raw){clearEditor();c.savedRevision=c.latestRevision=null;c.latestBody='';return true;}
  return false;
 }
 async function beforeSignOut(){try{await flight;return true;}catch{message('Your message draft has not saved. Return to Messages before signing out.',true);return false;}}
 input.addEventListener('input',()=>{void save();});
 // Input writes begin immediately; no debounce that could be lost on app suspension.
 document.addEventListener('visibilitychange',()=>{if(document.hidden&&context&&input.value!==context.latestBody)void save();});
 return {open,leave,reset,capture,sent,beforeSignOut,ready:()=>context&&showCopies(context).catch(()=>{}),flush:()=>flight};
})();
