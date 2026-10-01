"""Build the reviewed linked-Creator draft. Never provisions a real account."""
from pathlib import Path
import json, re, sys, subprocess
root=Path(__file__).resolve().parents[1]
EXPECTED='c23b13b51ac8623fccd86341ae73c4a1db8c442a4a2f9698fd8761ec40993ca3'
check='--check' in sys.argv

def replace(s,old,new):
    if s.count(old)!=1: raise RuntimeError('Unexpected source near '+old[:90])
    return s.replace(old,new,1)
def put(path,text):
    p=root/path
    if check:
        if not p.exists() or p.read_text()!=text: raise RuntimeError('Generated file differs: '+path)
    else: p.write_text(text)

base=(root/'supabase/creator-offers.sql').read_text()
core=base[base.index('create function private.creator_access()'):]
core=core.replace('create function ','create or replace function ')
core=replace(core,"and exists(select 1 from private.creator_accounts c join auth.users u on u.id=c.user_id", "and exists(select 1 from private.creator_accounts c join auth.users u on u.id=auth.uid()\n  join auth.users workspace_owner on workspace_owner.id=c.user_id")
core=replace(core,"where c.user_id=auth.uid() and u.deleted_at is null", "where (c.user_id=auth.uid() or c.linked_user_id=auth.uid())\n   and workspace_owner.deleted_at is null and workspace_owner.email_confirmed_at is not null\n   and (workspace_owner.banned_until is null or workspace_owner.banned_until<=now())\n   and not exists(select 1 from private.team_logins where user_id=c.user_id)\n   and not exists(select 1 from private.scoped_deletion_jobs j where j.personal and j.sealed_at is not null\n    and j.subject_hash=encode(sha256(convert_to(c.user_id::text,'UTF8')),'hex'))\n   and u.deleted_at is null")
core=replace(core,'declare u uuid=auth.uid();d private.creator_offer_drafts%rowtype;offer uuid;', 'declare u uuid=auth.uid();workspace_owner uuid;linked_user uuid;capable boolean;\n d private.creator_offer_drafts%rowtype;offer uuid;')
old=""" if p_action='access' then return jsonb_build_object('creator',private.creator_access());end if;
 if not private.creator_access() then raise sqlstate '42501' using message='Creator access is unavailable for this account';end if;
 -- Serialize owner mutations and revocation. No team or organization role confers access.
 perform 1 from private.creator_accounts where user_id=u for update;
 if not found then raise sqlstate '42501' using message='Creator access was removed';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4096 then raise exception 'Invalid offer request';end if;"""
new=""" if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4096 then raise exception 'Invalid offer request';end if;
 select user_id,linked_user_id into workspace_owner,linked_user from private.creator_accounts
  where user_id=u or linked_user_id=u;
 capable:=coalesce(private.creator_access() and (u=workspace_owner or p_data->>'client'='creator-linked-v1'),false);
 -- Legacy clients must not route a linked personal account into the owner-only home.
 if p_action='access' then return jsonb_build_object('creator',capable,'home_mode',
  case when capable then case when u=workspace_owner then 'dedicated' else 'team' end else null end);end if;
 if not capable then raise sqlstate '42501' using message='Creator access is unavailable. Refresh the app and try again.';end if;
 -- Both logins lock the same workspace row. Revocation cannot race an offer mutation.
 select user_id,linked_user_id into workspace_owner,linked_user from private.creator_accounts
  where user_id=u or linked_user_id=u for update;
 if not found or not private.creator_access() then raise sqlstate '42501' using message='Creator access was removed';end if;
 p_data:=p_data-'client';"""
core=replace(core,old,new)
core=core.replace('d.created_by=u','d.created_by=workspace_owner').replace('created_by=u and','created_by=workspace_owner and').replace('values(offer,u,code_value','values(offer,workspace_owner,code_value')
core=replace(core,'from private.creator_offer_drafts x where created_by=u;', 'from private.creator_offer_drafts x where created_by=workspace_owner;')
core=replace(core,"from (select action,offer_id,created_at from private.creator_offer_events where actor_id=u order by created_at desc limit 20) x;", """from (select e.action,e.offer_id,e.created_at,
    case when e.actor_id=u then 'This login' when e.actor_id=workspace_owner then 'Creator owner' else 'Linked personal login' end actor_label
   from private.creator_offer_events e where e.actor_id=workspace_owner or e.actor_id=linked_user
    or exists(select 1 from private.creator_offer_drafts o where o.id=e.offer_id and o.created_by=workspace_owner)
   order by e.created_at desc,e.id desc limit 20) x;""")
