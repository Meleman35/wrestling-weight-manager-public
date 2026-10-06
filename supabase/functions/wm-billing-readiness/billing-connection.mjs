// Private connection settings are pinned to the owner-confirmed session pooler.
// Do not accept a request-selected host, postgres login, query options or TLS mode.
const host='aws-0-us-west-2.pooler.supabase.com';
const login='wm_billing_service';
const pooledLogin=login+'.vfocpoyexnjsjpxhhyqr';
const unavailable=()=>new Error('Private billing connection unavailable');
export function billingConnectionOptions(value) {
 try {
  if(typeof value!=='string'||value.length>2048)throw unavailable();
  const url=new URL(value);
  if(url.protocol!=='postgresql:'||url.hostname!==host||url.port!=='5432'||url.pathname!=='/postgres'||
   url.username!==pooledLogin||!/^[a-f0-9]{64}$/.test(url.password)||url.search||url.hash)throw unavailable();
  return {host,port:5432,database:'postgres',user:pooledLogin,password:url.password,
   ssl:{rejectUnauthorized:true},max:1,idleTimeoutMillis:1000,connectionTimeoutMillis:5000,
   statement_timeout:5000,query_timeout:7000,application_name:'wm-billing-server'};
 }catch{throw unavailable();}
}

// Session pooling pins the backend to this connection. Check the actual login
// before selecting its one permitted runtime role; check both again afterward.
export function createBillingConnectionPool({Pool,connectionURL}) {
 const pool=new Pool(billingConnectionOptions(connectionURL));
 // node-postgres emits idle connection errors. Never log provider diagnostics
 // here because they may contain private connection details.
 pool.on('error',()=>{});
 return {async connect(){
  let connection;
  try {
   connection=await pool.connect();
   const row=(await connection.query(`select session_user as login,r.rolsuper,r.rolbypassrls,r.rolcreaterole,r.rolcreatedb,
    r.rolreplication,r.rolcanlogin,pg_has_role(session_user,'wm_billing_runtime','MEMBER') as runtime_member
    from pg_roles r where r.rolname=session_user`)).rows[0];
   if(row?.login!==login||row.rolsuper!==false||row.rolbypassrls!==false||row.rolcreaterole!==false||
    row.rolcreatedb!==false||row.rolreplication!==false||row.rolcanlogin!==true||row.runtime_member!==true)throw unavailable();
   await connection.query('set role wm_billing_runtime');
   const selected=(await connection.query(`select current_user as role,r.rolsuper,r.rolbypassrls,r.rolcreaterole,r.rolcreatedb,
    r.rolreplication,r.rolcanlogin from pg_roles r where r.rolname=current_user`)).rows[0];
   if(selected?.role!=='wm_billing_runtime'||selected.rolsuper!==false||selected.rolbypassrls!==false||
    selected.rolcreaterole!==false||selected.rolcreatedb!==false||selected.rolreplication!==false||selected.rolcanlogin!==false)throw unavailable();
   return connection;
  }catch {connection?.release(true);throw unavailable();}
 },end:()=>pool.end()};
}
