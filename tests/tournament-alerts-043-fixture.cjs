const fs=require('fs'),path=require('path'),{fixture:base,root}=require('./tournaments-fixture.cjs');
async function fixture(db){
 const f=await base(db);await db.exec('reset role');
 await db.exec(`alter table public.team_memberships add column notifications_paused boolean default false;
 alter table public.teams add column organization_id uuid;
 create table public.organization_memberships(organization_id uuid,user_id uuid,role text);
 create table public.communication_notifications(id uuid);
 create table public.communication_delivery_queue(id uuid);`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260925043538_tournament_alert_preferences_02043.sql'),'utf8'));
 const preferences=async(action='get',data={})=>(await db.query('select public.tournament_alert_preferences($1,$2) r',[action,JSON.stringify({team_id:f.ids.team,...data})])).rows[0].r;
 const tick=async(now=new Date())=>{await db.exec('reset role');return (await db.query('select private.prepare_tournament_alert_drafts($1,100) r',[now.toISOString()])).rows[0].r;};
 const due=async()=>{await db.exec('reset role');await db.exec("update private.tournament_alert_preferences set next_check_at='2000-01-01'");};
 await f.as(f.ids.coach);return {...f,preferences,tick,due};
}
module.exports={fixture,root};
