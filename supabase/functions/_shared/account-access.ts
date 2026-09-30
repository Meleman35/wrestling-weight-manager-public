// The gateway verifies the caller token; the DB checks fresh session/deletion state.
// Caller credentials only. A service key or decoded client claims are never substituted.
export async function accountAccessAllowed(deps:{fetch:typeof fetch},url:string,key:string,authorization:string):Promise<boolean>{
 try{
  const response=await deps.fetch(url+'/rest/v1/rpc/account_deletion_check_access',{
   method:'POST',headers:{apikey:key,Authorization:authorization,'Content-Type':'application/json'},
   body:'{}',signal:AbortSignal.timeout(10000)
  });
  return response.ok && await response.json()===true;
 }catch{return false;}
}
