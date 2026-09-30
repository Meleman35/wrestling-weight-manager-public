// The same planner is used by the service worker and isolated PostgreSQL tests.
// It reads through an injected, bounded adapter. It cannot mutate or infer consent.
import policy from './scoped-deletion-policy.json' with {type:'json'};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const identifier=/^[a-z_][a-z0-9_]*$/;
export class ScopeError extends Error {
  constructor(code,details={}){super(code);this.code=code;this.details=details;}
}
const sortedObject=x=>Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b)));
const canonical=x=>JSON.stringify(sortedObject(x));
const qualified=(schema,table)=>schema+'.'+table;
const set=x=>new Set(x);

export function validateScope(input){
  if(!input||!uuid.test(input.actorId)||!['personal','team','organization','all'].includes(input.kind))throw new ScopeError('invalid_scope');
  for(const key of ['teamIds','organizationIds']){
    if(!Array.isArray(input[key])||input[key].length>100||input[key].some(x=>typeof x!=='string'||!uuid.test(x)))throw new ScopeError('invalid_targets');
    if(new Set(input[key].map(x=>x.toLowerCase())).size!==input[key].length)throw new ScopeError('duplicate_targets');
  }
  const personal=['personal','all'].includes(input.kind);
  if(input.kind==='personal'&&(input.teamIds.length||input.organizationIds.length))throw new ScopeError('unexpected_workspace');
  if(input.kind==='team'&&(input.teamIds.length!==1||input.organizationIds.length))throw new ScopeError('invalid_team_scope');
  if(input.kind==='organization'&&(input.organizationIds.length!==1||input.teamIds.length))throw new ScopeError('invalid_organization_scope');
  if(input.kind==='all'&&!input.teamIds.length&&!input.organizationIds.length)throw new ScopeError('empty_combined_scope');
  return Object.freeze({actorId:input.actorId.toLowerCase(),kind:input.kind,personal,
    teamIds:Object.freeze(input.teamIds.map(x=>x.toLowerCase()).sort()),organizationIds:Object.freeze(input.organizationIds.map(x=>x.toLowerCase()).sort())});
}

export function catalogIndex(catalog){
  const tables=new Map();
  for(const t of catalog.tables){
    if(!['public','private'].includes(t.schema)||!identifier.test(t.name)||!Array.isArray(t.columns))throw new ScopeError('invalid_catalog');
    const name=qualified(t.schema,t.name);
    if(tables.has(name)||t.columns.some(x=>!identifier.test(x.name)))throw new ScopeError('invalid_catalog');
    const pk=catalog.constraints.find(k=>k.type==='p'&&k.schema===t.schema&&k.table===t.name)?.columns||[];
    tables.set(name,{...t,name,pk,columns:new Map(t.columns.map(x=>[x.name,x]))});
  }
  // Only the primary key of Auth is needed. Never request an Auth row or credential.
  tables.set('auth.users',{name:'auth.users',pk:['id'],columns:new Map([['id',{name:'id',nullable:false}]])});
  const fks=catalog.constraints.filter(x=>x.type==='f').map(k=>{
    if(!k.columns?.length||k.columns.length!==k.ref_columns?.length||!['a','r','c','n','d'].includes(k.delete_action))throw new ScopeError('invalid_catalog');
    if(k.columns.some(x=>!identifier.test(x))||k.ref_columns.some(x=>!identifier.test(x)))throw new ScopeError('invalid_catalog');
    return {...k,child:qualified(k.schema,k.table),parent:qualified(k.ref_schema,k.ref_table)};
  });
  return {tables,fks};
}

