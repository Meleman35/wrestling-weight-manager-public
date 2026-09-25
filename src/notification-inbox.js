/* One unread inbox across teams; server read state drives every device badge. */
window.WMNotificationSync = (() => {
  let rows=[],owner='',loading=null,generation=0,badge=null,remoteCount=null,lastRemote=0,remoteBusy=false,retryTimer=null,filterTeam=null;
  const $n=id=>document.getElementById(id);
  const current=()=>session?.user?.id||'';
  const available=()=>!!current()&&managedMessagesEnabled();
  function reset(){generation++;rows=[];owner=current();badge=null;remoteCount=null;lastRemote=0;loading=null;remoteBusy=false;filterTeam=null;clearTimeout(retryTimer);render();}
  async function pushBadge(count,userId){
    if(!available()||current()!==userId||remoteBusy)return;
    if(remoteCount===count&&Date.now()-lastRemote<300000)return;
    remoteBusy=true;
    try{
      const result=await client.functions.invoke('sync-notification-badges',{body:{}});
      if(current()!==userId)return;
      if(!result.error&&result.data?.ok){remoteCount=Number(result.data.count);lastRemote=Date.now();}
      else {clearTimeout(retryTimer);retryTimer=setTimeout(()=>refresh(),30000);}
    }catch{if(current()===userId){clearTimeout(retryTimer);retryTimer=setTimeout(()=>refresh(),30000);}}
    finally{if(current()===userId){remoteBusy=false;if(remoteCount!==null&&remoteCount!==badge)clearTimeout(retryTimer),retryTimer=setTimeout(()=>refresh(),500);}}
  }
  function applyBadge(count){
    badge=Math.max(0,Math.trunc(Number(count)||0));
    postNativeNotification('setBadge',{count:badge});
    try{const result=badge?navigator.setAppBadge?.(badge):navigator.clearAppBadge?.();result?.catch?.(()=>{});}catch{}
  }
  async function refresh(){
    if(owner!==current())reset();
    if(!available()){applyBadge(0);rows=[];render();return;}
    if(loading)return loading;
    const userId=current(),ticket=++generation;
    const task=(async()=>{
      const unread=[];let cursor=null;
      do{
        let q=client.from('communication_notifications').select('*').eq('user_id',userId).is('read_at',null).order('id',{ascending:true}).limit(200);
        if(cursor)q=q.gt('id',cursor);
        const {data,error}=await q;
        if(current()!==userId||ticket!==generation)return;
        if(error)throw new Error('Notifications could not refresh. Try again when connected.');
        const page=data||[];unread.push(...page);if(page.length<200)break;cursor=page.at(-1).id;
      }while(cursor);
      const {data:count,error}=await client.rpc('get_notification_badge_count');
      if(current()!==userId||ticket!==generation)return;
      if(error)throw new Error('The unread count could not refresh.');
      rows=unread.sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at)));owner=userId;
      applyBadge(count);render();pushBadge(badge,userId);
    })().catch(error=>{if(current()===userId&&ticket===generation&&!$n('communicationNotificationsSheet').classList.contains('hidden'))$n('notificationSyncStatus').textContent=error.message;});
    loading=task;try{await task;}finally{if(loading===task)loading=null;}
  }
  function render(){
    if(!$n('notificationSyncStatus'))return;
    const list=$n('communicationNotificationList');
    if(owner!==current()){reset();return;}
    const all=rows.filter(r=>!r.read_at),visible=all.filter(r=>!filterTeam||r.team_id===filterTeam);
    const count=available()?(badge??all.length):0,display=n=>n>99?'99+':String(n);
    const counts=new Map();for(const r of all)counts.set(r.team_id,(counts.get(r.team_id)||0)+1);
    const outside=all.filter(r=>r.team_id!==activeTeam?.id).length;
    const header=$n('teamUnreadBadge');header.textContent=display(count);header.classList.toggle('hidden',!count);
    header.setAttribute('aria-label',`${count} unread updates across your teams`);
    $n('teamSwitcherBtn').setAttribute('aria-label',`Switch team${count?`, ${count} unread updates across your teams`:''}`);
    for(const b of document.querySelectorAll('[data-team-notifications]')){
      const n=available()?(counts.get(b.dataset.teamNotifications)||0):0;
      b.textContent=display(n);b.classList.toggle('hidden',!n);
      const team=availableTeams.find(t=>t.id===b.dataset.teamNotifications);
      b.setAttribute('aria-label',`${n} unread updates for ${team?.name||'this team'}`);
      b.onclick=()=>openInbox(b.dataset.teamNotifications);
    }
    $n('teamNotificationHint').textContent=count?`${count} unread update${count===1?'':'s'} across your teams. Tap a red badge to see that team’s updates.`:'Your role and permissions can be different on each team.';
    const other=$n('otherTeamNotificationsBtn');other.classList.toggle('hidden',!outside||!available());other.textContent=`${outside} unread update${outside===1?'':'s'} in other teams · View`;
    $n('allTeamNotificationsBtn').textContent=`All notifications${count?' · '+display(count):''}`;
    $n('communicationUnreadCount').textContent=display(count);
    $n('openNotificationsBtn').setAttribute('aria-label',`All notifications, ${count} unread across your teams`);
    $n('markCommunicationNotificationsReadBtn').disabled=!visible.length;
    $n('markCommunicationNotificationsReadBtn').textContent=filterTeam?'Mark this team read':'Mark All Read';
    const selected=availableTeams.find(t=>t.id===filterTeam);
    $n('notificationSyncStatus').textContent=filterTeam?`Unread updates for ${selected?.name||'this team'}. Other teams stay unread.`:'Unread updates from all your teams. Reading here updates your other devices.';
    $n('notificationShowAllBtn').classList.toggle('hidden',!filterTeam);
    list.replaceChildren();
    if(!visible.length){const empty=document.createElement('div');empty.className='empty-card';empty.textContent=filterTeam?'No unread notifications for this team.':'You’re all caught up. No unread notifications across your teams.';list.append(empty);return;}
    for(const row of visible){
      const b=document.createElement('button');b.className='notification-card unread';b.type='button';b.dataset.notificationId=row.id;
      const team=(availableTeams||[]).find(t=>t.id===row.team_id);
      const meta=document.createElement('small');meta.textContent=`${team?.name||'Team update'} · ${String(row.category||'update').replaceAll('_',' ')} · ${fmtDateTime(row.created_at)}`;
      const title=document.createElement('b');title.textContent=row.title||'Team update';const body=document.createElement('p');body.textContent=row.body||'';b.append(title,body,meta);
      b.onclick=async event=>{event.stopPropagation();try{await open(row);}catch(error){message(error.message||'Could not open this update. Please try again.',true);}};list.append(b);
    }
  }
  async function mark(items){
    const userId=current(),ids=[...new Set(items.filter(x=>!x.read_at).map(x=>x.id))];if(!userId||!ids.length)return true;
    const {error}=await client.rpc('mark_communication_notifications_read',{p_notification_ids:ids});
    if(current()!==userId)return false;
    if(error){message('Could not mark these notifications read. Please try again.',true);return false;}
    // Invalidate any older request before it can restore a badge that was read.
    generation++;loading=null;rows=rows.filter(x=>!ids.includes(x.id));applyBadge(rows.length);render();
    await refresh();loadCommunications(false);return true;
  }
  async function open(row){
    const userId=current();
    if(!available()||!userId)return;
    if(row.team_id&&!availableTeams.some(t=>t.id===row.team_id))await refreshCurrentTeamConnections();
    if(current()!==userId)return;
    if(row.team_id&&activeTeam?.id!==row.team_id){
      if(!availableTeams.some(t=>t.id===row.team_id)){message('This team is no longer available. You can mark the notification read from the inbox.');return;}
      await activateTeam(row.team_id);
    }
    if(current()!==userId||row.team_id&&activeTeam?.id!==row.team_id)return;
    if(window.WMJoinSync?.isNotification(row)){await WMJoinSync.openNotification(row);return;}
    if(row.category==='weigh_in'){await openWeighInNotification({...row,notification_id:row.id});return;}
    if(row.category==='sms_reply'){if(await openTextReplies())await mark([row]);return;}
    if(row.category==='safety'&&isStaff){if(await openCommunicationSafetyReview())await mark([row]);return;}
    if(row.thread_id){closeSheets();setTab('messages');await openCommunicationThread(row.thread_id);return;}
    if(await mark([row]))message('Notification marked read.');
  }
  async function openInbox(teamId=null){const userId=current();if(!userId)return;filterTeam=typeof teamId==='string'?teamId:null;closeSheets();openSheet('communicationNotificationsSheet');render();await refresh();if(current()!==userId)return;render();}
  function foreground(){if(!document.hidden)refresh();}
  document.addEventListener('visibilitychange',foreground);window.addEventListener('focus',foreground);window.addEventListener('online',foreground);
  setInterval(()=>{if(!document.hidden&&available())refresh();else if(owner!==current())reset();},15000);
  $n('refreshAllNotificationsBtn').onclick=()=>refresh();
  for(const id of ['allTeamNotificationsBtn','otherTeamNotificationsBtn','notificationShowAllBtn'])$n(id).onclick=()=>openInbox();
  return {refresh,render,reset,open:openInbox,markRecords:mark,markAll:()=>mark(rows.filter(r=>!filterTeam||r.team_id===filterTeam)),readChanged:()=>{generation++;loading=null;return refresh();}};
})();
