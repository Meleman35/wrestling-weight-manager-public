const assert=require('node:assert/strict'),fs=require('fs'),path=require('path');
const {PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const {fixture,root}=require('./goals-fixture.cjs');
(async()=>{
 const db=new PGlite(),{ids,as}=await fixture(db),passed=[];
 const pass=s=>{passed.push(s);console.log('PASS',s);};
 await db.exec('reset role');
 const migration=fs.readdirSync(path.join(root,'supabase/migrations')).find(p=>p.endsWith('video_pilot_access_02046.sql'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',migration),'utf8'));
 const call=async(team=ids.team)=>(await db.query('select public.video_pilot_context($1) r',[team])).rows[0].r;
 await as(ids.coach);assert.equal((await call()).allowed,false);pass('Pilot disabled with no initial grants');
 await db.exec('reset role');await db.query("insert into private.video_pilot_grants(team_id,user_id,expires_at) values($1,$2,now()+interval '1 hour')",[ids.team,ids.coach]);
 await as(ids.coach);assert.equal((await call()).allowed,false);
 await db.exec('reset role;update private.video_pilot_control set enabled=true');await as(ids.coach);
 const c=await call();assert(c.allowed);assert.equal(c.team_id,ids.team);assert.equal(c.user_id,ids.coach);assert.equal(c.lease_seconds,3600);assert.deepEqual(new Set(c.athlete_ids),new Set([ids.a,ids.b]));assert(!c.cloud_upload&&!c.live&&!c.billing);pass('Exact active coach/team grant returns bounded lease and active roster only');
 assert.equal((await call(ids.other)).allowed,false);
 for(const k of ['parent','athlete','outsider']){await as(ids[k]);assert.equal((await call()).allowed,false);}
 await as(ids.shared);await assert.rejects(call,/Personal coach/);pass('Wrong teams, parents, athletes, unrelated accounts and shared logins denied');
 await as(ids.coach);await assert.rejects(()=>db.query('select * from private.video_pilot_grants'),/permission denied/);
 await assert.rejects(()=>db.query("update private.video_pilot_control set enabled=true"),/permission denied/);pass('Client cannot read raw grants, enable pilot or grant itself access');
 await db.exec('reset role;set role anon');await assert.rejects(call,/permission denied/);pass('Anonymous access denied');
 for(const change of ["revoked_at=now()","revoked_at=null,expires_at=now()-interval '1 second'"]){await db.exec('reset role;update private.video_pilot_grants set '+change);await as(ids.coach);assert.equal((await call()).allowed,false);}
 await db.exec("reset role;update private.video_pilot_grants set expires_at=now()+interval '2 days',revoked_at=null");await as(ids.coach);assert.equal((await call()).lease_seconds,7200);
 await db.exec('reset role');await db.query('update public.team_memberships set active=false where user_id=$1',[ids.coach]);await as(ids.coach);assert.equal((await call()).allowed,false);pass('Revocation, expiry, membership removal and two-hour maximum enforced');
 const checks=await db.query("select p.proname,p.prosecdef,p.proconfig from pg_proc p where p.proname='video_pilot_context'");assert(checks.rows.every(r=>r.proconfig.includes('search_path=""')));
 fs.writeFileSync(path.join(root,'validation/video-pilot-db.json'),JSON.stringify({engine:'PGlite; synthetic existing schema, actual pilot migration',passed,productionApplied:false},null,2));await db.close();
})().catch(e=>{console.error(e);process.exit(1);});
