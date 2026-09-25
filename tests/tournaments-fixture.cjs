const fs=require('fs'),path=require('path'),{randomUUID}=require('crypto'),{fixture:goalsFixture,root}=require('./goals-fixture.cjs');
async function fixture(db){
 const f=await goalsFixture(db),ids={...f.ids,event:randomUUID(),otherEvent:randomUUID()};
 await db.exec('reset role');
 await db.exec(`create table public.team_events(id uuid primary key,team_id uuid,season_id uuid,event_type text,title text,starts_at timestamptz);`);
 await db.query("insert into public.team_events values($1,$2,$3,'tournament','Synthetic Invitational',now()),($4,$5,$6,'tournament','Other Team Event',now())",[ids.event,ids.team,ids.season,ids.otherEvent,ids.other,ids.otherseason]);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260925033022_tournament_foundation_02042.sql'),'utf8'));
 const call=async(action,data={})=>(await db.query('select public.tournament_request($1,$2) r',[action,JSON.stringify({team_id:ids.team,event_id:ids.event,...data})])).rows[0].r;
 const row=(overrides={})=>({id:randomUUID(),athlete_id:ids.a,division:'16U',weight_class:'120 lb',bout_number:'101',mat:'1',opponent:'Private Opponent',status:'queued',queue_order:1,estimated_start:new Date(Date.now()+30*60000).toISOString(),result:'',bracket_url:'https://example.test/bracket',revision:0,...overrides});
 await f.as(ids.coach);return {...f,ids,call,row};
}
module.exports={fixture,root};
