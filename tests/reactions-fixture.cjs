const fs=require('fs'),path=require('path'),{randomUUID}=require('crypto');
const root=path.resolve(__dirname,'..');
async function fixture(db){
 await db.exec(`create schema auth;create schema private;create role authenticated;create role anon;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.profiles(id uuid primary key,display_name text);
 create table public.communication_threads(id uuid primary key,team_id uuid,kind text,archived_at timestamptz,is_safety_test boolean default false);
 create table public.communication_thread_members(thread_id uuid,user_id uuid,left_at timestamptz,can_post boolean default true,member_role text default 'participant');
 create table public.communication_messages(id uuid primary key,thread_id uuid,created_at timestamptz default now(),deleted_at timestamptz,is_simulated boolean default false);
 create table public.communication_blocks(team_id uuid,user_id uuid,blocked_user_id uuid);
 create table private.team_logins(user_id uuid);
 create table public.fixture_access(team_id uuid,user_id uuid,active boolean default true,minor boolean default false,capability boolean default true);
 create function private.communication_user_belongs_to_team(t uuid,u uuid) returns boolean language sql as $$select exists(select 1 from public.fixture_access where team_id=t and user_id=u and active)$$;
 create function private.communication_user_is_minor(t uuid,u uuid) returns boolean language sql as $$select coalesce((select minor from public.fixture_access where team_id=t and user_id=u),false)$$;
 create function private.communication_minor_capability(t uuid,u uuid,c text) returns boolean language sql as $$select coalesce((select capability from public.fixture_access where team_id=t and user_id=u),false)$$;
 create function private.communication_person_name(t uuid,u uuid) returns text language sql as $$select display_name from public.profiles where id=u$$;`);
 const migration=fs.readdirSync(path.join(root,'supabase/migrations')).find(x=>x.endsWith('message_reactions_02041.sql'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',migration),'utf8'));
 const ids=Object.fromEntries(['user','mate','mirror','outsider','shared','minor','team','otherTeam','thread','otherThread','message','otherMessage','removed','simulated'].map(k=>[k,randomUUID()]));
 for(const k of ['user','mate','mirror','outsider','shared','minor'])await db.query('insert into public.profiles values($1,$2)',[ids[k],'Example '+k]);
 await db.query("insert into public.communication_threads(id,team_id,kind) values($1,$2,'direct'),($3,$4,'direct')",[ids.thread,ids.team,ids.otherThread,ids.otherTeam]);
 for(const k of ['user','mate','mirror','shared','minor']){await db.query('insert into public.fixture_access(team_id,user_id,minor) values($1,$2,$3)',[ids.team,ids[k],k==='minor']);await db.query('insert into public.communication_thread_members(thread_id,user_id,can_post,member_role) values($1,$2,$3,$4)',[ids.thread,ids[k],k!=='mirror',k==='mirror'?'guardian_mirror':'participant']);}
 await db.query('insert into public.fixture_access(team_id,user_id) values($1,$2)',[ids.otherTeam,ids.outsider]);await db.query('insert into public.communication_thread_members(thread_id,user_id) values($1,$2)',[ids.otherThread,ids.outsider]);
 for(const k of ['message','removed','simulated'])await db.query('insert into public.communication_messages(id,thread_id,deleted_at,is_simulated) values($1,$2,$3,$4)',[ids[k],ids.thread,k==='removed'?new Date():null,k==='simulated']);
 await db.query('insert into public.communication_messages(id,thread_id) values($1,$2)',[ids.otherMessage,ids.otherThread]);await db.query('insert into private.team_logins values($1)',[ids.shared]);
 async function as(uid){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid||'']);await db.exec('set role authenticated');}
 const call=async(action,data={})=>(await db.query('select public.message_reactions_request($1,$2) r',[action,JSON.stringify({thread_id:ids.thread,...data})])).rows[0].r;
 const list=()=>call('list',{message_ids:[ids.message]});const set=key=>call('set',{message_id:ids.message,reaction:key});
 await as(ids.user);return {ids,as,call,list,set};
}
module.exports={root,fixture};
