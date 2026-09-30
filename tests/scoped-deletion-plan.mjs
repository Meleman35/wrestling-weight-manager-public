import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {fixture} from './helpers/scoped-deletion-db.mjs';
import {planDeletion,validateScope,ScopeError} from '../scripts/scoped-deletion-plan.mjs';
const passed=[],pass=x=>{passed.push(x);console.log('PASS',x);};
const id=()=>randomUUID();
const a=id(),b=id(),child=id(),o1=id(),o2=id(),t1=id(),t2=id(),s1=id(),s2=id(),ap=id(),ath=id(),unclaimedProfile=id(),unclaimed=id(),w=id(),th1=id(),th2=id(),m1=id(),m2=id(),reply=id(),g1=id(),g2=id();
const {db,reader,catalog}=await fixture();
const input=(kind='all',teams=[t1],orgs=[o1])=>({actorId:a,kind,teamIds:teams,organizationIds:orgs});
const plan=scope=>planDeletion({scope,catalog,reader});
try{
 await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$4,now()),($2,$5,now()),($3,$6,now())',[a,b,child,'a@example.invalid','b@example.invalid','child@example.invalid']);
 await db.query('insert into public.profiles(id,display_name) values($1,$4),($2,$5),($3,$6)',[a,b,child,'Departing adult','Retained adult','Retained child']);
 await db.query('insert into public.organizations(id,name) values($1,$3),($2,$4)',[o1,o2,'Selected organization','Surviving organization']);
 await db.query('insert into public.teams(id,organization_id,name) values($1,$3,$5),($2,$4,$6)',[t1,t2,o1,o2,'Selected team','Surviving team']);
 await db.query('insert into public.seasons(id,team_id,name) values($1,$3,$5),($2,$4,$5)',[s1,s2,t1,t2,'Synthetic season']);
 await db.query('insert into public.athlete_profiles(id) values($1),($2)',[ap,unclaimedProfile]);
 await db.query("insert into public.athletes(id,organization_id,profile_id,first_name,last_name) values($1,$3,$4,'Shared','Child'),($2,$3,$5,'Unclaimed','Athlete')",[ath,unclaimed,o1,ap,unclaimedProfile]);
 await db.query("insert into private.wrestling_profiles(id,user_id,name) values($1,$2,'Departing adult')",[w,a]);
 await db.query("insert into private.wrestling_profiles(athlete_profile_id,name) values($1,'Retained child')",[ap]);
 await db.query("insert into public.team_memberships(team_id,user_id,role) values($1,$3,'head_coach'),($2,$3,'assistant_coach'),($1,$4,'manager'),($2,$4,'head_coach')",[t1,t2,a,b]);
 await db.query("insert into public.team_memberships(team_id,user_id,role,athlete_id) values($1,$3,'athlete',$4),($2,$3,'athlete',$4)",[t1,t2,child,ath]);
 await db.query("insert into public.organization_memberships(organization_id,user_id,role) values($1,$3,'organization_admin'),($2,$3,'assistant_coach'),($1,$4,'head_coach'),($2,$4,'organization_admin')",[o1,o2,a,b]);
 await db.query('insert into public.roster_memberships(season_id,athlete_id) values($1,$3),($2,$3),($1,$4)',[s1,s2,ath,unclaimed]);
 await db.query("insert into public.athlete_guardians(id,athlete_id,guardian_user_id,name,email) values($1,$3,$4,'Departing guardian','a@example.invalid'),($2,$3,$5,'Retained guardian','b@example.invalid')",[g1,g2,ath,a,b]);
 await db.query("insert into public.communication_threads(id,team_id,kind,created_by) values($1,$3,'group',$5),($2,$4,'group',$5)",[th1,th2,t1,t2,a]);
 await db.query("insert into public.communication_messages(id,thread_id,team_id,sender_user_id,body) values($1,$3,$5,$7,'Own selected-team message'),($2,$4,$6,$7,'Own other-team message')",[m1,m2,th1,th2,t1,t2,a]);
 await db.query("insert into public.communication_messages(id,thread_id,team_id,sender_user_id,reply_to_message_id,body) values($1,$2,$3,$4,$5,'Other person reply must stay')",[reply,th2,t2,b,m2]);
 await db.query("insert into public.communication_attachments(message_id,thread_id,team_id,uploader_user_id,storage_path,mime_type,size_bytes) values($1,$2,$3,$4,'synthetic/message.jpg','image/jpeg',100)",[m1,th1,t1,a]);
 await db.query("insert into public.communication_message_audit(message_id,thread_id,team_id,actor_user_id,event_type,body_snapshot) values($1,$2,$3,$4,'created','Own message snapshot')",[m1,th1,t1,a]);
 await db.query("insert into public.audit_log(actor_user_id,action,entity_type,metadata) values($1::uuid,'fixture','profile',jsonb_build_object('user',($1::uuid)::text))",[a]);

 const all=await plan(input());
 const deletes=all.records.filter(x=>x.action==='delete'),row=(table,key)=>all.records.find(x=>x.table===table&&Object.entries(key).every(([k,v])=>x.key[k]===v));
 assert.equal(row('public.profiles',{id:a}).action,'delete');assert.ok(!row('public.profiles',{id:b}));assert.ok(!row('public.profiles',{id:child}));
 assert.equal(row('private.wrestling_profiles',{id:w}).action,'delete');
 assert.ok(!deletes.some(x=>['public.athletes','public.athlete_profiles'].includes(x.table)));
 for(const aid of [ath,unclaimed]){assert.equal(row('public.athletes',{id:aid}).action,'null');assert.deepEqual(row('public.athletes',{id:aid}).columns,['organization_id']);}
 assert.ok(!row('public.teams',{id:t2}));assert.ok(!row('public.organizations',{id:o2}));
 assert.equal(row('public.communication_messages',{id:reply}).action,'null');assert.deepEqual(row('public.communication_messages',{id:reply}).columns,['reply_to_message_id']);
 assert.equal(row('public.communication_messages',{id:m2}).action,'delete');assert.equal(row('public.athlete_guardians',{id:g1}).action,'delete');assert.ok(!row('public.athlete_guardians',{id:g2}));
 assert.equal(all.records.filter(x=>x.table==='auth.users').length,1);assert.equal(all.records.find(x=>x.table==='auth.users').key.id,a);
 pass('Combined scope removes only its actor identity and selected workspaces, while preserving shared/unclaimed athletes, another guardian and the other person’s reply');

 const team=await plan(input('team',[t1],[]));
 assert.ok(!team.records.some(x=>['auth.users','public.profiles','private.wrestling_profiles','public.athlete_profiles','public.athletes'].includes(x.table)));
 assert.ok(!team.records.some(x=>x.table==='public.communication_messages'&&x.key.id===m2));
 assert.ok(!team.records.some(x=>x.table==='public.athlete_guardians'));
 pass('Team-only closure plans zero personal identities or guardian removals and preserves other-team messages');

 const personal=await plan(input('personal',[],[]));
 assert.ok(!personal.records.some(x=>['public.teams','public.organizations','public.seasons','public.athletes'].includes(x.table)));
 assert.equal(personal.records.filter(x=>x.table==='public.team_memberships'&&x.action==='delete').length,2);
 assert.equal(personal.records.filter(x=>x.table==='public.organization_memberships'&&x.action==='delete').length,2);
 assert.ok(personal.records.some(x=>x.table==='public.communication_message_audit'&&x.action==='delete'));
 pass('Personal-only planning spans all memberships and own messages/snapshots without closing any team or organization');

 await assert.rejects(()=>plan(input('organization',[],[o1])),e=>e instanceof ScopeError&&e.code==='linked_teams_not_selected');
 await assert.rejects(()=>plan(input('all',[],[o1])),e=>e.code==='linked_teams_not_selected');
 for(const value of [input('all',[],[]),input('personal',[t1],[]),input('team',[t1,t2],[]),input('team',[t1],[o1]),input('all',[t1,t1],[o1]),{...input(),actorId:'bad'}])assert.throws(()=>validateScope(value),ScopeError);
 pass('Unselected linked teams, empty combined requests, duplicate IDs and cross-scope payloads are rejected');

 await db.query("insert into public.communication_safety_flags(message_id,team_id,rule_code,severity,source) values($1,$2,'test-retention','low','automatic')",[m1,t1]);
 await assert.rejects(()=>plan(input()),e=>e.code==='unreviewed_dependency'&&e.details.table==='public.communication_safety_flags');
 await db.query('delete from public.communication_safety_flags where message_id=$1',[m1]);
 await db.query("insert into private.ops_audit(organization_id,actor_id,action) values($1,$2,'Unreviewed audit')",[o2,a]);
 await assert.rejects(()=>plan(input()),e=>e.code==='unreviewed_identity_reference'&&e.details.table==='private.ops_audit');
 await db.query('delete from private.ops_audit where actor_id=$1',[a]);
 pass('Unreviewed safety records and identity references without foreign keys stop planning before any erasure');

 await db.query("update public.profiles set ui_preferences=jsonb_build_object('copied_identity',$1::text) where id=$2",[a,b]);
 await assert.rejects(()=>plan(input()),e=>e.code==='unreviewed_identity_snapshot'&&e.details.table==='public.profiles');
 await db.query("update public.profiles set ui_preferences='{}' where id=$1",[b]);
 await db.query("insert into public.team_memberships(team_id,user_id,role,athlete_id) values($1,$2,'athlete',$3)",[t1,a,ath]);
 await assert.rejects(()=>plan(input()),e=>e.code==='athlete_identity_review_required');
 await db.query("delete from public.team_memberships where user_id=$1 and role='athlete'",[a]);
 pass('Copied identity snapshots and ambiguous athlete-bound personal profiles are blocked rather than deleting another person’s data');

 const summary=(await db.query('select (select count(*) from auth.users)::int users,(select count(*) from public.profiles)::int profiles,(select count(*) from public.athletes)::int athletes,(select count(*) from public.teams)::int teams,(select count(*) from public.communication_messages)::int messages')).rows[0];
 assert.deepEqual(summary,{users:3,profiles:3,athletes:2,teams:2,messages:3});
 await assert.rejects(()=>planDeletion({scope:input(),catalog,reader,maxRows:2}),e=>e.code==='scope_too_large');
 pass('Planning itself performs no deletion and bounded plans fail before oversized execution');
 await writeFile(new URL('../validation/scoped-deletion-plan.json',import.meta.url),JSON.stringify({passed,tableCount:catalog.tables.length,realDataChanged:false,limits:'Structural PostgreSQL fixture with synthetic people. Planning only; not provider/Auth/device erasure acceptance.'},null,2));
}finally{await db.close();}
