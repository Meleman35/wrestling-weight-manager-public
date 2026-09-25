/* Server-confirmed team status only. This screen never activates a subscription. */
window.WMTeamPlan=(()=>{
 const el=id=>document.getElementById(id);
 let generation=0,identity='',busy=false;
 const account=()=>[session?.user?.id,activeTeam?.id].join(':');
 const allowed=()=>!!session?.user?.id&&!!activeTeam?.id&&!managedLogin&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)');
 const visible=()=>!el('teamPlanSheet').classList.contains('hidden');
 function reset(){generation++;identity='';busy=false;el('teamPlanBody').replaceChildren();el('teamPlanStatus').textContent='';el('teamPlanRefresh').disabled=false;}
 function sync(){
  show('teamPlanBtn',allowed());
  if(visible()&&(!allowed()||identity&&identity!==account())){reset();show('teamPlanSheet',false);recoverInteractionLayer();}
 }
 const date=value=>{const d=new Date(value);return Number.isFinite(d.getTime())?d.toLocaleDateString(undefined,{year:'numeric',month:'long',day:'numeric'}):'';};
 function render(data){
  const pilot=data.access_source==='pilot',paid=data.access_source==='subscription';
  const heading=paid?'Full Year':pilot?'TestFlight pilot':'Free';
  let detail=paid?'This team has Full Year access.':pilot?'Paid tools are included during the free pilot. No purchase is needed.':'This team does not have an active Full Year subscription.';
  if(paid&&data.paid_through)detail+=(data.subscription_status==='canceled'?' Access ends on ':' Current access runs through ')+date(data.paid_through)+'.';
  if(data.subscription_status==='expired'&&!pilot)detail='Full Year has expired. Your free features and authorized access to saved records remain available.';
  el('teamPlanBody').innerHTML=`<section class="team-plan-card"><p class="team-plan-label">${esc(data.team_name)}</p><h3>${heading}</h3><p>${esc(detail)}</p></section>
   <section class="team-plan-rules"><h3>One team, one subscription</h3><p>Full Year covers the team’s authorized coaches, parents and athletes. Family members do not need separate subscriptions.</p><p>Changing the head coach, team name or season keeps the subscription with this team. Creating another team requires its own plan.</p></section>
   <div class="team-plan-columns"><section class="team-plan-card"><h3>Always included</h3><ul><li>Accounts and family connections</li><li>Core team communication and schedules</li><li>Parent controls and athlete privacy</li><li>Authorized access to saved records</li></ul></section>
   <section class="team-plan-card"><h3>Full Year at launch</h3><p>Annual access for one team. We’re preparing team management, inventory and reporting tools for the paid release.</p><p>Final pricing and the complete feature list will be shown before purchase.</p></section></div>
   <p class="team-plan-note">Purchases are not open yet. ${data.can_manage_plan?'Your team administrator will manage the team subscription.':'Your coach or team administrator will handle the team subscription.'}</p>
   <p class="fine">USA Bracketing integration and tournament phone alerts are still being prepared. They are not active services in this release.</p>`;
 }
 async function refresh(){
  if(!allowed()||!visible()||busy)return;
  const ticket=++generation,teamId=activeTeam.id;identity=account();busy=true;
  el('teamPlanBody').replaceChildren();el('teamPlanRefresh').disabled=true;el('teamPlanStatus').textContent='Checking this team’s plan…';
  const current=()=>ticket===generation&&identity===account()&&allowed()&&visible();
  try{
   const {data,error}=await client.rpc('team_plan_request',{p_team_id:teamId});
   if(!current())return;
   if(error||!data||data.team_id!==teamId||!['free','pilot','subscription'].includes(data.access_source))throw Error('Plan status is unavailable. Please refresh in a moment.');
   render(data);el('teamPlanStatus').textContent='';
  }catch(e){if(current())el('teamPlanStatus').textContent='Plan status is unavailable. Please refresh in a moment.';}
  finally{if(current()){busy=false;el('teamPlanRefresh').disabled=false;}}
 }
 function open(){if(!allowed())return;closeSheets();openSheet('teamPlanSheet');identity=account();refresh();}
 function inventoryCsv(rows){
  const cell=value=>{let s=String(value??'');if(/^[\s]*[=+@-]/.test(s)||/^[\t\r\n]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
  return [['Item','Total','Issued','Available','Notes'],...rows.map(r=>[r.title,r.quantity,r.checked_out,r.quantity-r.checked_out,r.notes])].map(r=>r.map(cell).join(',')).join('\r\n');
 }
 el('teamPlanBtn').onclick=open;el('teamPlanRefresh').onclick=refresh;
 document.addEventListener('visibilitychange',()=>{sync();if(!document.hidden&&visible())refresh();});
 window.addEventListener('focus',()=>{sync();if(visible())refresh();});
 // Lock/account changes clear the visible projection even without a navigation event.
 setInterval(()=>{sync();},1000);
 setInterval(()=>{if(!document.hidden&&visible())refresh();},60000);
 sync();return {open,reset,sync,inventoryCsv};
})();
