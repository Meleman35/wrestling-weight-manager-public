import {openSubscriptionScreen} from './subscription-controller.mjs';
import {createSubscriptionAPIClient} from './subscription-api-client.mjs';

// In-app host. Native activation checks live Auth and backend readiness before
// StoreKit becomes available. Status displays never authorize a protected action.
export function installSubscriptionApp({button,root,show,hide,beforeOpen,getSession,
  unlocked,personal,getTeam,publishableKey,native=()=>globalThis.webkit?.messageHandlers,
  fetchImpl=globalThis.fetch,openScreen=openSubscriptionScreen,createAPI=createSubscriptionAPIClient}) {
 let epoch=0,screen=null,api=null,watch=null,owner=null,team=null,generation=null;
 const allowed=()=>unlocked()===true&&personal()===true;
 const valid=ticket=>ticket===epoch&&allowed()&&getSession()?.user?.id===owner&&(getTeam()?.id??null)===team;
 function stopNative(){try{Promise.resolve(native()?.wmPurchaseActivation?.postMessage({command:'stop'})).catch(()=>{});}catch{}}
 function close(){epoch++;screen?.dispose();screen=null;api?.stop();api=null;if(watch)clearInterval(watch);watch=null;owner=null;team=null;generation=null;root.replaceChildren();hide();stopNative();}
 function text(value){const node=root.ownerDocument.createElement('p');node.setAttribute('role','status');node.textContent=value;root.append(node);return node;}
 function currentSession(){
  if(!owner||!generation||!allowed())return null;
  const session=getSession();if(session?.user?.id!==owner||typeof session.access_token!=='string')return null;
  // Decode for correlation only. Every backend operation verifies the token.
  try {const raw=session.access_token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');
   const claims=JSON.parse(atob(raw));if(claims.sub!==owner||typeof claims.session_id!=='string')return null;
   return {accountID:owner,sessionID:claims.session_id,accessToken:session.access_token,generation};
  }catch{return null;}
 }
 async function open(kind='team'){
  beforeOpen();close();if(!allowed())return;
  if(kind!=='team'){show();text('Family Video is planned for a later update and is not available for purchase.');return;}
  const ticket=epoch;owner=getSession()?.user?.id;team=getTeam()?.id??null;if(!owner)return;
  show();const loading=text('Checking purchase availability…');
  watch=setInterval(()=>{if(!valid(ticket))close();},500);
  try {
   const handlers=native();if(!handlers?.wmPurchaseActivation)throw Error('native_required');
   const result=await handlers.wmPurchaseActivation.postMessage({command:'activate'});
   if(!valid(ticket))return;
   if(result?.ready!==true||typeof result.generation!=='string')throw Error('unavailable');
   generation=result.generation;
   api=createAPI({currentSession,sessionGeneration:generation,publishableKey,fetchImpl});
   loading.remove();
   if(!team){text('Choose a team in the app before opening Team Pro.');return;}
   const accessStatus=text('');
   const refreshAccess=async()=>{
    if(!valid(ticket))throw Error('session_ended');
    if(!team){accessStatus.textContent='Purchase delivery checked. Choose a team to view its current access.';return;}
    const result=await api.readAccess({teamID:team},{isCurrent:()=>valid(ticket)});
    if(valid(ticket))accessStatus.textContent=result.teamPro?'Team Pro is active for this team.':'Team Pro is not active for this team.';
   };
   const mounted=await openScreen({container:root,kind:'team',teamID:team,
    handler:native().wmPurchases,currentSession:()=>valid(ticket)?generation:null,sessionGeneration:generation,
    purchaseReady:true,refreshAccess});
   if(!valid(ticket)){mounted.dispose();return;}screen=mounted;
   await mounted.recover();
   if(valid(ticket))await refreshAccess();
  }catch(error){
   if(!valid(ticket))return;
   screen?.dispose();screen=null;api?.stop();api=null;stopNative();root.replaceChildren();
   text(error.message==='native_required'?'Open the installed Wrestling Manager app to manage purchases.':'Purchases could not be confirmed. Reconnect and reopen plans to recover pending purchases.');
  }
 }
 button.hidden=false;button.onclick=()=>open();
 const visibility=()=>{if(document.visibilityState==='hidden')close();};document.addEventListener('visibilitychange',visibility);
 return Object.freeze({open,close,dispose(){close();button.onclick=null;button.hidden=true;document.removeEventListener('visibilitychange',visibility);}});
}