core=replace(core,"return jsonb_build_object('creator',true,'offers',offers", "return jsonb_build_object('creator',true,'home_mode',case when u=workspace_owner then 'dedicated' else 'team' end,'workspace_shared',linked_user is not null,'offers',offers")
core="""-- BEGIN LINKED CREATOR CORE
-- One optional, operator-provisioned login. No email or JWT metadata grants access.
alter table private.creator_accounts add column linked_user_id uuid unique references auth.users(id) on delete set null;
alter table private.creator_accounts add constraint creator_accounts_distinct_logins check(linked_user_id is null or linked_user_id<>user_id);
"""+core+'-- END LINKED CREATOR CORE\n'
compat=(root/'supabase/creator-offers-compatibility.sql').read_text().replace('27d274de0c35fb69ae2ed5ff35a959b9b001de1ef865fad1a804b5ba8b39f57e',EXPECTED)
guard="""-- Linked Creator access. Deploy only with the matching reviewed deletion-worker policy.
-- No account is enrolled by this migration. Billing, team roles and health access are unchanged.
begin;
lock table private.creator_accounts in access exclusive mode;
do $$begin
 if private.scoped_deletion_schema_hash()<>'EXPECTED_HASH'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Linked Creator access requires a fresh schema compatibility review';end if;
 if exists(select 1 from private.scoped_deletion_jobs where state not in ('completed','cancelled'))
 then raise exception 'Finish or review existing deletion jobs before this migration';end if;
end $$;
""".replace('EXPECTED_HASH',EXPECTED)
put('supabase/creator-linked-access.sql',guard+core+compat+'\ncommit;\n')

s=(root/'src/creator-offers.js').read_text()
marker='/* Linked Creator workspace v1: team navigation is never replaced for a linked login. */\n'
if not s.startswith(marker):
    s=replace(s,"let generation=0,owner=''", "let accessMode='',generation=0,owner=''")
    s=replace(s,"function hideAccess(){accessGeneration++;show('creatorOffersBtn',false)}", "function hideAccess(){accessGeneration++;accessMode='';show('creatorOffersBtn',false);show('creatorDashboardMoreBtn',false)}")
    s=replace(s,"const g=accessGeneration,u=identity();lastActor=actor();if(!u||!navigator.onLine)return false;", "const g=accessGeneration,u=actor();lastActor=actor();if(!u||!navigator.onLine)return false;")
    s=replace(s,"p_action:'access',p_data:{}", "p_action:'access',p_data:{client:'creator-linked-v1'}")
    s=replace(s,"g===accessGeneration&&u===identity()&&navigator.onLine&&!error&&out?.creator===true){show('creatorOffersBtn',true);return true}", "g===accessGeneration&&u===actor()&&navigator.onLine&&!error&&out?.creator===true){accessMode=out.home_mode==='team'?'team':'dedicated';show('creatorOffersBtn',true);show('creatorDashboardMoreBtn',true);return true}")
    s=replace(s,"if(!u||!await refreshAccess()||g!==homeGeneration||u!==identity())return false;", "if(!u||!await refreshAccess()||g!==homeGeneration||u!==actor()||accessMode!=='dedicated')return false;")
    s=replace(s,"p_action:action,p_data:body", "p_action:action,p_data:{...body,client:'creator-linked-v1'}")
    s=replace(s,"<h2 id=\"creatorTitle\">Offers & Trial</h2>", "<h2 id=\"creatorTitle\">Creator Dashboard</h2>")
    s=replace(s,"<div id=\"creatorOfferStatus\" role=\"status\"></div>", "<button id=\"creatorReturnToTeam\" type=\"button\" class=\"secondary hidden\">‹ Return to Team</button><div id=\"creatorOfferStatus\" role=\"status\"></div>")
    s=replace(s,"function render(){", "function render(){\n  show('creatorReturnToTeam',data.home_mode==='team'||accessMode==='team');")
    s=replace(s,"${esc(new Date(e.created_at).toLocaleString())}</p>", "${esc(new Date(e.created_at).toLocaleString())}${e.actor_label?' · '+esc(e.actor_label):''}</p>")
    s=replace(s,"$c('creatorOfferBody').replaceChildren();status('');show(sheet.id,false);", "$c('creatorOfferBody').replaceChildren();show('creatorReturnToTeam',false);status('');show(sheet.id,false);")
    s=replace(s,"$c('creatorOffersBtn').onclick=open;", """$c('creatorOffersBtn').textContent='Creator Dashboard';
 const more=document.createElement('button');more.type='button';more.id='creatorDashboardMoreBtn';more.className='menu-row hidden';
 more.innerHTML='<span>⚙️</span><div><b>Creator Dashboard</b><small>Shared app management workspace</small></div><i>›</i>';
 $c('moreTab').querySelector('.toolbox-title').after(more);more.onclick=open;
 $c('creatorReturnToTeam').onclick=()=>closeSheets();
 $c('creatorOffersBtn').onclick=open;""")
    s=replace(s,"if(u!==lastActor){lastActor=u;hideAccess();close()}", "if(u!==lastActor){lastActor=u;hideAccess();close();if(u&&navigator.onLine)void refreshAccess()}")
    s=replace(s,"document.addEventListener('visibilitychange',()=>{if(document.hidden){close();hideAccess()}});", "window.addEventListener('online',()=>void refreshAccess());document.addEventListener('visibilitychange',()=>{if(document.hidden){close();hideAccess()}else void refreshAccess()});")
    s=marker+s
