// Real PostgreSQL adapter candidate. Pool credentials stay on the server.
// Production deployment remains blocked on deletion/retention and route wiring.
export class PostgresBillingRepository {
 constructor({pool,auth}){this.pool=pool;this.auth=auth;}
 async withTransaction(lockKeys,callback){
  const client=await this.pool.connect();let committed=false;
  try{
   await client.query('BEGIN');
   await client.query("set local lock_timeout='5s'");await client.query("set local statement_timeout='10s'");
   // Sorting imposes a single lock order; collisions only serialize extra work.
   for(const key of [...new Set(lockKeys)].sort())await client.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[key]);
   const tx=this.port(client),result=await callback(tx);
   await client.query('COMMIT');committed=true;return result;
  }catch(e){if(!committed)await client.query('ROLLBACK').catch(()=>{});throw e;}finally{client.release();}
 }
 intentTransaction({userID,scope},callback){return this.withTransaction(['purchaser:'+userID+':'+scope],callback);}
 transaction({environment,originalTransactionID,token},callback){return this.withTransaction(['original:'+environment+':'+originalTransactionID,'token:'+token.toLowerCase()],callback);}
 port(client){
  const one=async(sql,args)=>(await client.query(sql,args)).rows[0];
  return {
   currentActor:ctx=>this.auth.currentActor(ctx,client),
   canPurchaseTeam:async(user,team)=>(await one('select wm_billing.can_purchase_team($1,$2) as allowed',[user,team]))?.allowed===true,
   canPurchaseFamily:async user=>(await one('select wm_billing.can_purchase_family($1) as allowed',[user]))?.allowed===true,
   getTeamPurchaseBinding:async user=>{const row=await one('select team_id from wm_billing.team_bindings where user_id=$1',[user]);return row?{teamID:row.team_id}:null;},
   saveIntent:async intent=>{
    const scope=intent.familyOwnerID?'family':'team';
    if(scope==='team'){
     const bound=await one('insert into wm_billing.team_bindings(user_id,team_id) values($1,$2) on conflict(user_id) do update set team_id=wm_billing.team_bindings.team_id where wm_billing.team_bindings.team_id=excluded.team_id returning team_id',[intent.userID,intent.teamID]);
     if(!bound)throw Error('team_already_bound');
    }
    await client.query('insert into wm_billing.intents(token,user_id,product_id,scope,team_id,family_owner_id,created_at,cancelled) values($1,$2,$3,$4,$5,$6,$7,$8)',[intent.token,intent.userID,intent.productID,scope,intent.teamID,intent.familyOwnerID??null,intent.createdAt,intent.cancelled]);
   },
   getSubscription:async(environment,original)=>{const row=await one('select snapshot from wm_billing.subscriptions where environment=$1 and original_id=$2 for update',[environment,original]);return row?.snapshot??null;},
   getIntent:async token=>{const row=await one('select * from wm_billing.intents where token=$1 for update',[token]);return row?{userID:row.user_id,teamID:row.team_id,...(row.family_owner_id?{familyOwnerID:row.family_owner_id}:{}),token:row.token,productID:row.product_id,authorized:true,cancelled:row.cancelled,boundOriginalTransactionID:row.bound_original_id}:null;},
   saveSubscription:async s=>{
    const row=await one('insert into wm_billing.subscriptions(environment,original_id,token,user_id,scope,team_id,family_owner_id,snapshot) values($1,$2,$3,$4,$5,$6,$7,$8) on conflict(environment,original_id) do update set snapshot=excluded.snapshot where wm_billing.subscriptions.token=excluded.token and wm_billing.subscriptions.user_id=excluded.user_id and wm_billing.subscriptions.team_id is not distinct from excluded.team_id and wm_billing.subscriptions.family_owner_id is not distinct from excluded.family_owner_id returning original_id',[s.environment,s.originalTransactionID,s.appAccountToken,s.userID,s.familyOwnerID?'family':'team',s.teamID,s.familyOwnerID??null,JSON.stringify(s)]);
    if(!row)throw Error('binding_mismatch');
   },
   bindIntent:async(token,original)=>{const row=await one('update wm_billing.intents set bound_original_id=$2 where token=$1 and (bound_original_id is null or bound_original_id=$2) returning token',[token,original]);if(!row)throw Error('intent_already_bound');},
   recordDelivery:async(environment,transaction,original)=>{const row=await one('insert into wm_billing.deliveries(environment,transaction_id,original_id) values($1,$2,$3) on conflict(environment,transaction_id) do update set last_seen=now() where wm_billing.deliveries.original_id=excluded.original_id returning transaction_id',[environment,transaction,original]);if(!row)throw Error('delivery_binding_conflict');}
  };
 }
}
