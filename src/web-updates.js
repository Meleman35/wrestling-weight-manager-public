/* Public web-version status only. Never activates a worker or reloads user work. */
window.WMWebUpdates=(()=>{
 'use strict';
 const CURRENT='0.20.119',LIMIT=65536;
 const sheet=document.getElementById('accountSheet');
 if(!sheet)return Object.freeze({check:async()=>{}});
 const card=document.createElement('section');card.id='webUpdatesCard';card.className='feature-card';
 card.setAttribute('aria-labelledby','webUpdatesTitle');
 const title=document.createElement('h3');title.id='webUpdatesTitle';title.textContent='App updates';
 const version=document.createElement('p');version.className='fine';version.textContent='Current web version: '+CURRENT+'. Apple app updates are separate.';
 const status=document.createElement('p');status.id='webUpdatesStatus';status.className='fine';status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const button=document.createElement('button');button.id='webUpdatesCheck';button.className='wide secondary';button.type='button';button.textContent='Check for updates';
 card.append(title,version,status,button);sheet.append(card);
 let epoch=0,controller=null,busy=false;
 const visible=()=>!document.hidden&&!sheet.classList.contains('hidden')&&!sheet.hidden;
 const newer=v=>{const a=v.split('.').map(Number),b=CURRENT.split('.').map(Number);for(let i=0;i<3;i++){if(a[i]!==b[i])return a[i]>b[i];}return false;};
 const paint=(state,text)=>{card.dataset.updateState=state;status.textContent=text;};
 function cancel(){++epoch;controller?.abort();controller=null;busy=false;button.disabled=false;if(card.dataset.updateState==='checking')paint('idle','The check stopped. Open My Account and check again when ready.');}
 async function check(){
  if(busy||!visible())return;
  if(!navigator.onLine){paint('offline','Connect to the internet to check for updates. Your saved work stays on this device.');return;}
  const g=++epoch,c=new AbortController();controller=c;busy=true;button.disabled=true;
  const valid=()=>epoch===g&&visible();let timeout=false;
  const timer=setTimeout(()=>{timeout=true;c.abort();},8000);
  paint('checking','Checking for a newer web version…');
  try{
   const url=new URL('./sw.js',location.href);
   if(url.origin!==location.origin)throw Error('origin');
   const response=await fetch(url.href,{cache:'no-store',credentials:'omit',redirect:'error',signal:c.signal});
   if(!response.ok||response.redirected)throw Error('response');
   const size=response.headers.get('content-length');if(size&&(!/^\d+$/.test(size)||Number(size)>LIMIT))throw Error('size');
   const text=await response.text();if(text.length>LIMIT)throw Error('size');
   const match=text.match(/^const CACHE='wm-shell-(\d{1,5}\.\d{1,5}\.\d{1,5})';$/m);
   if(!match||text.match(/^const CACHE=/gm)?.length!==1)throw Error('version');
   if(!valid())return;
   if(newer(match[1]))paint('available','Web update '+match[1]+' is available. Save unfinished work and finish any recording or sync first. Then close all Wrestling Manager app windows and browser tabs, and reopen. Keep app data and saved recordings.');
   else if(match[1]===CURRENT)paint('current','This screen matches the published web version. Apple app updates are checked separately in TestFlight or the App Store.');
   else paint('unconfirmed','The server returned an older web version. Check again later; keep your saved work.');
  }catch{
   if(valid())paint(navigator.onLine?'error':'offline',timeout?'The update check timed out. Try again when connected. Your saved work has not changed.':'The latest web version could not be confirmed. Check your connection and try again. Your saved work has not changed.');
  }finally{
   clearTimeout(timer);if(epoch===g){controller=null;busy=false;button.disabled=false;}
  }
 }
 button.onclick=()=>{void check();};
 new MutationObserver(()=>{if(visible())void check();else if(busy)cancel();}).observe(sheet,{attributes:true,attributeFilter:['class','hidden']});
 document.addEventListener('visibilitychange',()=>{if(document.hidden&&busy)cancel();});
 window.addEventListener('pagehide',cancel);
 paint('idle','Check when connected. Updating never requires clearing your app data.');
 return Object.freeze({check});
})();
