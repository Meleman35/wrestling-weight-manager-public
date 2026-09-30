process.on('uncaughtException',e=>{console.error(e.message,e.where||'');process.exit(1)});
import {fixture} from './helpers/scoped-deletion-db.mjs';
import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomUUID as uuid,createHash} from 'node:crypto';
const {db}=await fixture(),checks=[];
async function runFile(path){const sql=await readFile(path,'utf8');try{await db.exec(sql);}catch(e){console.error(path,e.message,'position',e.position,sql.slice(Math.max(0,Number(e.position)-180),Number(e.position)+160));throw e;}}const pass=s=>{checks.push(s);console.log('PASS',s);};
await db.exec(`alter table auth.users add column raw_user_meta_data jsonb default '{}';create schema extensions;create function extensions.digest(text,text) returns bytea language sql immutable as $$select sha256(convert_to($1,'UTF8'))$$;create function storage.foldername(text) returns text[] language sql immutable as $$select string_to_array($1,'/')$$;grant usage on schema public,private,auth to authenticated,service_role;`);
await runFile('tests/fixtures/parent-messaging-functions.sql');
await runFile('supabase/migrations/20260930214004_parent_approved_team_messaging_020105.sql');
const ids=Object.fromEntries(['coach','reviewer','teen','parent','stranger','org','team','season','athlete','profile','social','guardian','invitation','emailRequest'].map(k=>[k,uuid()]));
for(const k of ['coach','reviewer','teen','parent','stranger']){await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[ids[k],k+'@example.test']);await db.query('insert into public.profiles(id,display_name) values($1,$2)',[ids[k],'Example '+k]);}
await db.query("insert into public.organizations(id,name) values($1,'Example organization')",[ids.org]);await db.query("insert into public.teams(id,organization_id,name) values($1,$2,'Example team')",[ids.team,ids.org]);await db.query("insert into public.seasons(id,team_id,name) values($1,$2,'Current')",[ids.season,ids.team]);
await db.query('insert into public.athlete_profiles(id) values($1)',[ids.profile]);await db.query("insert into public.athletes(id,profile_id,organization_id,first_name,last_name,birth_date) values($1,$2,$3,'Sample','Athlete',current_date-interval '15 years')",[ids.athlete,ids.profile,ids.org]);await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$2)',[ids.season,ids.athlete]);await db.query("insert into private.wrestling_profiles(id,athlete_profile_id,name) values($1,$2,'Sample Athlete')",[ids.social,ids.profile]);
await db.query("insert into public.team_memberships(team_id,user_id,role,athlete_id,permissions) values($1,$2,'head_coach',null,'{}'),($1,$3,'athlete',$4,'{}'),($1,$5,'manager',null,'{\"staff_role\":\"team_mom\"}')",[ids.team,ids.coach,ids.teen,ids.athlete,ids.reviewer]);
await db.query("insert into public.athlete_guardians(id,athlete_id,name,email,invitation_status) values($1,$2,'Example Parent','parent@example.test','pending')",[ids.guardian,ids.athlete]);
await db.query("insert into public.guardian_invitations(id,athlete_id,team_id,email,status,expires_at,token_hash,name,created_by) values($1,$2,$3,'parent@example.test','pending',now()+interval '14 days','test-invitation','Example Parent',$4)",[ids.invitation,ids.athlete,ids.team,ids.coach]);
await db.query('insert into private.invitation_email_attempts(invitation_id,request_id,requested_by) values($1,$2,$3)',[ids.invitation,ids.emailRequest,ids.coach]);
const admin=async()=>db.exec('reset role');const as=async(id,role='authenticated')=>{await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id||undefined,role})]);await db.exec('set role '+role);};
const rpc=async(name,args)=> (await db.query(`select public.${name}($1,$2) r`,args)).rows[0].r;
const review=async(action,data={})=>rpc('conversation_review_request',[action,{team_id:ids.team,...data}]);
const svc=async(action,data={})=>{await as(null,'service_role');return rpc('parent_browser_service',[action,data]);};
const token=()=>createHash('sha256').update(uuid()).digest('hex');
const issue=async()=>{const hash=token();await svc('issue',{invitation_id:ids.invitation,request_id:ids.emailRequest,token_hash:hash});return hash;};
const preview=hash=>svc('messaging_preview',{token_hash:hash});
const approve=async(hash,allow_media=false)=>{const p=await preview(hash),r=p.reviewers.find(x=>x.id===ids.reviewer);return svc('messaging_approve',{token_hash:hash,acknowledge:true,notice_version:'teen-messaging-v1',reviewer_id:r?.id,reviewer_version:r?.version,allow_media});};
await admin();await db.exec('insert into private.parent_browser_settings(id,enabled) values(true,true);insert into private.conversation_review_settings(id,enabled) values(true,true);');
await as(ids.coach);await db.query('select public.parent_browser_verify($1,$2,true)',[ids.guardian,ids.team]);await review('assign',{user_id:ids.reviewer,confirm_adult:true});
let hash=await issue(),p=await preview(hash);assert.equal(p.eligible,true);assert.deepEqual(p.reviewers,[]);
await as(ids.reviewer);await review('accept',{acknowledge:true});p=await preview(hash);assert.equal(p.reviewers.length,1);assert.equal(p.reviewers[0].name,'Example reviewer');
await as(ids.teen);await assert.rejects(()=>rpc('parent_browser_service',['messaging_approve',{token_hash:hash}]),/permission denied|Service/);await assert.rejects(()=>db.query('select private.parent_messaging_state($1,$2)',[ids.team,ids.teen]),/permission denied/);pass('Verified parent email capability and accepted adult reviewer are required; athletes cannot grant consent');
await as(ids.coach);await assert.rejects(()=>db.query('select public.create_communication_thread($1,$2,$3,$4)',[ids.team,ids.season,'Coach conversation',[ids.teen]]),/Parent approval/);
const approval=await approve(hash);assert.equal(approval.action,'messaging_approve');await admin();assert.equal((await db.query('select count(*) n from private.parent_browser_permissions')).rows[0].n,0);assert.equal((await db.query('select guardian_user_id from public.athlete_guardians where id=$1',[ids.guardian])).rows[0].guardian_user_id,null);
await as(ids.coach);const thread=(await db.query('select public.create_communication_thread($1,$2,$3,$4) id',[ids.team,ids.season,'Coach conversation',[ids.teen]])).rows[0].id;
let msg=(await db.query('select public.send_communication_message($1,$2) id',[thread,'Practice begins at five.'])).rows[0].id;
await admin();assert.equal((await db.query('select count(*) n from public.communication_message_receipts where message_id=$1 and user_id=$2',[msg,ids.reviewer])).rows[0].n,1);assert.equal((await db.query('select count(*) n from public.communication_notifications where user_id=$1',[ids.reviewer])).rows[0].n,0);
await as(ids.reviewer);assert.equal((await review('messages',{thread_id:thread}))[0].body,'Practice begins at five.');await assert.rejects(()=>db.query('select public.send_communication_message($1,$2)',[thread,'Cannot post as reviewer']),/cannot post/);
await as(ids.teen);let access=(await db.query('select public.get_communication_media_access($1) r',[thread])).rows[0].r;assert.equal(access.can_send,false);assert.equal(access.messaging_allowed,true);let observers=await review('observers',{thread_id:thread});assert.equal(observers.find(x=>x.name==='Example reviewer').parent_approved,true);await db.query('select public.send_communication_message($1,$2)',[thread,'Thank you, coach.']);pass('Consented team chat copies the named reviewer on every message, exposes their identity, stays quiet and does not grant profile or guardian powers');
await admin();await db.query("update public.team_memberships set permissions=permissions||'{\"team_admin\":true}'::jsonb where team_id=$1 and user_id=$2",[ids.team,ids.reviewer]);await as(ids.reviewer);await assert.rejects(()=>db.query('select public.create_communication_thread($1,$2,$3,$4)',[ids.team,ids.season,'Only one adult',[ids.teen]]),/reviewer|Messaging is paused/);pass('The approved reviewer cannot count as both adults in a conversation');
const blocked=async(fn,pattern=/Messaging is paused|Parent approval|connected parent|Reviewer|eligible|newest|newer|fresh|contact changed|permission denied|row-level security/i)=>{await db.exec('savepoint expected_rejection');await assert.rejects(fn,pattern);await db.exec('rollback to savepoint expected_rejection');};
const send=async()=>{await as(ids.coach);return db.query('select public.send_communication_message($1,$2)',[thread,'A routine schedule update.']);};
const ready=async()=>{await admin();return (await db.query('select private.parent_messaging_thread_ready($1) r',[thread])).rows[0].r;};
const scenario=async(name,fn)=>{await admin();await db.exec('begin');try{await fn();pass(name);}finally{await admin();await db.exec('rollback');}};
const manageLink=async()=>{await svc('recovery_context',{email:'parent@example.test'});const h=token();await svc('issue_management',{guardian_id:ids.guardian,token_hash:h});return h;};
const revoke=hash=>svc('messaging_revoke',{token_hash:hash,acknowledge:true,notice_version:'teen-messaging-v1'});
await scenario('Messaging-only parents can recover and withdraw; replay cannot revive consent and history is retained',async()=>{
 const before=(await db.query('select count(*) n from public.communication_messages')).rows[0].n;
 const manage=await manageLink();assert.equal((await preview(manage)).current.id,approval.id);assert.equal((await revoke(manage)).action,'messaging_revoke');assert.equal(await ready(),false);
 await as(ids.coach);await blocked(()=>db.query('select public.send_communication_message($1,$2)',[thread,'Blocked after withdrawal']));
 assert.equal((await approve(hash)).id,approval.id);assert.equal(await ready(),false);
 await admin();assert.equal((await db.query('select count(*) n from public.communication_messages')).rows[0].n,before);assert.equal((await db.query('select count(*) n from private.parent_browser_permissions')).rows[0].n,0);
 const fresh=await issue();await approve(fresh);assert.equal(await ready(),true);
});
await scenario('Profile approval and withdrawal are independent from messaging, even on the same email link',async()=>{
 await svc('approve',{token_hash:hash,acknowledge:true,notice_version:'teen-profile-v1',review_photos:true});assert.equal(await ready(),true);
 const manage=await manageLink();await svc('revoke',{token_hash:manage,acknowledge:true,notice_version:'teen-profile-v1'});assert.equal(await ready(),true);
 await revoke(manage);assert.equal(await ready(),false);
 await admin();assert.equal((await db.query('select mode from private.parent_browser_permissions where guardian_id=$1',[ids.guardian])).rows[0].mode,'revoked');
});
await scenario('Old profile-used invitation cannot undo a newer messaging withdrawal',async()=>{
 const older=await issue();await svc('approve',{token_hash:older,acknowledge:true,notice_version:'teen-profile-v1',review_photos:true});
 const manage=await manageLink();await revoke(manage);await as(null,'service_role');await blocked(()=>approve(older),/newer messaging/);assert.equal(await ready(),false);
});
for(const action of ['revoke','leave'])await scenario('Reviewer '+action+' stops delivery and media uploads; reassignment requires fresh parent approval',async()=>{
 await as(action==='revoke'?ids.coach:ids.reviewer);await review(action,{user_id:ids.reviewer});assert.equal(await ready(),false);
 await as(ids.coach);await blocked(()=>db.query('select public.send_communication_message($1,$2)',[thread,'Blocked']));
 await admin();assert.equal((await db.query('select private.can_upload_communication_media_object($1) r',[ids.team+'/'+thread+'/'+ids.coach+'/test.jpg'])).rows[0].r,false);
 await as(ids.coach);await review('assign',{user_id:ids.reviewer,confirm_adult:true});await as(ids.reviewer);await review('accept',{acknowledge:true});assert.equal(await ready(),false);
 const fresh=await issue();await approve(fresh);assert.equal(await ready(),true);
});
for(const [name,sql,args] of [
 ['reviewer membership ends','update public.team_memberships set active=false where team_id=$1 and user_id=$2',[ids.team,ids.reviewer]],
 ['assigning coach authority ends','update public.team_memberships set active=false where team_id=$1 and user_id=$2',[ids.team,ids.coach]],
 ['reviewer staff role changes',"update public.team_memberships set permissions='{\"staff_role\":\"limited_staff\"}' where team_id=$1 and user_id=$2",[ids.team,ids.reviewer]],
 ['parent contact changes',"update public.athlete_guardians set email='changed@example.test' where id=$1",[ids.guardian]],
 ['coach verification changes',"update private.parent_browser_verifications set verified_at=now()+interval '1 second' where guardian_id=$1",[ids.guardian]],
 ['consent expires',"update private.parent_browser_events set details=jsonb_set(details,'{expires_at}',to_jsonb((now()-interval '1 minute')::text)) where id=$1",[approval.id]],
 ['athlete is under 13',"update public.athletes set birth_date=current_date-interval '12 years' where id=$1",[ids.athlete]],
 ['reviewer feature disabled','update private.conversation_review_settings set enabled=false',[]],
 ['browser choices disabled','update private.parent_browser_settings set enabled=false',[]]
])await scenario('Delivery pauses when '+name,async()=>{await db.query(sql,args);assert.equal(await ready(),false);await as(ids.coach);await blocked(()=>db.query('select public.send_communication_message($1,$2)',[thread,'Blocked']));});
await scenario('Expired/replaced links, unaccepted reviewers and missing acknowledgments cannot approve messaging',async()=>{
 const fresh=await issue();await as(null,'service_role');await blocked(()=>preview(hash),/newest/);
 const p=await preview(fresh),r=p.reviewers[0],args={token_hash:fresh,reviewer_id:r.id,reviewer_version:r.version,allow_media:false,acknowledge:true,notice_version:'teen-messaging-v1'};
 for(const change of [{acknowledge:false},{notice_version:'teen-profile-v1'},{allow_media:'false'},{reviewer_version:'0'.repeat(64)},{reviewer_id:ids.stranger}]){await as(null,'service_role');await blocked(()=>svc('messaging_approve',{...args,...change}),/Review|reviewer|media permission/i);}
 await admin();await db.query("update private.parent_browser_links set expires_at=now()-interval '1 second' where token_hash=$1",[fresh]);await as(null,'service_role');await blocked(()=>preview(fresh),/newest/);
});
await scenario('Media requires its own opt-in and coach-led group/team messages include reviewer receipts',async()=>{
 const fresh=await issue();await approve(fresh,true);await as(ids.teen);const access=(await db.query('select public.get_communication_media_access($1) r',[thread])).rows[0].r;assert.equal(access.can_send,true);assert.equal(access.can_view,true);
 await admin();assert.equal((await db.query('select private.communication_minor_capability($1,$2,$3) r',[ids.team,ids.teen,'peer_to_peer'])).rows[0].r,false);
 assert.equal((await db.query('select private.can_upload_communication_media_object($1) r',[ids.team+'/'+thread+'/'+ids.teen+'/test.jpg'])).rows[0].r,true);
 await as(ids.coach);const group=(await db.query('select public.create_communication_thread($1,$2,$3,$4) id',[ids.team,ids.season,'Coach-led group',[ids.teen,ids.reviewer]])).rows[0].id;
 for(const kind of ['group','team','all_members']){
  await admin();await db.query('update public.communication_threads set kind=$2 where id=$1',[group,kind]);await as(ids.coach);const mid=(await db.query('select public.send_communication_message($1,$2) id',[group,'The schedule is posted.'])).rows[0].id;
  await admin();assert.equal((await db.query('select count(*) n from public.communication_message_receipts where message_id=$1 and user_id=$2',[mid,ids.reviewer])).rows[0].n,1);
  await as(ids.reviewer);assert.equal((await review('check',{thread_id:group})).allowed,true);
 }
 await admin();await db.query('update public.communication_thread_members set left_at=now() where thread_id=$1 and user_id=$2',[group,ids.coach]);assert.equal((await db.query('select private.parent_messaging_thread_ready($1) r',[group])).rows[0].r,false);
});
await scenario('Joining as a parent restores account controls and requires the parent to be included before sending resumes',async()=>{
 await db.query('update public.athlete_guardians set guardian_user_id=$2 where id=$1',[ids.guardian,ids.parent]);assert.equal(await ready(),false);
 await as(ids.coach);await blocked(()=>db.query('select public.send_communication_message($1,$2)',[thread,'No silent bypass']));
 await admin();await db.query('insert into public.athlete_chat_permissions(team_id,athlete_id,coach_to_athlete,approved_by_user_id,approved_at) values($1,$2,true,$3,now())',[ids.team,ids.athlete,ids.parent]);assert.equal(await ready(),false);
 await as(ids.coach);assert.equal((await db.query('select public.create_communication_thread($1,$2,$3,$4) id',[ids.team,ids.season,'Coach conversation',[ids.teen]])).rows[0].id,thread);assert.equal(await ready(),true);await send();
 await admin();assert.equal((await db.query("select count(*) n from public.communication_thread_members where thread_id=$1 and user_id=$2 and member_role='guardian_mirror' and left_at is null",[thread,ids.parent])).rows[0].n,1);assert.equal((await preview(hash)).eligible,false);
});
await scenario('A second verified parent withdrawal overrides another parent’s browser approval',async()=>{
 const guardian=uuid();await db.query("insert into public.athlete_guardians(id,athlete_id,name,email,invitation_status) values($1,$2,'Second Parent','second@example.test','pending')",[guardian,ids.athlete]);
 await as(ids.coach);await db.query('select public.parent_browser_verify($1,$2,true)',[guardian,ids.team]);await admin();
 await db.query("insert into private.parent_browser_events(guardian_id,event,notice_version,details) values($1,'revoked','teen-messaging-v1',$2)",[guardian,JSON.stringify({...approval,action:'messaging_revoke'})]);assert.equal(await ready(),false);
});
await scenario('Direct table writes cannot bypass the communication RPC and private consent helpers remain inaccessible',async()=>{
 await db.exec('alter table public.communication_messages enable row level security;grant insert on public.communication_messages to authenticated;');await as(ids.teen);
 await blocked(()=>db.query('insert into public.communication_messages(thread_id,team_id,sender_user_id,body) values($1,$2,$3,$4)',[thread,ids.team,ids.teen,'Bypass']),/row-level security/);
 for(const name of ['parent_messaging_service','parent_browser_profile_service'])await blocked(()=>db.query('select private.'+name+'($1,$2)',['messaging_approve',{}]),/permission denied/);
});

await writeFile('validation/parent-messaging-db.json',JSON.stringify({checks,realMessagesSent:false},null,2));await db.close();
