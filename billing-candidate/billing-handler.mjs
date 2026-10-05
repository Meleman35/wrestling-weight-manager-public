// Fetch-compatible server route candidate. Disabled unless explicitly configured.
// No live deployment, private credentials or feature access grants are installed.
import {launchProductIDs} from './launch-products.mjs';
const origins=new Set(['https://theteammanager.app']);
const response=(status,body,origin)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store',...(origin?{'Access-Control-Allow-Origin':origin,'Vary':'Origin'}:{})}});
async function boundedJSON(request){
 if(!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type')||''))throw Error('invalid_content_type');
 const length=request.headers.get('content-length');if(length&&(!/^\d+$/.test(length)||Number(length)>65536))throw Error('body_too_large');
 if(!request.body)throw Error('invalid_request');const reader=request.body.getReader();let lengthRead=0;const chunks=[];
 try{while(true){const {value,done}=await reader.read();if(done)break;lengthRead+=value.length;if(lengthRead>65536){await reader.cancel();throw Error('body_too_large');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const bytes=new Uint8Array(lengthRead);let offset=0;for(const value of chunks){bytes.set(value,offset);offset+=value.length;}
 try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{throw Error('invalid_request');}
}
export function createBillingHandler({enabled=false,auth,intents,delivery,access,coverage}){
 return async request=>{
  const origin=request.headers.get('origin');if(origin&&!origins.has(origin))return response(403,{error:'origin_forbidden'});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers:origin?{'Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Methods':'POST','Access-Control-Allow-Headers':'Authorization, Content-Type, apikey','Access-Control-Max-Age':'600'}:{}});
  if(!enabled)return response(503,{error:'billing_unavailable'},origin);
  if(request.method!=='POST')return response(405,{error:'method_not_allowed'},origin);
  try{
   const body=await boundedJSON(request);
   if(!body||Object.keys(body).some(k=>!['action','data'].includes(k))||!['capabilities','prepare','deliver','abandon','access','coverage','coverage-options'].includes(body.action)||!body.data||Array.isArray(body.data)||typeof body.data!=='object')throw Error('invalid_request');
   const context=await auth.authenticate(request.headers.get('authorization'));
   // This gate is independent of which buttons a client displays. Preserve
   // delivery/restore reconciliation, but never create a later-update purchase.
   if(body.action==='prepare'&&!launchProductIDs.includes(body.data.productID))throw Error('unknown_product');
   if(body.action==='capabilities'){
    if(Object.keys(body.data).length)throw Error('invalid_request');
    const actor=await auth.currentActor(context);
    if(!actor||actor.liveSession!==true||actor.confirmed!==true||actor.deleted===true||actor.banned===true||actor.managedTeamLogin===true||actor.deletionFrozen===true)throw Error('unauthorized');
    return response(200,{ready:true,productIDs:[...launchProductIDs].sort()},origin);
   }
   const result=body.action==='coverage-options'?await coverage.options(context,body.data):body.action==='coverage'?await coverage.select(context,body.data):body.action==='access'?await access.read(context,body.data):body.action==='prepare'?await intents.prepare(context,body.data):body.action==='abandon'?await intents.abandon(context,body.data):await delivery.deliver(context,body.data);
   return response(200,result,origin);
  }catch(e){
   const code=e.code||e.message;
   if(e.message==='family_coverage_forbidden')return response(403,{error:'family_coverage_not_authorized'},origin);
   if(e.message==='invalid_coverage')return response(400,{error:'invalid_request'},origin);
   if(code==='unauthorized'||code==='session_changed')return response(401,{error:'sign_in_required'},origin);
   if(code==='body_too_large')return response(413,{error:code},origin);
   if(code==='access_forbidden')return response(403,{error:'access_not_authorized'},origin);
   if(['invalid_request','invalid_target','invalid_content_type','unknown_product'].includes(code))return response(400,{error:'invalid_request'},origin);
   if(['team_purchase_forbidden','family_purchase_forbidden','intent_not_owned','different_owner'].includes(code))return response(403,{error:'purchase_not_authorized'},origin);
   if(['team_already_bound','purchase_already_bound'].includes(code))return response(409,{error:code},origin);
   // No raw database, Apple, JWT or signed receipt details reach the client.
   return response(503,{error:'purchase_delivery_unconfirmed'},origin);
  }
 };
}
