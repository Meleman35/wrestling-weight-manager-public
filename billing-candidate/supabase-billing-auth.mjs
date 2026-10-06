// Server-only. Contexts can be minted only after Supabase verifies this exact JWT.
// Never construct an authContext from a request-body user or decoded JWT alone.
import {Buffer} from 'node:buffer';
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
export class SupabaseBillingAuth {
 #contexts=new WeakMap();
 constructor({projectURL,publishableKey,pool,fetchImpl=fetch,clock=Date.now}){
  const url=new URL(projectURL);
  if(url.protocol!=='https:'||url.username||url.password||url.pathname!=='/'||url.search||url.hash||!url.hostname.endsWith('.supabase.co'))throw Error('invalid_auth_configuration');
  this.projectURL=url.origin;this.publishableKey=publishableKey;this.pool=pool;this.fetch=fetchImpl;this.clock=clock;
 }
 async authenticate(authorization){
  if(typeof authorization!=='string'||!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization)||authorization.length>16384)throw Error('unauthorized');
  const token=authorization.slice(7);
  let claims;try{claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));}catch{throw Error('unauthorized');}
  // Structural checks are not verification. Supabase /auth/v1/user below must
  // accept the same token and return the same account before minting a context.
  if(!uuid(claims.sub)||!uuid(claims.session_id)||claims.role!=='authenticated'||claims.aud!=='authenticated'||
     claims.iss!==this.projectURL+'/auth/v1'||!Number.isSafeInteger(claims.exp)||claims.exp*1000<=this.clock())throw Error('unauthorized');
  const response=await this.fetch(this.projectURL+'/auth/v1/user',{method:'GET',redirect:'error',
   headers:{Authorization:authorization,apikey:this.publishableKey},signal:AbortSignal.timeout(8000)});
  if(!response.ok)throw Error('unauthorized');
  const user=await response.json();if(user.id!==claims.sub||claims.exp*1000<=this.clock())throw Error('unauthorized');
  const context=Object.freeze({});this.#contexts.set(context,{userID:claims.sub,sessionID:claims.session_id,expiresAt:claims.exp*1000});return context;
 }
 claims(context){const claims=this.#contexts.get(context);if(!claims||claims.expiresAt<=this.clock())throw Error('unauthorized');return claims;}
 async currentActor(context,client){
  const claims=this.claims(context);
  const query=async connection=>{
   await connection.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:claims.userID,session_id:claims.sessionID,role:'authenticated'})]);
   const result=await connection.query('select wm_billing.current_actor($1,$2,$3) as actor',[claims.userID,claims.sessionID,claims.expiresAt]);
   this.claims(context);return result.rows[0]?.actor??null;
  };
  if(client)return query(client);
  const connection=await this.pool.connect();try{await connection.query('BEGIN');const actor=await query(connection);await connection.query('COMMIT');return actor;}catch(e){await connection.query('ROLLBACK').catch(()=>{});throw e;}finally{connection.release();}
 }
}
