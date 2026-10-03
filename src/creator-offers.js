/* Linked Creator workspace v1: team navigation is never replaced for a linked login. */
/* Only the server decides Creator access. This console prepares offers;
   it cannot grant paid access or turn a draft into a store discount. */
(() => {
 const $c=id=>document.getElementById(id);
 const plans={team_pro_year:'Team Pro · annual',team_pro_month:'Team Pro · monthly',family_video_year:'Family Video · annual',family_video_month:'Family Video · monthly',college_pro_year:'College Pro · annual',college_pro_month:'College Pro · monthly'};
 const sheet=document.createElement('section');sheet.id='creatorOffersSheet';sheet.className='sheet hidden';sheet.setAttribute('role','dialog');sheet.setAttribute('aria-modal','true');sheet.setAttribute('aria-labelledby','creatorTitle');
 sheet.innerHTML='<div class="sheet-handle"></div><div class="sheet-head"><div><div class="eyebrow">APP CREATOR</div><h2 id="creatorTitle">Creator Dashboard</h2></div><button type="button" class="icon-close" id="creatorClose" aria-label="Close Creator">×</button></div><button id="creatorReturnToTeam" type="button" class="secondary hidden">‹ Return to Team</button><button id="creatorDashboardRolePreviewBtn" type="button" class="wide secondary hidden">Explore Role Views · Demo</button><div id="creatorOfferStatus" role="status"></div><div id="creatorOfferBody"></div>';
 document.body.append(sheet);
 const home=document.createElement('section');home.id='creatorHomePanel';home.className='hidden';home.setAttribute('aria-labelledby','creatorHomeTitle');
 home.innerHTML='<div class="brand-lockup compact"><div class="brand-mark">WM</div><div><div class="eyebrow">APP MANAGEMENT</div><h1 id="creatorHomeTitle">Creator</h1></div></div><div class="card"><p id="creatorHomeEmail" class="muted"></p><h2>Your app workspace</h2><p>Manage discounts and trial settings here. No team or organization is required.</p><button id="creatorHomeOffersBtn" type="button" class="wide">Offers &amp; Trial</button><p class="fine">Discounts and customer trials are awaiting billing setup.</p></div><div class="card creator-home-actions"><button id="creatorHomeSecurityBtn" type="button" class="wide secondary">Sign-In &amp; Security</button><button id="creatorHomeAccountBtn" type="button" class="wide secondary">My Account</button><button id="creatorHomeCheckBtn" type="button" class="wide secondary">Refresh Access</button><button id="creatorHomeSignOutBtn" type="button" class="wide secondary">Sign Out</button><p id="creatorHomeStatus" class="fine" role="status"></p></div>';
 $c('setupView').prepend(home);
 let returnAccount='',accessMode='',generation=0,owner='',data=null,busy=false,accessGeneration=0,checking=false,lastCheck=0,homeOwner='',homeGeneration=0;
 const identity=()=>session?.user?.id&&!managedLogin?session.user.id:'';
 const actor=()=>identity()&&!document.hidden&&!document.body.classList.contains('kiosk-locked')&&!document.querySelector('#appLockOverlay:not(.hidden)')?identity():'';
 const active=g=>g===generation&&owner&&owner===actor()&&!sheet.classList.contains('hidden')&&navigator.onLine;
 const status=(s,error=false)=>{$c('creatorOfferStatus').textContent=s;$c('creatorOfferStatus').classList.toggle('error',error)};
 function close(){generation++;owner='';data=null;busy=false;checking=false;$c('creatorOfferBody').replaceChildren();show('creatorReturnToTeam',false);show('creatorDashboardRolePreviewBtn',false);status('');show(sheet.id,false);recoverInteractionLayer()}
 function hideAccess(){accessGeneration++;accessMode='';show('creatorOffersBtn',false);show('creatorDashboardMoreBtn',false)}
 async function refreshAccess(){
  hideAccess();const g=accessGeneration,u=actor();lastActor=actor();if(!u||!navigator.onLine)return false;
  try{const {data:out,error}=await client.rpc('creator_offers_request',{p_action:'access',p_data:{client:'creator-linked-v1'}});
   if(g===accessGeneration&&u===actor()&&navigator.onLine&&!error&&out?.creator===true){accessMode=out.home_mode==='team'?'team':'dedicated';show('creatorOffersBtn',true);show('creatorDashboardMoreBtn',true);return true}
  }catch{/* Access stays hidden on a failed or stale check. */}return false;
 }
 function resetHome(){homeGeneration++;homeOwner='';$c('setupView').classList.remove('creator-home-mode');show(home.id,false);$c('creatorHomeEmail').textContent='';$c('creatorHomeStatus').textContent=''}
 async function showHome(){
  const g=++homeGeneration,u=identity();if(!u||!await refreshAccess()||g!==homeGeneration||u!==actor()||accessMode!=='dedicated')return false;
  // Creator authorization is independent of memberships and never makes a team.
  closeSheets();homeOwner=u;activeTeam=null;activeSeason=null;availableTeams=[];
  organizationMemberships=[];teamMemberships=[];currentTeamMemberships=[];familyAthletes=[];memberAthletes=[];personalWeightSnapshots=[];
  actualIsStaff=false;actualIsTeamAdmin=false;actualIsManager=false;actualCanAttendance=false;actualCanWeighIn=false;actualCanMassText=false;
  isStaff=false;isTeamAdmin=false;isManager=false;canAttendance=false;canWeighIn=false;canMassText=false;staffMembership=null;
  $c('creatorHomeEmail').textContent=session.user.email||'';$c('creatorHomeStatus').textContent='';
  $c('setupView').classList.add('creator-home-mode');show(home.id,true);show('authView',false);show('appView',false);show('setupView',true);window.scrollTo(0,0);return true;
 }
 async function call(action,body={},g=generation){
  if(!active(g))throw Error('Reconnect and reopen Creator.');
  const {data:out,error}=await client.rpc('creator_offers_request',{p_action:action,p_data:{...body,client:'creator-linked-v1'}});
  if(!active(g))throw Error('The account changed. Reopen Creator.');
  if(error){if(error.code==='42501'){close();hideAccess()}throw Error(error.message||'Unable to load Creator.')}return out;
 }
 async function load(g){data=await call('dashboard',{},g);if(!active(g))return;lastCheck=Date.now();render();status('')}
 function exit(){
  const account=owner===actor()&&returnAccount===actor()+'|'+(activeTeam?.id||'');
  closeSheets();if(account)openAccountSheet();
 }
 async function open(returnTo){
  const target=document.activeElement;
  if(returnTo==='accountSheet'||target?.closest('#accountSheet'))returnAccount=actor()+'|'+(activeTeam?.id||'');
  else if(returnTo!=='preserve'&&!target?.closest('#creatorRolePreviewSheet'))returnAccount='';
  closeSheets();if(!actor()||!navigator.onLine){message('Sign in with your personal account and reconnect.',true);return}
  owner=actor();lastActor=owner;const g=++generation;openSheet(sheet.id);sheet.querySelector('[data-sheet-back]').onclick=exit;status('Checking Creator access…');
  try{await load(g)}catch(e){if(active(g))status(e.message,true);else if(g===generation)message(e.message,true)}
 }
 async function save(button,operation){
  if(busy)return;const g=generation;busy=true;button.disabled=true;status('Saving…');
  try{await operation(g);if(active(g)){await load(g);status('Saved. Billing setup is still required.')}}
  catch(e){if(active(g))status(e.message,true)}finally{if(active(g)){busy=false;button.disabled=false}}
 }
 function render(){
  show('creatorReturnToTeam',data.home_mode==='team'||accessMode==='team');
  show('creatorDashboardRolePreviewBtn',!!window.WMCreatorRolePreview);
  $c('creatorOfferBody').innerHTML=`<p class="creator-note"><b>Prepare your launch offers.</b><br>Billing is not connected yet. These drafts cannot be redeemed or unlock paid features.</p>
   <section class="creator-card"><h3>7-day full-feature trial</h3><span class="creator-tag">Awaiting billing setup</span><p>Team Pro access for 7 days, with the plan’s normal limits and account permissions.</p><label class="creator-switch"><span>Offer this trial at launch</span><input id="creatorTrialWanted" type="checkbox" ${data.trial.requested?'checked':''}></label><p class="creator-fine">Apple trial eligibility and the price after the trial must be shown at checkout before the customer agrees. Saving this setting does not start a trial or charge anyone.</p><button id="creatorTrialSave" type="button" class="secondary">Save Trial Setting</button></section>
   <div class="creator-actions"><button id="creatorNewOffer" type="button">Prepare Discount Code</button><button id="creatorRefresh" type="button" class="secondary">Refresh</button></div>
   <h3 style="margin-top:22px">Discount drafts</h3><div>${data.offers.length?data.offers.map(o=>`<article class="creator-card"><span class="creator-tag">${o.status==='archived'?'Archived':'Draft · not redeemable'}</span><div class="creator-code"><b>${esc(o.code)}</b></div><p>${esc(plans[o.product])}<br>${o.discount_percent}% off for ${o.billing_periods} billing period${o.billing_periods===1?'':'s'}</p><p class="creator-fine">Up to ${o.redemption_limit} redemptions · expires ${esc(new Date(o.expires_at).toLocaleString())}</p>${o.status==='draft'?`<div class="creator-actions"><button type="button" class="secondary" data-creator-edit="${esc(o.id)}">Edit Draft</button><button type="button" class="secondary" data-creator-archive="${esc(o.id)}">Archive</button></div>`:''}</article>`).join(''):'<p class="creator-fine">No codes prepared yet.</p>'}</div>
   <details class="creator-card"><summary>What makes these offers ready?</summary><p class="creator-fine">Connect subscription purchases and verified access, configure the 1-week introductory offer in App Store Connect, then create Apple offer codes using the available price points and eligibility rules. Test purchase, restore, expiration and refunds before sharing codes.</p></details>
   <details class="creator-card"><summary>Recent changes</summary>${data.events.map(e=>`<p class="creator-fine">${esc({create:'Draft created',update:'Draft updated',archive:'Draft archived',trial:'Trial setting saved'}[e.action]||'Change')} · ${esc(new Date(e.created_at).toLocaleString())}${e.actor_label?' · '+esc(e.actor_label):''}</p>`).join('')||'<p class="creator-fine">No changes yet.</p>'}</details>`;
  $c('creatorTrialSave').onclick=e=>save(e.currentTarget,g=>call('trial',{requested:$c('creatorTrialWanted').checked,revision:data.trial.revision},g));
  $c('creatorNewOffer').onclick=()=>editor();$c('creatorRefresh').onclick=e=>save(e.currentTarget,async()=>{});
  sheet.querySelectorAll('[data-creator-edit]').forEach(b=>b.onclick=()=>editor(data.offers.find(o=>o.id===b.dataset.creatorEdit)));
  sheet.querySelectorAll('[data-creator-archive]').forEach(b=>b.onclick=()=>save(b,g=>{const o=data.offers.find(o=>o.id===b.dataset.creatorArchive);return call('archive',{id:o.id,revision:o.revision},g)}));
 }
 function editor(o){
  const id=o?.id||crypto.randomUUID(),initial=new Date(o?.expires_at||Date.now()+30*86400000);
  const local=new Date(initial.getTime()-initial.getTimezoneOffset()*60000).toISOString().slice(0,16);
  $c('creatorOfferBody').innerHTML=`<button id="creatorOfferBack" type="button" class="secondary">‹ Back</button><h3 style="margin-top:18px">${o?'Edit discount draft':'Prepare a discount code'}</h3><p class="creator-fine">Choose the offer you want. Apple’s available price points and code rules will be checked when billing is connected.</p>
   <form id="creatorOfferForm"><label for="creatorCode">Requested code</label><input id="creatorCode" value="${esc(o?.code||'')}" pattern="[A-Za-z0-9]{4,32}" minlength="4" maxlength="32" autocapitalize="characters" autocomplete="off" spellcheck="false" required placeholder="e.g. WRESTLING20">
   <label for="creatorProduct">Plan</label><select id="creatorProduct">${Object.entries(plans).map(([key,label])=>`<option value="${key}" ${o?.product===key?'selected':''}>${label}</option>`).join('')}</select>
   <div class="creator-fields"><div><label for="creatorDiscount">Desired discount (%)</label><input id="creatorDiscount" type="number" min="1" max="100" step="1" value="${o?.discount_percent||20}" required></div><div><label for="creatorPeriods">Billing periods</label><input id="creatorPeriods" type="number" min="1" max="12" step="1" value="${o?.billing_periods||1}" required></div></div>
   <label for="creatorLimit">Maximum redemptions</label><input id="creatorLimit" type="number" min="1" max="25000" step="1" value="${o?.redemption_limit||100}" required>
   <label for="creatorExpiry">Expiration (your local time)</label><input id="creatorExpiry" type="datetime-local" value="${local}" required>
   <p class="creator-note">Draft only. This code will not work at checkout yet.</p><button type="submit" id="creatorDraftSave" class="wide">Save Draft</button></form>`;
  $c('creatorOfferBack').onclick=()=>{render();status('')};
  $c('creatorOfferForm').onsubmit=e=>{e.preventDefault();const payload={id,code:$c('creatorCode').value,product:$c('creatorProduct').value,discount_percent:Number($c('creatorDiscount').value),billing_periods:Number($c('creatorPeriods').value),redemption_limit:Number($c('creatorLimit').value),expires_at:new Date($c('creatorExpiry').value).toISOString()};if(o)payload.revision=o.revision;
   save($c('creatorDraftSave'),g=>call(o?'update':'create',payload,g));};
 }
 $c('creatorOffersBtn').textContent='Creator Dashboard';
 const more=document.createElement('button');more.type='button';more.id='creatorDashboardMoreBtn';more.className='menu-row hidden';
 more.innerHTML='<span>⚙️</span><div><b>Creator Dashboard</b><small>Shared app management workspace</small></div><i>›</i>';
 $c('moreTab').querySelector('.toolbox-title').after(more);more.onclick=open;
 $c('creatorReturnToTeam').onclick=()=>closeSheets();
 $c('creatorDashboardRolePreviewBtn').onclick=()=>window.WMCreatorRolePreview?.open();
 $c('creatorOffersBtn').onclick=open;$c('creatorClose').onclick=exit;$c('creatorHomeOffersBtn').onclick=open;
 $c('creatorHomeSecurityBtn').onclick=()=>{if(actor()===homeOwner)openSecuritySheet()};
 $c('creatorHomeAccountBtn').onclick=()=>{if(actor()===homeOwner)openAccountSheet()};
 $c('creatorHomeSignOutBtn').onclick=signOutCurrentPhone;
 $c('creatorHomeCheckBtn').onclick=async e=>{const b=e.currentTarget;b.disabled=true;try{if(!navigator.onLine){$c('creatorHomeStatus').textContent='Reconnect to refresh Creator access.';return}await refresh()}finally{b.disabled=false}};
 let lastActor=actor();setInterval(()=>{const u=actor();if(u!==lastActor){lastActor=u;hideAccess();close();if(u&&navigator.onLine)void refreshAccess()}if(owner&&(owner!==u||!navigator.onLine))close();if(homeOwner&&homeOwner!==identity())resetHome()},300);
 setInterval(async()=>{if(!owner||busy||checking||Date.now()-lastCheck<15000)return;checking=true;const g=generation;try{const a=await call('access',{},g);if(!a?.creator){close();hideAccess()}else lastCheck=Date.now()}catch{if(active(g)){close();hideAccess()}}finally{checking=false}},1000);
 window.addEventListener('offline',()=>{close();hideAccess()});window.addEventListener('online',()=>void refreshAccess());document.addEventListener('visibilitychange',()=>{if(document.hidden){close();hideAccess()}else void refreshAccess()});
 window.WMCreatorOffers={open,close,refreshAccess,showHome,resetHome};
})();
