import {SupabaseBillingAuth} from './supabase-billing-auth.mjs';
import {PostgresBillingRepository} from './postgres-repository.mjs';
import {launchProductIDs} from './launch-products.mjs';
const enrolled=async(client,team)=>(await client.query('select wm_billing.sandbox_team_enrolled($1) as allowed',[team])).rows[0]?.allowed===true;
const deny=()=>{throw Error('unauthorized');};

// Real Supabase authentication is unchanged. Enrollment is rechecked with each
// actor read, including after Apple network waits and inside write transactions.
export class SandboxBillingAuth extends SupabaseBillingAuth {
 async currentActor(context,client){
  if(client){const actor=await super.currentActor(context,client);if(!actor||!await enrolled(client,null))deny();return actor;}
  const connection=await this.pool.connect();
  try{await connection.query('BEGIN');const actor=await this.currentActor(context,connection);await connection.query('COMMIT');return actor;}
  catch(error){await connection.query('ROLLBACK').catch(()=>{});throw error;}finally{connection.release();}
 }
}
export class SandboxBillingRepository extends PostgresBillingRepository {
 port(client){
  const base=super.port(client);
  const guard=async team=>{if(!team||!await enrolled(client,team))deny();};
  const binding=async value=>{if(value){if(value.familyOwnerID!=null)deny();await guard(value.teamID);}return value;};
  return {...base,
   canPurchaseTeam:async(user,team)=>await enrolled(client,team)&&await base.canPurchaseTeam(user,team),
   canPurchaseFamily:async()=>false,
   familyCoverageOptions:async()=>{throw Error('family_coverage_forbidden');},
   replaceFamilyCoverage:async()=>{throw Error('family_coverage_forbidden');},
   resolveAccess:async(user,team,athlete,event)=>{await guard(team);const value=await base.resolveAccess(user,team,athlete,event);return value?{...value,familyCoverage:[]}:value;},
   saveIntent:async value=>{await guard(value.teamID);if(value.familyOwnerID!=null||!launchProductIDs.includes(value.productID))deny();return base.saveIntent(value);},
   getIntent:async token=>binding(await base.getIntent(token)),
   getSubscription:async(environment,original)=>{if(environment!=='Sandbox')deny();return binding(await base.getSubscription(environment,original));},
   saveSubscription:async value=>{await binding(value);if(value.environment!=='Sandbox'||!launchProductIDs.includes(value.productID))deny();return base.saveSubscription(value);}
  };
 }
}
