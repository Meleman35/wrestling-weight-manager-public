import {createBillingConnectionPool} from '../supabase/functions/wm-billing-readiness/billing-connection.mjs';
import {privateBillingPool,billingDatabase} from './billing-runtime.mjs';
import {SandboxBillingAuth,SandboxBillingRepository} from './sandbox-billing-ports.mjs';
import {PurchaseIntentService} from './purchase-intent.mjs';
import {PurchaseDeliveryService} from './purchase-delivery.mjs';
import {SubscriptionAccessService} from './subscription-access.mjs';
import {FamilyCoverageService} from './family-coverage.mjs';
import {createBillingHandler} from './billing-handler.mjs';
import {readApplePublicConfiguration} from './apple-server-config.mjs';
import {createRemoteAppleEvidenceAdapter} from './remote-apple-evidence.mjs';
const origin='https://theteammanager.app';
const reply=(status,error,o)=>Response.json({error},{status,headers:{'Cache-Control':'no-store',...(o?{'Access-Control-Allow-Origin':o,'Vary':'Origin'}:{})}});

// This acceptance host has no production mode. Every command requires current
// server enrollment; Apple evidence must verify specifically in Sandbox.
export function createSandboxBillingHost({Pool,readSecret,fetchImpl=fetch,makePool=createBillingConnectionPool,
 makeAuth=options=>new SandboxBillingAuth(options),makeRepository=options=>new SandboxBillingRepository(options),
 makeApple=createRemoteAppleEvidenceAdapter,makeHandler=createBillingHandler}){
 let pool,db,handler,inFlight=0;
 function initialize(){
  pool??=privateBillingPool(makePool({Pool,connectionURL:readSecret('BILLING_DATABASE_URL')}));
  db??=billingDatabase(pool);
  if(!handler){
   const config=readApplePublicConfiguration('Sandbox');
   const url=readSecret('APPLE_VERIFIER_URL');if(url!=='https://wm-apple-verifier.onrender.com/apple')throw Error('Invalid verifier');
   const apple=makeApple({url,secret:readSecret('APPLE_VERIFIER_SHARED_SECRET'),config,fetchImpl});
   const auth=makeAuth({projectURL:'https://vfocpoyexnjsjpxhhyqr.supabase.co',publishableKey:readSecret('SUPABASE_ANON_KEY'),pool,fetchImpl});
   const repository=makeRepository({pool,auth});
   handler=makeHandler({enabled:true,purchaseEnvironment:'Sandbox',auth,intents:new PurchaseIntentService({auth,repository}),
    delivery:new PurchaseDeliveryService({auth,apple,repository,config}),access:new SubscriptionAccessService({auth,repository,environment:'Sandbox'}),coverage:new FamilyCoverageService({auth,repository})});
  }
 }
 return async request=>{
  const url=new URL(request.url),o=request.headers.get('origin');
  if(!/^(?:\/functions\/v1)?\/wrestling-manager-billing\/?$/.test(url.pathname)||url.search)return reply(404,'unavailable');
  if(o&&o!==origin)return reply(403,'origin_forbidden');
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers:o?{'Access-Control-Allow-Origin':o,'Vary':'Origin','Access-Control-Allow-Methods':'POST','Access-Control-Allow-Headers':'Authorization, Content-Type, apikey','Access-Control-Max-Age':'600'}:{}});
  if(request.method!=='POST')return reply(405,'method_not_allowed',o);
  if(!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(request.headers.get('authorization')??''))return reply(401,'sign_in_required',o);
  if(inFlight>=2)return reply(429,'retry_later',o);inFlight++;
  try{
   initialize();
   if((await db.query('select wm_billing.notification_deployment_ready() as ready')).rows[0]?.ready!==true)return reply(503,'billing_unavailable',o);
   return await handler(request);
  }catch{return reply(503,'billing_unavailable',o);}finally{inFlight--;}
 };
}