// Every policy has an explicit default: an affected, unreviewed dependency blocks.
// Delete actions are NOT inferred solely from foreign-key CASCADE or uploader IDs.
export async function planDeletion({scope:input,catalog,reader,maxRows=25000}){
  const scope=validateScope(input),{tables,fks}=catalogIndex(catalog);
  if(typeof reader?.select!=='function'||!Number.isInteger(maxRows)||maxRows<1||maxRows>100000)throw new ScopeError('invalid_reader');
  const deletable=set(policy.deleteTables),userDeletes=set(policy.deleteUserEdges),userNulls=set(policy.nullUserEdges);
  const records=new Map(),queue=[],pending=[],observations=[],readCache=new Map();
  function keyFor(table,row){
    const definition=tables.get(table);
    if(!definition||!definition.pk.length)throw new ScopeError('unreviewed_primary_key',{table});
    if(row.__deletion_key){
      if(Object.keys(row.__deletion_key).sort().join(',')!==[...definition.pk].sort().join(',')||Object.values(row.__deletion_key).some(v=>typeof v!=='string'))throw new ScopeError('invalid_record_key',{table});
      return sortedObject(row.__deletion_key);
    }
    const key={};for(const col of definition.pk){if(row[col]===undefined||row[col]===null)throw new ScopeError('invalid_record_key',{table});key[col]=row[col];}
    return sortedObject(key);
  }
  function tag(table,key){return table+':'+canonical(key);}
  async function select(table,predicates){
    if(!tables.has(table)||!Array.isArray(predicates)||predicates.some(p=>!Object.keys(p).length||Object.keys(p).some(c=>!tables.get(table).columns.has(c))))throw new ScopeError('invalid_query');
    if(!predicates.length)return [];
    const cacheKey=table+':'+JSON.stringify(predicates.map(sortedObject));
    if(readCache.has(cacheKey))return readCache.get(cacheKey);
    const rows=await reader.select(table,predicates,maxRows+1);
    if(!Array.isArray(rows)||rows.length>maxRows)throw new ScopeError('scope_too_large');
    const seen=new Set();for(const row of rows){const k=tag(table,keyFor(table,row));if(seen.has(k))throw new ScopeError('duplicate_query_row');seen.add(k);}
    // The service seals this observation set while holding the affected write locks.
    observations.push({table,predicates:predicates.map(sortedObject),rows:rows.map(row=>({key:keyFor(table,row),row}))});
    readCache.set(cacheKey,rows);return rows;
  }
  function add(table,row,action,origin,columns=[]){
    const key=keyFor(table,row),id=tag(table,key),existing=records.get(id);
    if(existing?.action==='delete'||existing?.action==='auth')return existing;
    if(action==='delete'){
      if(!deletable.has(table))throw new ScopeError('unreviewed_record',{table});
      if(table==='public.profiles'&&(!scope.personal||row.id!==scope.actorId))throw new ScopeError('protected_personal_identity');
      if(table==='private.wrestling_profiles'&&(!scope.personal||row.user_id!==scope.actorId||row.athlete_profile_id!==null))throw new ScopeError('athlete_identity_review_required');
      if(table==='public.team_memberships'&&scope.personal&&row.user_id===scope.actorId&&row.role==='athlete'&&row.athlete_id)throw new ScopeError('athlete_identity_review_required');
      if(origin.kind!=='personal'&&row.team_id&&row.team_id!==origin.id&&!scope.teamIds.includes(row.team_id))throw new ScopeError('shared_workspace_dependency',{table});
      if(origin.kind==='organization'&&row.organization_id&&row.organization_id!==origin.id)throw new ScopeError('shared_workspace_dependency',{table});
    }
    if(action==='null'&&columns.some(c=>!tables.get(table).columns.get(c)?.nullable))throw new ScopeError('nonnullable_shared_record',{table,columns});
    if(existing&&action==='null'){existing.columns=[...new Set([...existing.columns,...columns])].sort();return existing;}
    const entry={table,key,action,columns:[...columns].sort(),origin,row};records.set(id,entry);
    if(action==='delete'||action==='auth')queue.push(entry);
    if(records.size>maxRows)throw new ScopeError('scope_too_large');return entry;
  }
  async function seed(table,predicates,origin){for(const row of await select(table,predicates))add(table,row,'delete',origin);}
  if(scope.personal){
    add('auth.users',{id:scope.actorId},'auth',{kind:'personal',id:scope.actorId});
    await seed('public.profiles',[{id:scope.actorId}],{kind:'personal',id:scope.actorId});
  }
  for(const [table,ids,kind] of [['public.teams',scope.teamIds,'team'],['public.organizations',scope.organizationIds,'organization']]){
    for(const id of ids){const rows=await select(table,[{id}]);if(rows.length!==1)throw new ScopeError('target_changed');add(table,rows[0],'delete',{kind,id});}
  }
  // Reviewed sources that deliberately have no FK, including snapshots and retry logs.
  const extras=[
    ['public.audit_log','actor_user_id','personal'],['public.communication_message_audit','actor_user_id','personal'],
    ['private.wrestling_role_review_log','reviewer_id','personal'],['private.event_series_edits','actor','personal'],
    ['public.practice_series','created_by','personal-null'],['public.practice_series_exceptions','created_by','personal-null'],
    ['private.conversation_review_events','actor_id','personal'],['private.conversation_review_events','subject_id','personal']
  ];
  for(const [table,col,kind] of extras){
    if(!scope.personal||!tables.get(table)?.columns.has(col))continue;
    for(const row of await select(table,[{[col]:scope.actorId}]))add(table,row,kind==='personal-null'?'null':'delete',{kind:'personal',id:scope.actorId},kind==='personal-null'?[col]:[]);
  }
  // Source-owned team rows without a FK must not escape the review just because
  // the ordinary database cascade does not know about them.
  for(const [table,definition] of tables){
    if(table==='auth.users'||table.startsWith('private.scoped_deletion_'))continue;
    for(const [column,ids,kind] of [['team_id',scope.teamIds,'team'],['organization_id',scope.organizationIds,'organization']]){
      if(!ids.length||!definition.columns.has(column)||fks.some(k=>k.child===table&&k.columns.includes(column)))continue;
      for(const id of ids)for(const row of await select(table,[{[column]:id}])){
        if(deletable.has(table))add(table,row,'delete',{kind,id});else pending.push({table,row,reason:'unreviewed_record'});
      }
    }
  }
  for(let next=0;next<queue.length;next++){
    const parent=queue[next];
    for(const fk of fks.filter(x=>x.parent===parent.table)){
      const predicate={};let match=true;
      fk.ref_columns.forEach((col,i)=>{if(parent.row[col]===null||parent.row[col]===undefined)match=false;else predicate[fk.columns[i]]=parent.key[col]??parent.row[col];});
      if(!match)continue;
      for(const row of await select(fk.child,[predicate])){
        let action='block',columns=fk.columns;
        const userRoot=['auth.users','public.profiles'].includes(parent.table);
        const edge=fk.child+'.'+columns.join(',');
        if(userRoot){if(userDeletes.has(edge))action='delete';else if(userNulls.has(edge))action='null';}
        else if(parent.table==='public.organizations'&&fk.child==='public.athletes')action='null';
        else if(parent.table==='public.organizations'&&fk.child==='public.teams')action=scope.teamIds.includes(row.id)?'delete':'block';
        else if(parent.table==='private.event_repeat_batches'&&fk.child==='public.team_events')action='null';
        else if(fk.delete_action==='n'&&deletable.has(fk.child))action='null';
        else if(deletable.has(fk.child))action='delete';
        if(action==='block')pending.push({table:fk.child,row,reason:parent.table==='public.organizations'&&fk.child==='public.teams'?'linked_teams_not_selected':'unreviewed_dependency',edge:fk.name});
        else add(fk.child,row,action,parent.origin,action==='null'?columns:[]);
      }
    }
    // These snapshot/capability records use application-level references.
    const loose=[];
    if(parent.table==='public.communication_messages')loose.push(['public.communication_message_audit','message_id',parent.row.id]);
    if(parent.table==='public.communication_threads')loose.push(['public.communication_message_audit','thread_id',parent.row.id]);
    if(parent.table==='public.teams')loose.push(['public.communication_message_audit','team_id',parent.row.id]);
    if(['public.team_memberships','public.organization_memberships'].includes(parent.table)){
      for(const table of ['private.wrestling_role_approvals','private.wrestling_role_review_log']){
        for(const row of await select(table,[{membership_id:parent.row.id,source:parent.table==='public.team_memberships'?'team':'organization'}]))add(table,row,'delete',parent.origin);
      }
    }
    for(const [table,col,value] of loose)for(const row of await select(table,[{[col]:value}]))add(table,row,'delete',parent.origin);
  }
  // Memberships currently carry the only athlete-login ownership link. Until a
  // portable ownership migration is released, do not strand a profile by closing
  // its last active team. Surviving memberships are observed and frozen as well.
  for(const entry of records.values()){
    if(entry.table!=='public.team_memberships'||entry.action!=='delete'||entry.row.role!=='athlete'||!entry.row.active||!entry.row.athlete_id)continue;
    const links=await select('public.team_memberships',[{user_id:entry.row.user_id,athlete_id:entry.row.athlete_id,role:'athlete',active:true}]);
    if(!links.some(row=>!records.has(tag('public.team_memberships',keyFor('public.team_memberships',row)))))throw new ScopeError('profile_continuity_review_required');
  }
  for(const problem of pending){
    const r=records.get(tag(problem.table,keyFor(problem.table,problem.row)));
    if(r?.action!=='delete')throw new ScopeError(problem.reason,{table:problem.table,constraint:problem.edge});
  }
  // UUID-shaped identity references without FKs are blockers, not inferred ownership.
  // Unknown copied JSON identities also require a reviewed disposition.
  const identityColumns=set(['user_id','actor','actor_id','actor_user_id','reviewer_id','subject_id','sender_id','sender_user_id','owner_id','created_by','updated_by','requested_by','approved_by','verified_by','recipient','recipient_user_id','user_a','user_b']);
  for(const [table,definition] of tables){
    if(table==='auth.users'||table.startsWith('private.scoped_deletion_')||!scope.personal)continue;
    for(const [col,meta] of definition.columns){
      if(!identityColumns.has(col)||!['uuid','text'].includes(meta.type)||fks.some(k=>k.child===table&&k.columns.includes(col)))continue;
      for(const row of await select(table,[{[col]:scope.actorId}])){
        const planned=records.get(tag(table,keyFor(table,row)));
        if(planned?.action!=='delete'&&!planned?.columns.includes(col))throw new ScopeError('unreviewed_identity_reference',{table,column:col});
      }
    }
    const jsonColumns=[...definition.columns.values()].filter(x=>['json','jsonb'].includes(x.type)).map(x=>x.name);
    if(jsonColumns.length){
      if(typeof reader.identityMentions!=='function')throw new ScopeError('missing_snapshot_reader');
      const rows=await reader.identityMentions(table,jsonColumns,scope.actorId,maxRows+1);
      if(rows.length>maxRows)throw new ScopeError('scope_too_large');
      observations.push({table,identityMention:{columns:jsonColumns,actorId:scope.actorId},rows:rows.map(row=>({key:keyFor(table,row),row}))});
      for(const row of rows)if(records.get(tag(table,keyFor(table,row)))?.action!=='delete')throw new ScopeError('unreviewed_identity_snapshot',{table});
    }
  }
  // This output remains a plan. Only the service's locked seal may authorize execution.
  return {version:policy.version,scope,records:[...records.values()].sort((a,b)=>tag(a.table,a.key).localeCompare(tag(b.table,b.key))),observations};
}
