import {mountRemoteReportingHome} from './remote-weighins-screen.mjs';
import {createRemoteReportingClient} from './remote-weighins-client.mjs';

// Candidate app registration. Enabled only after production adapters are deployed.
export function installRemoteReportingApp({button,root,show,hide,getSession,unlocked,personal,publishableKey,enabled=false,fetch=globalThis.fetch,nativeCapture,beforeOpen=()=>{}}) {
 let active=null,epoch=0;
 const valid=owner=>owner===active?.owner&&unlocked()===true&&personal()===true;
 function close(){epoch++;const prior=active;active=null;prior?.client?.stop();prior?.screen?.close();if(prior?.timer)clearInterval(prior.timer);hide();}
 async function open(){
  beforeOpen();close();if(!enabled||!unlocked()||!personal())return;
  const ticket=epoch,current=await getSession();if(ticket!==epoch||!current?.user?.id)return;
  const owner=current.user.id;active={owner,screen:null,timer:null};show();
  const client=createRemoteReportingClient({initialSession:current,getSession,isCurrent:()=>valid(owner)&&ticket===epoch,publishableKey,fetch});active.client=client;
  const api={context:client.context,report:client.report,photo:client.photo,
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
