import {billingConnectionOptions,createBillingConnectionPool} from './billing-connection.mjs';
const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
export function createBillingDatabaseReadiness({readSecret,Pool,now=Date.now}) {
 let cached,expires=0;
 async function check(){
  const result={databaseURLConfigured:false,databaseConnected:false,restrictedDatabaseIdentity:false,billingEnabled:false};
  let pool,connection;
  try {
   const connectionURL=readSecret('BILLING_DATABASE_URL');
   billingConnectionOptions(connectionURL);result.databaseURLConfigured=true;
   pool=createBillingConnectionPool({Pool,connectionURL});
   connection=await pool.connect();
   const row=(await connection.query("select current_database()='postgres' as expected_database,current_user='wm_billing_runtime' as expected_role")).rows[0];
   result.databaseConnected=row?.expected_database===true;
   result.restrictedDatabaseIdentity=result.databaseConnected&&row?.expected_role===true;
  }catch{/* Never expose connection URLs, passwords, errors or business rows. */}
  finally {connection?.release();await pool?.end().catch(()=>{});}
  return result;
 }
 return async request=>{
  if(request.method!=='POST')return new Response(null,{status:405,headers:{...headers,Allow:'POST'}});
  if(request.headers.has('origin'))return Response.json({error:'not_authorized'},{status:403,headers});
  if(!cached||now()>=expires){expires=now()+30000;cached=check();}
  return Response.json(await cached,{headers});
 };
}
