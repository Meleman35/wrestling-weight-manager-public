const fs=require('fs'),path=require('path'),{fixture:base,root}=require('./tournament-alerts-043-fixture.cjs');
async function fixture(db){
 const f=await base(db);await db.exec('reset role');
 await db.exec(`
 create role service_role;
 create function public.is_team_admin(t uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.team_memberships m where m.team_id=t and m.user_id=auth.uid() and m.active and (m.role='head_coach' or m.role in ('assistant_coach','manager') and m.permissions->>'team_admin'='true'))
 or exists(select 1 from public.teams tt join public.organization_memberships m on m.organization_id=tt.organization_id where tt.id=t and m.user_id=auth.uid() and m.role='organization_admin');$$;
 create table private.wm_equipment(id uuid primary key default gen_random_uuid(),team_id uuid not null references public.teams(id),title text not null,quantity int not null check(quantity between 1 and 10000),checked_out int not null default 0 check(checked_out>=0 and checked_out<=quantity),notes text not null default '',revision int not null default 0);
 create table private.wm_media(id uuid primary key default gen_random_uuid(),profile_id uuid,team_id uuid,path text not null,mime text not null,caption text not null default '',shared boolean not null default false,ready boolean not null default false,created_at timestamptz default now());
 alter table private.wm_equipment enable row level security;alter table private.wm_media enable row level security;
 create schema storage;create table storage.objects(bucket_id text,name text,metadata jsonb);
 create function private.wm_media_access(p text,w boolean) returns boolean language sql as $$select false$$;
 `);
 await db.exec(fs.readFileSync(path.join(root,'tests/plan-resources-existing.sql'),'utf8'));
 await db.exec('revoke all on function private.wm_team_access(uuid,boolean) from public,anon,authenticated;revoke all on function private.wm_resources(text,jsonb),public.wm_resources_request(text,jsonb) from public,anon;grant execute on function private.wm_resources(text,jsonb),public.wm_resources_request(text,jsonb) to authenticated;');
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260925173201_team_plan_foundation_02044.sql'),'utf8'));
 const plan=async(team=f.ids.team)=>(await db.query('select public.team_plan_request($1) r',[team])).rows[0].r;
 const resource=async(action,data={})=>(await db.query('select public.wm_resources_request($1,$2) r',[action,JSON.stringify({team:f.ids.team,...data})])).rows[0].r;
 const dates={start:new Date(Date.now()-86400000).toISOString(),end:new Date(Date.now()+364*86400000).toISOString()};
 const apply=async({event='purchase-1',team=f.ids.team,ref='verified-subscription-1',revision=0,status='active',start=dates.start,end=dates.end,provider='manual'}={})=>{
  await db.exec('reset role');return (await db.query('select private.apply_team_subscription_event($1,$2,$3,$4,$5,$6,$7,$8) revision',[provider,event,team,ref,revision,status,start,end])).rows[0].revision;
 };
 const pilot=async(enabled)=>{await db.exec('reset role');await db.query('update private.team_plan_settings set pilot_enabled=$1',[enabled]);};
 await f.as(f.ids.coach);return {...f,plan,resource,apply,pilot,dates};
}
module.exports={fixture,root};
