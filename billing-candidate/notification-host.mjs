import {createBillingConnectionPool} from '../supabase/functions/wm-billing-readiness/billing-connection.mjs';
import {createBillingRuntime} from './billing-runtime.mjs';
const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
const reply=(status,error)=>Response.json({error},{status,headers});

// Separate server-notification host. It never exposes runtime.billing and cannot
// activate app purchases. Apple JWS authenticates notifications; a distinct
// Vault-backed capability authenticates the scheduler. No service-role DB login.
export function createNotificationHost({Pool,readSecret,fetchImpl=fetch,clock=Date.now,
 makePool=createBillingConnectionPool,makeRuntime=createBillingRuntime}){
 let pool;const runtimes=new Map();let windowStart=0,requests=0,inFlight=0;
 function allowNotification(){
  const now=clock();if(now-windowStart>=60000){windowStart=now;requests=0;}
  // Per-isolate burst limit, backed by the shared Render verifier's bounded
  // concurrency/worker timeouts. This is deliberately not a global rate claim.
  if(requests>=30)return false;requests++;return true;
 }
 async function runtime(environment){
  if(!pool)pool=makePool({Pool,connectionURL:readSecret('BILLING_DATABASE_URL')});
  if(!runtimes.has(environment)){
   let runtimeDB;
   const ready=async()=>runtimeDB&&(await runtimeDB.query('select wm_billing.notification_deployment_ready() as ready')).rows[0]?.ready===true;
   const started=makeRuntime({pool,publishableKey:readSecret('SUPABASE_ANON_KEY'),readSecret,environment,fetchImpl,
    remoteApple:{url:readSecret('APPLE_VERIFIER_URL'),secret:readSecret('APPLE_VERIFIER_SHARED_SECRET')},
    verifyDeployment:async db=>{runtimeDB=db;return await ready();},
    allowNotification:async()=>{if(!allowNotification())return false;if(!await ready())throw Error('Deployment unavailable');return true;},
    authorizeWorker:async request=>{
     const token=request.headers.get('authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
     if(!token)return false;
     const connection=await pool.connect();
     try{return (await connection.query('select wm_billing.authorize_notification_worker($1) and wm_billing.notification_deployment_ready() as allowed',[token])).rows[0]?.allowed===true;}
     finally{connection.release();}
    }});
   runtimes.set(environment,started);started.catch(()=>runtimes.delete(environment));
  }
  return runtimes.get(environment);
 }
 return async request=>{
  const url=new URL(request.url);
  // Hosted routing removes /functions/v1; local Fetch tests may retain it.
  const route=url.pathname.match(/^(?:\/functions\/v1)?\/wrestling-manager-apple-notifications\/(production|sandbox)(\/reconcile)?$/);
  if(!route||url.search)return reply(404,'unavailable');
  if(request.headers.has('origin'))return reply(403,'server_requests_only');
  if(request.method!=='POST')return reply(405,'post_required');
  const isWorker=!!route[2];
  if(isWorker&&!/^Bearer [a-f0-9]{64}$/.test(request.headers.get('authorization')??''))return reply(403,'not_authorized');
  if(inFlight>=2)return reply(429,'retry_later');
  inFlight++;
  try{
   const current=await runtime(route[1]==='production'?'Production':'Sandbox');
   return await (isWorker?current.reconcile(request):current.notification(request));
  }catch{return reply(503,'notifications_unavailable');}
  finally{inFlight--;}
 };
}
