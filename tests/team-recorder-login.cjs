const assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),{randomUUID}=require('crypto');
const {PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite'),{fixture,root}=require('./tournaments-fixture.cjs');
(async()=>{
 const db=new PGlite(),{ids,as,call,row}=await fixture(db),passed=[];const pass=s=>{passed.push(s);console.log('PASS',s)};
 await call('setup',{timezone:'America/Denver'});const bouts=[row(),row({bout_number:'102'})];for(const b of bouts)await call('save_bout',b);
 await db.exec(`reset role;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(bucket_id text,name text,metadata jsonb);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,update,delete on storage.objects to authenticated;
 alter table private.team_logins add column id uuid default gen_random_uuid(),add column team_id uuid,add column kind text default 'team_device',add column active boolean default true,add column state text default 'ready',add column revision integer default 1,add column permissions jsonb default '{}',add column parent_id uuid,add column username text,add column display_name text,add column athlete_id uuid;
 create table auth.sessions(id uuid primary key,user_id uuid);create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create table private.team_login_sessions(session_id uuid primary key,login_id uuid,revision int,device_id uuid);
 create table private.team_login_devices(id uuid,parent_id uuid,credential_session_id uuid,current_session_id uuid,revision int);
 create table private.team_login_settings(team_id uuid,login_code text);create table private.team_login_attempts(bucket text);
 create schema extensions;create function extensions.digest(text,text) returns bytea language sql immutable as $$select decode(md5($1),'hex')$$;
 `);
 await db.exec(fs.readFileSync(path.join(__dirname,'team-recorder-login-existing.sql'),'utf8'));
 for(const ending of ['video_pilot_access_02046.sql','athlete_match_video_02046.sql','team_recorder_access_02065.sql','team_recorder_login_02066.sql'])await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',fs.readdirSync(path.join(root,'supabase/migrations')).find(x=>x.endsWith(ending))),'utf8'));
 const req=async(action,data={})=>(await db.query('select public.video_match_request($1,$2) r',[action,JSON.stringify({team_id:ids.team,...data})])).rows[0].r;
 const lease=async()=>(await db.query('select public.video_pilot_context($1) r',[ids.team])).rows[0].r;
 await db.exec('reset role;update private.video_pilot_control set enabled=true');await db.query("insert into private.video_pilot_grants values($1,$2,now()+interval '1 day',null)",[ids.team,ids.coach]);
 const perms=(await db.query("select private.team_login_permissions('team_device','{\"record_matches\":true,\"weigh_in\":true,\"attendance\":true,\"messages\":true,\"equipment\":true,\"checkout\":true,\"team_admin\":true}') p")).rows[0].p;
 assert.equal(perms.record_matches,true);for(const k of ['weigh_in','attendance','messages','equipment','checkout','team_admin','mass_text'])assert.equal(perms[k],false);
 assert.equal((await db.query("select private.team_login_permissions('test_athlete','{\"record_matches\":true}') p")).rows[0].p.record_matches,false);
 assert.equal((await db.query("select private.team_login_permissions('team_device','{\"weigh_in\":true}') p")).rows[0].p.weigh_in,true);pass('Server forces recording-only permissions and preserves existing Team Device tools');
 const user=randomUUID(),login=randomUUID(),sessions=[randomUUID(),randomUUID()];
 await db.query('insert into public.profiles values($1,$2)',[user,'Team Recorder']);
 await db.query('insert into private.team_logins(id,user_id,team_id,username,display_name,permissions) values($1,$2,$3,$4,$5,$6)',[login,user,ids.team,'mat-recorder','Team Recorder',perms]);
 await db.query("insert into public.team_memberships(team_id,user_id,role,permissions) values($1,$2,'manager',$3)",[ids.team,user,perms]);
 await db.query("insert into private.team_login_settings values($1,'TEAM-TEST')",[ids.team]);
 for(const sid of sessions){await db.query('insert into auth.sessions values($1,$2)',[sid,user]);assert.equal((await db.query("select private.register_team_login_session($1,$2,$3,1,'TEAM-TEST','mat-recorder') r",[login,user,sid])).rows[0].r,true);}
 const device=async(index)=>{await as(user);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({session_id:sessions[index]})]);};
 for(let i=0;i<2;i++){await device(i);const home=await req('device_context');assert.equal(home.team.id,ids.team);assert.equal(home.available,true);assert.equal(home.test_only,true);assert.equal((await lease()).allowed,true);assert.deepEqual((await lease()).athlete_ids,[]);assert.equal((await req('recorder_test')).data.video_test,true);await assert.rejects(()=>req('begin',{bout_id:bouts[0].id}),/Only the Test/);}
 pass('Two registered devices share one login independently; test-only and cloud-off gates stay intact');
 await assert.rejects(()=>req('device_context',{team_id:ids.other}),/Approved team recorder/);
 for(const action of ['recorder_settings','recorder_settings_save','event_settings','assign','manage','permission','remove','athlete'])await assert.rejects(()=>req(action),/recording only/);
 for(const resource of ['profiles','team_memberships','athlete_medical_private','rpc/get_team_join_code','rpc/save_operations','rpc/tournament_request']){await db.query("select set_config('request.path',$1,false)",['/'+resource]);await assert.rejects(()=>db.query('select private.enforce_team_login_request()'),/recording only/);}
 for(const name of ['get_my_team_login','video_match_request','video_pilot_context']){await db.query("select set_config('request.path',$1,false)",['/rpc/'+name]);await db.query('select private.enforce_team_login_request()');}
 assert.equal((await db.query("select private.managed_resource_allowed('profiles') r")).rows[0].r,false);await assert.rejects(()=>db.query('select private.video_recording_device($1)',[ids.team]),/permission denied/);pass('Cross-team access, administration, family libraries and direct table access are denied');
 await db.exec('reset role;update private.video_pilot_control set test_only=false');await as(ids.coach);await req('event_settings',{event_id:ids.event,permitted:true,rules:{style:'folkstyle',periods:[120,120,120],breakSeconds:0,takedown:3}});
 await device(0);assert.equal((await req('assignments')).bouts.length,0);
 await as(ids.parent);await req('permission',{athlete_id:ids.a,allowed:true});await device(0);assert.equal((await req('assignments')).bouts.length,0);
 await as(ids.parent);await call('visibility',{athlete_id:ids.a,level:'full',revision:0});
 const matches=[];for(let i=0;i<2;i++){await device(i);assert.equal((await req('assignments')).bouts.length,2);const m=await req('begin',{bout_id:bouts[i].id});matches.push(m);await req('save',{id:m.id,revision:m.revision,data:m.data});}
 assert.notEqual(matches[0].id,matches[1].id);await assert.rejects(()=>req('save',{id:matches[0].id,revision:matches[0].revision,data:matches[0].data}),/changed/);pass('Separate bouts save independently; stale writes cannot overwrite a match; parent and event checks remain required');
 await as(ids.parent);await req('permission',{athlete_id:ids.a,allowed:false});await device(0);assert.deepEqual((await lease()).athlete_ids,[]);assert.equal((await req('assignments')).bouts.length,0);pass('Guardian withdrawal removes authorized bouts and recording athletes');
 await db.exec('reset role');await db.query('update private.team_logins set revision=revision+1 where id=$1',[login]);for(let i=0;i<2;i++){await device(i);await assert.rejects(()=>req('device_context'),/Approved team recorder/);await assert.rejects(()=>db.query('select private.enforce_team_login_request()'),/TEAM_LOGIN_REVOKED/);}
 await db.exec('reset role');await db.query('update private.team_logins set revision=1,active=false where id=$1',[login]);await device(0);await assert.rejects(()=>req('recorder_test'),/Approved team recorder/);
 await db.exec('reset role');await db.query('update private.team_logins set active=true where id=$1',[login]);await db.query('delete from auth.sessions where id=$1',[sessions[0]]);await device(0);await assert.rejects(()=>req('device_context'),/Approved team recorder/);await device(1);assert.equal((await req('device_context')).team.id,ids.team);
 pass('Password/access revision changes revoke both devices; disabled accounts and signed-out sessions fail authorization');
 fs.writeFileSync(path.join(root,'validation/team-recorder-login.json'),JSON.stringify({passed,engine:'PGlite synthetic data using actual migrations and existing registered-session functions',productionDataChanged:false},null,2));await db.close();
})().catch(e=>{console.error(e);process.exit(1)});
