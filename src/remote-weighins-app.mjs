import {mountRemoteReportingHome} from './remote-weighins-screen.mjs';

// Candidate app registration. Enabled only after production adapters are deployed.
export function installRemoteReportingApp({button,root,show,hide,getSession,unlocked,personal,publishableKey,enabled=false,fetch=globalThis.fetch,nativeCapture,beforeOpen=()=>{}}) {
 let active=null,epoch=0;
 const endpoint='https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/remote-weighins';
 const valid=owner=>owner===active?.owner&&unlocked()===true&&personal()===true;
 function close(){epoch++;const prior=active;active=null;prior?.screen?.close();if(prior?.timer)clearInterval(prior.timer);hide();}
 async function open(){
  beforeOpen();close();if(!enabled||!unlocked()||!personal())return;
  const ticket=epoch,current=await getSession();if(ticket!==epoch||!current?.user?.id)return;
  const owner=current.user.id;active={owner,screen:null,timer:null};show();
  async function request(action,body,photo=false){
   if(!valid(owner)||ticket!==epoch)throw Error('Reporting session closed');
   const session=await getSession();if(!valid(owner)||ticket!==epoch||session?.user?.id!==owner||!session.access_token)throw Error('Reporting session closed');
   const response=await fetch(endpoint+'/'+action,{method:'POST',redirect:'error',cache:'no-store',credentials:'omit',headers:{Authorization:'Bearer '+session.access_token,apikey:publishableKey,'Content-Type':'application/json'},body:JSON.stringify(body)});
   const after=await getSession();if(!valid(owner)||ticket!==epoch||after?.user?.id!==owner)throw Error('Reporting session closed');
   if(!response.ok)throw Error('Reporting unavailable');
   return photo?response.blob():response.json();
  }
  const api={context:()=>request('context',{}),report:query=>request('report',query),photo:query=>request('photo-read',query),
   ...(nativeCapture?{captureWindow:context=>nativeCapture(context)}:{})};
  active.screen=mountRemoteReportingHome({root,api,isCurrent:()=>valid(owner)&&ticket===epoch});
  active.timer=setInterval(()=>{if(!valid(owner))close();},1000);
  await active.screen.ready;
 }
 button.hidden=!enabled;button.onclick=()=>open().catch(()=>close());
 const onVisibility=()=>{if(document.visibilityState==='hidden')close();};
 document.addEventListener('visibilitychange',onVisibility);
 return Object.freeze({open,close,dispose(){close();document.removeEventListener('visibilitychange',onVisibility);button.onclick=null;button.hidden=true;}});
}
