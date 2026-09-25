/* 0.20.41: message reactions, available only through the conversation's server permissions. */
window.WMReactions=(()=>{
  const choices=[['wrestling','🤼','Wrestling'],['strength','💪','Strong'],['fire','🔥','On fire'],['trophy','🏆','Champion'],['gold','🥇','Gold medal'],['clap','👏','Great work'],['heart','❤️','Love it'],['thumbsup','👍','Got it'],['laugh','😂','Funny'],['celebrate','🎉','Celebrate'],['question','❓','Question'],['emphasis','‼️','Important']];
  let owner='',team='',thread='',epoch=0,loading=null,busy=false,last=0,cache=new Map(),canReact=false,selected=null,returnFocus=null,press=null,suppressClickUntil=0;
  const $r=id=>document.getElementById(id),dialog=$r('messageReactionDialog');
  const allowed=()=>!!session?.user?.id&&!managedLogin&&!document.hidden&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)')&&!$r('communicationThreadSheet').classList.contains('hidden');
  const valid=t=>t===epoch&&allowed()&&owner===session?.user?.id&&team===activeTeam?.id&&thread===String(activeCommunicationThread?.thread_id||'');
  const row=id=>activeCommunicationMessages.find(m=>String(m.message_id)===String(id));
  function close(){selected=null;clearTimeout(press?.timer);press=null;if(dialog.open)dialog.close();}
  function reset(){epoch++;close();owner='';team='';thread='';cache=new Map();loading=null;busy=false;canReact=false;last=0;}
  function sync(){if(!allowed()||owner&&(!valid(epoch))){reset();return false;}const next=String(activeCommunicationThread?.thread_id||'');if(!next)return false;if(thread!==next){reset();owner=session.user.id;team=activeTeam?.id;thread=next;}return true;}
  function paint(){
    if(!valid(epoch))return;
    for(const node of $r('communicationMessageList').querySelectorAll('[data-message-id]')){
      const m=row(node.dataset.messageId);if(!m)continue;
      let bar=node.querySelector('.message-reactions');if(!bar){bar=document.createElement('div');bar.className='message-reactions';node.querySelector('.message-line')?.after(bar);}bar.replaceChildren();
      if(!m.deleted_at&&!m.is_simulated)for(const r of cache.get(String(m.message_id))||[]){
        const choice=choices.find(c=>c[0]===r.key);if(!choice)continue;
        const b=document.createElement('button');b.type='button';b.className='reaction-chip'+(r.mine?' selected':'');b.textContent=choice[1]+' '+r.count;b.setAttribute('aria-pressed',String(!!r.mine));b.setAttribute('aria-label',`${choice[2]}, ${r.count} reaction${r.count===1?'':'s'}${r.mine?', including you':''}`);b.title=(r.people||[]).join(', ');b.disabled=!canReact||busy;b.onclick=()=>chooseMessage(m.message_id,b);bar.append(b);
      }
      let action=node.querySelector('[data-react-message]');
      if(!action&&!m.deleted_at&&!m.is_simulated){const actions=node.querySelector('.message-actions');if(actions){action=document.createElement('button');action.type='button';action.dataset.reactMessage=m.message_id;action.textContent='React';action.onclick=()=>chooseMessage(m.message_id,action);actions.prepend(action);}}
      if(action){action.hidden=!canReact;action.disabled=busy;}
    }
  }
  async function refresh(force=false){
    if(!sync())return;if(loading)return loading;if(!force&&Date.now()-last<5000){paint();return;}
    const ticket=epoch,ids=activeCommunicationMessages.filter(m=>!m.deleted_at&&!m.is_simulated).map(m=>m.message_id).slice(-100);if(!ids.length){paint();return;}
    const task=(async()=>{try{const {data,error}=await client.rpc('message_reactions_request',{p_action:'list',p_data:{thread_id:thread,message_ids:ids}});if(!valid(ticket))return;if(error)throw error;cache=new Map((data?.messages||[]).map(m=>[String(m.message_id),m.reactions||[]]));canReact=!!data?.can_react;last=Date.now();paint();}catch(e){if(valid(ticket)){canReact=false;cache=new Map();paint();if(dialog.open)$r('reactionStatus').textContent='Reactions could not refresh. Close and reopen the conversation to retry.';}}})();loading=task;try{await task;}finally{if(loading===task)loading=null;}
  }
  function chooseMessage(id,source){
    if(!sync()||busy||!canReact)return;const m=row(id);if(!m||m.deleted_at||m.is_simulated)return;
    selected=String(id);returnFocus=source;const mine=(cache.get(selected)||[]).find(r=>r.mine)?.key;
    $r('reactionStatus').textContent='Choose a reaction. Tap your selected reaction again to remove it.';
    $r('reactionChoices').replaceChildren();
    for(const [key,emoji,label] of choices){const b=document.createElement('button');b.type='button';b.className='reaction-choice'+(key===mine?' selected':'');b.textContent=emoji;b.setAttribute('aria-label',label);b.setAttribute('aria-pressed',String(key===mine));b.title=label;b.dataset.reactionKey=key;b.onclick=()=>save(key===mine?null:key);$r('reactionChoices').append(b);}
    $r('removeMessageReaction').hidden=!mine;if(!dialog.open)dialog.showModal();
  }
  async function save(key){
    if(!sync()||busy||!selected||!canReact)return;const id=selected,ticket=epoch,targetThread=thread;busy=true;dialog.querySelectorAll('button:not([data-reaction-close])').forEach(b=>b.disabled=true);$r('reactionStatus').textContent='Saving reaction…';paint();
    try{const {data,error}=await client.rpc('message_reactions_request',{p_action:'set',p_data:{thread_id:targetThread,message_id:id,reaction:key}});if(!valid(ticket))return;if(error)throw error;epoch++;loading=null;for(const m of data?.messages||[])cache.set(String(m.message_id),m.reactions||[]);canReact=!!data?.can_react;last=0;close();}
    catch(e){if(valid(ticket)){$r('reactionStatus').textContent='Reaction not confirmed. '+(e.message||'Check your connection and try again.');last=0;}}
    finally{if(owner===session?.user?.id&&thread===targetThread){busy=false;dialog.querySelectorAll('button').forEach(b=>b.disabled=false);paint();if(!dialog.open)returnFocus?.isConnected&&returnFocus.focus();}}
  }
  const list=$r('communicationMessageList');
  list.addEventListener('pointerdown',e=>{if(e.button!==0||e.target.closest('button,a,input,video'))return;const message=e.target.closest('[data-message-id]');if(!message||!canReact)return;clearTimeout(press?.timer);press={x:e.clientX,y:e.clientY,id:message.dataset.messageId};press.timer=setTimeout(()=>{if(!press)return;suppressClickUntil=Date.now()+700;chooseMessage(press.id,null);press=null;},500);});
  const cancelPress=()=>{clearTimeout(press?.timer);press=null;};
  list.addEventListener('pointermove',e=>{if(press&&Math.hypot(e.clientX-press.x,e.clientY-press.y)>10)cancelPress();});
  for(const ev of ['pointerup','pointercancel','scroll'])list.addEventListener(ev,cancelPress,{passive:true});
  list.addEventListener('click',e=>{if(Date.now()<suppressClickUntil){suppressClickUntil=0;e.preventDefault();e.stopImmediatePropagation();}},true);
  list.addEventListener('contextmenu',e=>{const m=e.target.closest('[data-message-id]');if(m&&canReact&&!e.target.closest('a,video')){e.preventDefault();chooseMessage(m.dataset.messageId,null);}});
  dialog.addEventListener('click',e=>{if(e.target===dialog||e.target.closest('[data-reaction-close]'))close();});
  dialog.addEventListener('close',()=>{selected=null;suppressClickUntil=0;});
  $r('removeMessageReaction').onclick=()=>save(null);
  setInterval(()=>{if(sync())refresh();},5000);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)reset();else refresh(true);});
  return {mount(){if(sync()){paint();refresh();}},refresh,reset,close};
})();