put('src/creator-offers.js',s)
policy=json.loads((root/'scripts/scoped-deletion-policy.json').read_text())
edge='private.creator_accounts.linked_user_id'
if edge not in policy['nullUserEdges']: policy['nullUserEdges'].append(edge)
put('scripts/scoped-deletion-policy.json',json.dumps(policy,indent=2)+'\n')
if not check:
    subprocess.run([sys.executable,str(root/'scripts/patch-creator-offers.py')],check=True,cwd=root)
else:
    subprocess.run([sys.executable,str(root/'scripts/patch-creator-offers.py'),'--check'],check=True,cwd=root)
print('PASS Linked Creator sources generated' if not check else 'PASS Linked Creator sources consistent')

# Reuse the complete production-shaped fixture and actual planner, not a toy catalog.
t=(root/'tests/practice-plans-compatibility.mjs').read_text()
t=t[:t.index("await db.exec('alter table private.practice_plans add column fixture_drift")]
t+='''
await db.exec("create table private.scoped_deletion_jobs(state text,subject_hash text,personal boolean,sealed_at timestamptz)");
const linkedMigration=(await readFile('supabase/creator-linked-access.sql','utf8')).replaceAll('LIVE_HASH',final.current);
await db.exec(linkedMigration);
const linkedCatalog=(await db.query('select catalog,catalog_hash,private.scoped_deletion_schema_hash() current from private.scoped_deletion_config')).rows[0];
assert.equal(linkedCatalog.current,linkedCatalog.catalog_hash);assert.notEqual(linkedCatalog.current,final.current);
assert((await db.query("select pg_get_functiondef('private.athlete_merge_request(text,jsonb)'::regprocedure) d")).rows[0].d.includes(linkedCatalog.current));
await db.query('insert into private.creator_accounts(user_id,linked_user_id) values($1,$2)',[owner,other]);
const offerId=uuid();
await db.query("insert into private.creator_offer_drafts(id,created_by,code,product,discount_percent,billing_periods,redemption_limit,expires_at) values($1,$2,'SHARED','team_pro_year',20,1,100,now()+interval '1 day')",[offerId,owner]);
await db.query("insert into private.creator_offer_events(actor_id,offer_id,action,detail) values($1,$2,'create','{}')",[other,offerId]);
const linkedPlan=await planDeletion({scope:{actorId:other,kind:'personal',teamIds:[],organizationIds:[]},catalog:linkedCatalog.catalog,reader});
const grant=linkedPlan.records.find(x=>x.table==='private.creator_accounts');assert.equal(grant.action,'null');assert.deepEqual(grant.columns,['linked_user_id']);
assert(!linkedPlan.records.some(x=>x.table==='private.creator_offer_drafts'));
assert(!linkedPlan.records.some(x=>x.table==='auth.users'&&x.key.id===owner));
const ownerPlan=await planDeletion({scope:{actorId:owner,kind:'personal',teamIds:[],organizationIds:[]},catalog:linkedCatalog.catalog,reader});
assert(ownerPlan.records.some(x=>x.table==='private.creator_accounts'&&x.action==='delete'));
assert(ownerPlan.records.some(x=>x.table==='private.creator_offer_drafts'&&x.action==='delete'));
assert(!ownerPlan.records.some(x=>x.table==='auth.users'&&x.key.id===other));
pass('Actual deletion planner unlinks the personal account without erasing the owner workspace or another identity');
await db.exec('alter table private.creator_accounts add column fixture_drift text');
assert.notEqual((await db.query('select private.scoped_deletion_schema_hash() h')).rows[0].h,linkedCatalog.catalog_hash);
pass('Exact deletion and merge schema-drift guards remain active after linked Creator migration');
await db.close();
'''.replace('LIVE_HASH',EXPECTED)
put('tests/creator-linked-access-compatibility.mjs',t)
