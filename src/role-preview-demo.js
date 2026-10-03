/* Representative role screens with fictional data only. Runs in an opaque sandbox.
   No app client, identities, native bridge, storage, provider, network or real routes. */
(() => {
 'use strict';
 const $=id=>document.getElementById(id),escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const roles={
  athlete:{label:'Athlete',name:'Avery Demo',initials:'AD',title:'Student athlete',home:'Locker Room',intro:'Your team, your goals and your family-approved profile.',access:['Your own profile and approved team content.','Goals, team schedule and permitted conversations.','Health submissions for ages 13–17 need guardian health-update permission; photos need a separate choice.'],limits:['No team management or other athletes’ private weight or care records.','A demo messaging choice does not authorize health sharing.']},
  coach:{label:'Coach',name:'Jordan Demo',initials:'JD',title:'Assistant Coach',home:'Locker Room',intro:'Your roster, coaching tools and team updates in one place.',access:['Coaching tools for your assigned team, within your permissions.','Authorized team weigh-in information and coach-shared participation instructions.','Practice Plans remain a paid team feature; production coverage is not activated by this preview.'],limits:['No private trainer/family care notes solely because you coach.','An assistant coach is not automatically a team administrator.']},
  trainer:{label:'Athletic Trainer',name:'Morgan Demo',initials:'MD',title:'Team Trainer',home:'Trainer Dashboard',intro:'Your assigned team and athlete-care workflow—not a coaching account.',access:['Accept the team’s trainer responsibility before opening care records.','Authorized athlete concerns, baselines, participation instructions and care updates.','Read-only schedule for the assigned team.'],limits:['No coaching, team administration or weight-history access solely through the trainer role.','No automatic access to every team at the school.','Sway completion is manually verified; the app does not diagnose or independently clear athletes.']},
  team_mom:{label:'Team Mom',name:'Casey Demo',initials:'CD',title:'Team Mom',home:'Locker Room',intro:'Help the team without becoming its coach or administrator.',access:['Normal team participation and separately assigned operational permissions.','Conversation review only with a separate eligible-adult assignment and acceptance.','Reviewer access is quiet and read-only for covered conversations.'],limits:['No blanket access to private chats, care notes, weights or parent controls.','Reviewer-only access cannot send, react, upload or delete.']},
  parent:{label:'Parent / Guardian',name:'Taylor Demo',initials:'TD',title:'Parent / Guardian',home:'Locker Room',intro:'Stay connected to your athlete and manage their permissions.',access:['Your connected athlete’s authorized profile, schedule and family updates.','Parent controls for your athlete; messaging and health permissions are separate.','Family Video coverage is athlete-specific; it does not unlock team coaching tools.'],limits:['No unrelated athletes’ private records.','Being a parent does not make you a coach, trainer or team administrator.']},
  admin:{label:'Team Administrator',name:'Riley Demo',initials:'RD',title:'Team Administrator',home:'Team Administration',intro:'People, team settings and authorized administration tools.',access:['Team membership, invitations and assigned role permissions.','Team settings and authorized administration workflows.','Additional coaching or family roles remain separate.'],limits:['No private clinical access solely because you are an administrator.','No Creator dashboard access through a team role.']}
 };
 const people=[{name:'Avery Demo',status:'Awaiting trainer',baseline:false,filter:'awaiting'},{name:'Rowan Demo',status:'Modified activity',baseline:true,filter:'restricted'},{name:'Kai Demo',status:'No concerns recorded',baseline:true,filter:'all'}];
 let role='coach',page='home',scenario={},messages=[],goalDone=false,profilePublic=false,filter='all';
 const card=(title,body)=>'<section class="card"><h2>'+escape(title)+'</h2>'+body+'</section>';
 const button=(label,action,secondary=true)=>'<button type="button" class="'+(secondary?'secondary ':'')+'wide" data-demo-action="'+action+'">'+escape(label)+'</button>';
 const p=s=>'<p>'+escape(s)+'</p>';
 const metric=(count,label,action)=>'<button type="button" class="metric" data-demo-action="'+action+'"><strong>'+count+'</strong><span>'+escape(label)+'</span></button>';
 function setRole(next){if(!roles[next])return;role=next;page='home';scenario={accepted:true,reviewer:false,messaging:false,age:'teen'};messages=[];goalDone=false;profilePublic=false;filter='all';render()}
 function settings(){
  if(role==='trainer')return '<label><span>Demo: trainer responsibility accepted</span><input id="demoAccepted" type="checkbox" '+(scenario.accepted?'checked':'')+'></label>';
  if(role==='team_mom')return '<label><span>Demo: separately assigned and accepted conversation reviewer</span><input id="demoReviewer" type="checkbox" '+(scenario.reviewer?'checked':'')+'></label>';
  if(role==='athlete')return '<label for="demoAge">Example age group</label><select id="demoAge"><option value="teen" '+(scenario.age==='teen'?'selected':'')+'>Ages 13–17</option><option value="child" '+(scenario.age==='child'?'selected':'')+'>Under 13</option></select><label><span>Demo: required family messaging permissions are in place</span><input id="demoMessaging" type="checkbox" '+(scenario.messaging?'checked':'')+(scenario.age==='child'?' disabled':'')+'></label>';
  return '<p class="fine">This example uses one typical role. Real screens depend on the person’s assignments, family permissions and feature availability.</p>';
 }
 function home(){
  let content='<section class="card hero"><div class="eyebrow">'+escape(roles[role].label)+' VIEW · FICTIONAL</div><h1>'+escape(roles[role].home)+'</h1><p>'+escape(roles[role].intro)+'</p></section>';
  if(role==='trainer'){
   if(!scenario.accepted)return content+card('Accept trainer access',p('The real app requires the assigned trainer to accept the responsibility before viewing athlete-care records.')+button('Try acceptance · demo only','accept')+'<p class="fine">No real responsibility is accepted here.</p>');
   content+='<p class="fine">3 fictional athletes · Counts are athletes, not diagnoses.</p><div class="grid">'+metric(1,'Awaiting review','health:awaiting')+metric(1,'Activity restrictions','health:restricted')+metric(1,'Reviews due','health:due')+metric(1,'Missing baselines','health:baseline')+'</div><p class="fine">No concerns recorded and baseline completion do not establish clearance.</p>'+button('Athletes & Baselines','health:all',false)+button('Care Updates','health:all')+button('Team Schedule · read only','schedule');
  }else if(role==='athlete'){
   content+=card('My goals','<label class="sample-task"><span>Practice my setup with purpose</span><input type="checkbox" id="demoGoal" '+(goalDone?'checked':'')+'></label><p class="fine">Try marking this fictional goal complete. Nothing is saved to the app.</p>')+card('Next practice',p('Thursday · 5:00–7:00 PM · Demo wrestling room')+button('View sample schedule','schedule'))+button('My profile','profile',false)+button('Team conversations','messages')+card('Health updates',p(scenario.age==='child'?'Younger athletes use the parent/trainer submission path.':'Health updates require a separate guardian permission. Messaging approval does not enable health photos.'));
  }else if(role==='team_mom'){
   content+=card('Team support',p('Team announcements and the practice schedule, with only separately assigned helper permissions.')+button('Team schedule','schedule'))+card('Conversation review',p(scenario.reviewer?'This example has a separate, accepted reviewer assignment. Covered conversations are read-only.':'Team Mom alone does not unlock conversation review. An eligible adult needs a separate assignment and must accept it.')+button(scenario.reviewer?'Open sample review inbox':'See the assignment example','messages'));
  }else if(role==='parent'){
   content+=card('My family','<div class="row"><div><b>Avery Demo</b><small>Connected athlete · fictional family</small></div><span class="pill">Family</span></div>'+button('View sample athlete profile','athlete-profile',false))+card('Stay involved',button('Schedule & RSVP example','schedule')+button('Family conversations','messages')+button('Permission examples','permissions'));
  }else if(role==='admin'){
   content+=card('Account & Team',button('People & Roles','people',false)+button('Team settings example','team-settings')+button('Team schedule','schedule'))+card('Role boundaries',p('Assigning a role and accepting responsibility are different steps. This preview never invites, assigns or changes a real person.'));
  }else{
   content+='<div class="grid">'+metric(3,'Sample athletes','roster')+metric(1,'Shared participation update','coach-health')+metric(1,'Next team practice','schedule')+metric('—','Paid Practice Plans','practice')+'</div>'+card('Clipboard',button('Sample roster','roster',false)+button('Practice Plans · feature status','practice')+button('Team conversations','messages'));
  }
  return content;
 }
 function profile(forceAthlete=false){
  const r=forceAthlete?roles.athlete:roles[role];
  return '<section class="card"><div class="profile-hero"><div class="profile-avatar" aria-hidden="true">'+r.initials+'</div><div><div class="eyebrow">FICTIONAL PROFILE</div><h1>'+r.name+'</h1><p>'+r.title+'</p></div></div><label class="sample-task"><span>Example of what others see</span><input id="demoPublic" type="checkbox" '+(profilePublic?'checked':'')+'></label><p class="fine">Illustrative fields only. Actual sharing depends on profile, age, family and team settings; this switch changes no setting.</p><div class="pair"><span>Team</span><b>Summit Demo Wrestling</b></div><div class="pair"><span>About</span><b>'+escape(r===roles.athlete?'Learning, working hard and supporting my teammates.':'Supporting the athletes and families in our demo team.')+'</b></div><div class="pair"><span>Role</span><b>'+r.title+'</b></div>'+(r===roles.athlete?'<div class="pair"><span>Example goal · when sharing is allowed</span><b>Build confidence on the mat</b></div>':'')+(!profilePublic?'<div class="notice">Account-facing example. Private settings and family links would depend on this person’s authorization.</div>':'<div class="notice">Shared-profile example. Private care notes, weight history, phone numbers and account controls are not shown here.</div>')+'</section>';
 }
 function schedule(){return '<h1>Team Schedule</h1><p class="fine">Fictional events, not your calendar. '+(role==='trainer'?'Trainer view is read-only.':'')+'</p>'+card('Thursday · Practice',p('5:00–7:00 PM · Demo wrestling room')+p('Focus: technique and partner work.'))+card('Saturday · Team event',p('9:00 AM · Demo gym')+(role==='parent'||role==='athlete'?button('Try RSVP · demo only','rsvp'):''));}
 function access(){return '<h1>'+escape(roles[role].label)+' · access</h1>'+card('Typical authorized tools',roles[role].access.map(x=>'<div class="access-item">'+escape(x)+'</div>').join(''))+card('Not automatically included',roles[role].limits.map(x=>'<div class="access-item">'+escape(x)+'</div>').join(''))+'<p class="fine">This walkthrough explains selected boundaries. It is not an exhaustive permission audit or a live-account test.</p>';}
 function health(){
  if(role!=='trainer'||!scenario.accepted)return card('Trainer responsibility required',p('Switch to an accepted fictional trainer to explore these sample screens.'));
  const selected=people.filter(a=>filter==='all'||filter==='baseline'&&!a.baseline||filter==='due'&&a.name==='Rowan Demo'||a.filter===filter);
  return '<h1>Athlete Health</h1><p class="fine">Fictional records only · '+escape({all:'All athletes',awaiting:'Awaiting review',restricted:'Activity restrictions',due:'Reviews due',baseline:'Missing baselines'}[filter])+'</p>'+selected.map(a=>card(a.name,'<span class="pill">'+a.status+'</span>'+p(a.baseline?'Sample baseline: provider completion recorded.':'Sample baseline: not verified for this school year.')+button('Open sample care record','care-record'))).join('');
 }
 function care(){if(role!=='trainer'||!scenario.accepted)return access();return '<h1>Sample care record</h1>'+card('Participation instructions · coach-shared',p('Modified activity · follow the trainer’s recorded instructions.')+'<span class="pill">Shared with coaches and family</span>')+card('Private care update',p('This fictional note illustrates the trainer/family area, separate from the coach-facing participation update.')+'<span class="pill warning">Not a coach-facing note</span>')+card('Provider-release workflow',p('Recording clearance uses the existing required provider/release process. This demo cannot clear an athlete, upload a release or verify a credential.'));}
 function chat(){
  const review=role==='team_mom';
  if(review&&!scenario.reviewer)return card('Reviewer access is separate',p('Team Mom is not automatically a reviewer. Use the demo scenario switch above to see an assigned-and-accepted reviewer example.'));
  if(role==='athlete'&&(scenario.age==='child'||!scenario.messaging))return card('Family permission required',p(scenario.age==='child'?'This walkthrough does not simulate direct minor messaging for an under-13 athlete. Use the parent/trainer path for health concerns.':'The example conversation stays closed until the required family permissions and adult participation controls are in place.'));
  return '<h1>'+ (review?'Conversation review':'Sample conversation')+'</h1><p class="fine">'+(review?'Covered coach/team-leader conversation · quiet, read-only review.':'Fictional team conversation. Required adult participation and family permissions still apply in the real app.')+'</p><div class="card"><span class="pill">Sample coach + guardian + athlete</span><div class="speech"><b>Coach Jordan Demo</b><p>Practice begins at 5 PM. Bring your practice gear.</p></div><div class="speech"><b>Taylor Demo · guardian</b><p>Thanks for the update!</p></div>'+messages.map(x=>'<div class="speech self"><b>Demo message · not sent</b><p>'+escape(x)+'</p></div>').join('')+(review?'<p class="notice">Read only. No reply, reaction, upload or delete permission from this reviewer assignment.</p>':'<label for="demoMessage">Try a fictional message</label><textarea id="demoMessage" maxlength="500" placeholder="Use fictional text only"></textarea>'+button('Simulate send · nothing leaves preview','send',false))+'</div>';
 }
 function extra(){
  if(page==='roster')return '<h1>Sample roster</h1>'+people.map(a=>card(a.name,button('View illustrative athlete profile','athlete-profile'))).join('');
  if(page==='coach-health')return '<h1>Coach-shared participation</h1>'+card('Rowan Demo',p('Modified activity · see trainer instructions.')+'<span class="pill">Participation update only</span>')+p('Private care notes and files are not included in this coach example.');
  if(page==='practice')return card('Practice Plans · paid team tool',p('A monthly coaching workspace for daily focus, timed activity blocks and copied plans. Verified paid access is required for real plans; billing is not connected in the current release.')+'<div class="row"><b>Warm-up · sample block</b><span>10 min</span></div><div class="row"><b>Technique · sample block</b><span>20 min</span></div><button type="button" class="secondary wide" disabled>Sample only · no real plan saving</button>');
  if(page==='permissions')return '<h1>Parent permission examples</h1>'+card('Separate choices',p('Profile sharing, team conversations, health updates and private health photos/documents have distinct controls. One does not automatically authorize the others.')+p('This view shows the distinction without changing consent for any athlete.'));
  if(page==='people')return '<h1>People & Roles · demo</h1>'+card('Example assignments',p('Coach Jordan Demo · Assistant Coach')+p('Morgan Demo · Team Trainer')+p('Casey Demo · Team Mom')+'<button type="button" class="secondary wide" disabled>No real invitations or role changes in preview</button>');
  return card('Team settings · demo',p('Team identity, roles and administrative tools depend on authorization. This example does not change any team.'));
 }
 function render(){
  const r=roles[role];$('demoRole').value=role;$('demoScenario').innerHTML=settings();$('demoAvatar').textContent=r.initials;$('demoPersona').textContent=r.name+' · '+r.label;
  document.querySelectorAll('[data-demo-page]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.demoPage===page)));
  $('demoScreen').innerHTML=page==='home'?home():page==='profile'?profile():page==='athlete-profile'?profile(true):page==='schedule'?schedule():page==='access'?access():page==='health'?health():page==='care-record'?care():page==='messages'?chat():extra();
  $('demoStatus').textContent='';
  if($('demoAccepted'))$('demoAccepted').onchange=e=>{scenario.accepted=e.target.checked;page='home';render()};
  if($('demoReviewer'))$('demoReviewer').onchange=e=>{scenario.reviewer=e.target.checked;render()};
  if($('demoAge'))$('demoAge').onchange=e=>{scenario.age=e.target.value;scenario.messaging=false;render()};
  if($('demoMessaging'))$('demoMessaging').onchange=e=>{scenario.messaging=e.target.checked;render()};
  if($('demoGoal'))$('demoGoal').onchange=e=>{goalDone=e.target.checked;$('demoStatus').textContent='Fictional goal '+(goalDone?'completed':'reopened')+' in this preview only.'};
  if($('demoPublic'))$('demoPublic').onchange=e=>{profilePublic=e.target.checked;render()};
 }
 function go(next){page=next;render();$('demoScreen').focus({preventScroll:true});$('demoScreen').scrollIntoView({block:'start'})}
 document.addEventListener('click',event=>{
  const b=event.target.closest('button');if(!b)return;
  if(b.dataset.demoPage){go(b.dataset.demoPage);return}
  const a=b.dataset.demoAction;if(!a)return;
  if(a==='send'){const text=$('demoMessage').value.trim();if(!text){$('demoStatus').textContent='Enter fictional text to try this action.';return}messages.push(text.slice(0,500));messages=messages.slice(-10);render();$('demoStatus').textContent='Demo message added here only. No message was sent.';return}
  if(a==='accept'){scenario.accepted=true;render();$('demoStatus').textContent='Demo acceptance only. No real trainer assignment changed.';return}
  if(a==='rsvp'){$('demoStatus').textContent='Sample RSVP recorded only in this preview. No calendar or attendance record changed.';return}
  if(a.startsWith('health:')){filter=a.split(':')[1];go('health');return}go(a);
 });
 $('demoRole').onchange=e=>setRole(e.target.value);
 $('demoReset').onclick=()=>{setRole(role);$('demoStatus').textContent='This role’s fictional example has been reset.'};
 window.addEventListener('message',e=>{if(e.source!==parent||e.data?.type!=='wm-role-preview-back')return;if(page==='home')parent.postMessage({type:'wm-role-preview-close'},'*');else go('home')});
 setRole(role);
})();
// The only message leaving the sandbox requests closing its own preview. No payload data.
document.addEventListener('keydown',e=>{if(e.key==='Escape')parent.postMessage({type:'wm-role-preview-close'},'*')});
