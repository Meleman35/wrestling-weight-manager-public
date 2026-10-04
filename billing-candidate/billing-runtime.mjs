import {SupabaseBillingAuth} from './supabase-billing-auth.mjs';
import {PostgresBillingRepository} from './postgres-repository.mjs';
import {PurchaseIntentService} from './purchase-intent.mjs';
import {PurchaseDeliveryService} from './purchase-delivery.mjs';
import {SubscriptionAccessService} from './subscription-access.mjs';
import {FamilyCoverageService} from './family-coverage.mjs';
import {createBillingHandler} from './billing-handler.mjs';
import {createAppleEvidenceAdapter} from './apple-evidence.mjs';
import {readAppleServerConfiguration} from './apple-server-config.mjs';
import {appleTrustRoots} from './apple-trust-roots.mjs';
import {createAppleNotificationHandler} from './apple-notification-handler.mjs';
import {createAppleNotificationInbox} from './apple-notification-inbox.mjs';
import {createAppleNotificationPostgres} from './apple-notification-postgres.mjs';
import {createAppleNotificationWorker} from './apple-notification-worker.mjs';

// This pool must authenticate as a dedicated server identity. No fallback to
// postgres/service_role: database permissions are checked on every checkout.
export function privateBillingPool(pool){
 return {async connect(){
  const connection=await pool.connect();
  try {
   const role=(await connection.query("select current_user as role,r.rolsuper,r.rolbypassrls,session_user as login,l.rolsuper as login_super,l.rolbypassrls as login_bypass,l.rolcanlogin as can_login from pg_roles r join pg_roles l on l.rolname=session_user where r.rolname=current_user")).rows[0];
   if(!role||role.role!=='wm_billing_runtime'||role.rolsuper||role.rolbypassrls||role.login_super!==false||role.login_bypass!==false||role.can_login!==true||['postgres','service_role','anon','authenticated'].includes(role.login))throw Error('Private billing identity required');
   return connection;
  }catch(error){connection.release(true);throw error;}
 }};
}
export function billingDatabase(pool){
 const transaction=async callback=>{
  const connection=await pool.connect();
  try {await connection.query('BEGIN');await connection.query("set local statement_timeout='10s'");await connection.query("set local lock_timeout='5s'");
   const result=await callback(connection);await connection.query('COMMIT');return result;
  }catch(error){await connection.query('ROLLBACK').catch(()=>{});throw error;}finally{connection.release();}
 };
 return {transaction,query:(sql,args)=>transaction(connection=>connection.query(sql,args))};
}
export async function createBillingRuntime({pool,publishableKey,readSecret,environment,
 verifyDeployment,allowNotification,authorizeWorker,fetchImpl=fetch,appleFactory=createAppleEvidenceAdapter}){
 if(!publishableKey||![verifyDeployment,allowNotification,authorizeWorker].every(f=>typeof f==='function'))throw Error('Billing runtime configuration required');
 const privatePool=privateBillingPool(pool),db=billingDatabase(privatePool);
 // Deployment verification must include the approved deletion catalog and
 // retention integration. Configuration alone cannot make draft schemas live.
 if(await verifyDeployment(db)!==true)throw Error('Billing deployment not approved');
 const config=readAppleServerConfiguration({readSecret,rootCertificates:appleTrustRoots(),environment});
 const apple=await appleFactory(config);
 const auth=new SupabaseBillingAuth({projectURL:'https://vfocpoyexnjsjpxhhyqr.supabase.co',publishableKey,pool:privatePool,fetchImpl});
 const repository=new PostgresBillingRepository({pool:privatePool,auth});
 const billing=createBillingHandler({enabled:true,auth,
  intents:new PurchaseIntentService({auth,repository}),delivery:new PurchaseDeliveryService({auth,apple,repository,config}),
  access:new SubscriptionAccessService({auth,repository,environment}),coverage:new FamilyCoverageService({auth,repository})});
 const notification=createAppleNotificationHandler({enabled:true,apple,
  persistVerified:createAppleNotificationInbox({db,environment}),allowRequest:allowNotification});
 const worker=createAppleNotificationWorker({apple,...createAppleNotificationPostgres({db,environment}),config});
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
 return Object.freeze({billing,notification,async reconcile(request){
  let authorized=false;
  if(request.method==='POST'&&!request.headers.has('origin')){
   try {authorized=await authorizeWorker(request)===true;}catch{authorized=false;}
  }
  if(!authorized)return new Response(JSON.stringify({error:'not_authorized'}),{status:403,headers});
  // One bounded leased unit per invocation; a scheduler can drain the backlog.
  try {return new Response(JSON.stringify(await worker()),{status:200,headers});}
  catch{return new Response(JSON.stringify({error:'reconciliation_unconfirmed'}),{status:503,headers});}
 }});
}
