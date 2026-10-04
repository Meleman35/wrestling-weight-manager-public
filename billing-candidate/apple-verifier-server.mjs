import {createServer} from 'node:http';
import {timingSafeEqual,createPrivateKey} from 'node:crypto';
import {Buffer} from 'node:buffer';
import {Worker} from 'node:worker_threads';
import {pathToFileURL} from 'node:url';
import {appleTrustRoots} from './apple-trust-roots.mjs';
import {readAppleServerConfiguration} from './apple-server-config.mjs';

const maxBody=196608,uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(x);
const jws=x=>typeof x==='string'&&x.length<=131072&&/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(x);
function validCall(body){
 if(!body||Array.isArray(body)||Object.keys(body).sort().join(',')!=='action,environment,input,requestID'||
  !uuid(body.requestID)||!['Sandbox','Production'].includes(body.environment))return false;
 if(['resolve','notificationTransaction'].includes(body.action))return jws(body.input)&&(body.action!=='resolve'||body.input.length<=65536);
 if(body.action!=='refresh'||!body.input||Array.isArray(body.input)||Object.keys(body.input).sort().join(',')!=='appAccountToken,bundleID,environment,originalTransactionID')return false;
 return body.input.environment===body.environment&&body.input.bundleID==='com.damonmele.wrestlingmanager'&&
  typeof body.input.originalTransactionID==='string'&&/^[0-9]{1,40}$/.test(body.input.originalTransactionID)&&uuid(body.input.appAccountToken);
}
export function runAppleVerification(call,{timeoutMs=25000}={}){
 return new Promise((resolve,reject)=>{
  const worker=new Worker(new URL('./apple-verifier-worker.mjs',import.meta.url),{workerData:call,resourceLimits:{maxOldGenerationSizeMb:96}});
  let settled=false;
  const finish=(error,result)=>{
   if(settled)return;settled=true;clearTimeout(timer);
   void worker.terminate().then(()=>error?reject(Error('Verification unavailable')):resolve(result),()=>reject(Error('Verification unavailable')));
  };
  const timer=setTimeout(()=>finish(true),timeoutMs);
  worker.once('message',message=>finish(message?.ok!==true,message?.result));
  worker.once('error',()=>finish(true));worker.once('exit',()=>{if(!settled)finish(true);});
 });
}
export function createAppleVerifierServer({secret,verify=runAppleVerification,maxConcurrent=2}){
 if(!/^[a-f0-9]{64}$/i.test(secret)||typeof verify!=='function'||!Number.isInteger(maxConcurrent)||maxConcurrent<1||maxConcurrent>8)throw Error('Verifier server configuration required');
 const expected=Buffer.from('Bearer '+secret);let inFlight=0;
 const server=createServer(async(req,res)=>{
  const reply=(status,body)=>{if(res.destroyed||res.writableEnded)return;res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(body));};
  if(req.method==='GET'&&req.url==='/health')return reply(200,{ready:true});
  if(req.url!=='/apple'||req.method!=='POST')return reply(404,{error:'unavailable'});
  const supplied=Buffer.from(typeof req.headers.authorization==='string'?req.headers.authorization:'');
  if(req.headers.origin!==undefined||supplied.length!==expected.length||!timingSafeEqual(supplied,expected))return reply(403,{error:'not_authorized'});
  if(inFlight>=maxConcurrent)return reply(429,{error:'retry_later'});
  if(req.headers['content-type']?.split(';')[0].trim().toLowerCase()!=='application/json'||
   (req.headers['content-length']!==undefined&&(!/^\d+$/.test(req.headers['content-length'])||Number(req.headers['content-length'])>maxBody)))return reply(400,{error:'invalid_request'});
  inFlight++;
  try {
   const chunks=[];let size=0;
   for await(const chunk of req){size+=chunk.length;if(size>maxBody){reply(400,{error:'invalid_request'});return;}chunks.push(chunk);}
   let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));}catch{return reply(400,{error:'invalid_request'});}
   if(!validCall(body))return reply(400,{error:'invalid_request'});
   try {
    const result=await verify(body);
    if(!result||typeof result!=='object'||Buffer.byteLength(JSON.stringify(result))>32768)throw Error('Invalid result');
    reply(200,{requestID:body.requestID,environment:body.environment,result});
   }catch{reply(503,{error:'verification_unavailable'});}
  }catch{reply(400,{error:'invalid_request'});}finally{inFlight--;}
 });
 server.requestTimeout=15000;server.headersTimeout=10000;server.keepAliveTimeout=5000;server.maxRequestsPerSocket=50;
 return server;
}
export function validateAppleVerifierStartup(readSecret){
 const roots=appleTrustRoots();
 for(const environment of ['Sandbox','Production']){
  const config=readAppleServerConfiguration({readSecret,rootCertificates:roots,environment});
  const key=createPrivateKey(config.signingKey);
  if(key.asymmetricKeyType!=='ec'||key.asymmetricKeyDetails?.namedCurve!=='prime256v1')throw Error('Apple signing key configuration required');
 }
}
// Server deployment is a separate, owner-approved hosting step. No auto-start
// when this module is imported by a test or the Supabase billing service.
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try {
  validateAppleVerifierStartup(name=>process.env[name]);
  const port=Number(process.env.PORT??10000);if(!Number.isInteger(port)||port<1||port>65535)throw Error('Invalid port');
  const server=createAppleVerifierServer({secret:process.env.APPLE_VERIFIER_SHARED_SECRET});
  server.listen(port,'0.0.0.0',()=>console.log('Apple verification service listening'));
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{server.close();setTimeout(()=>process.exit(0),30000).unref();});
 }catch{console.error('Apple verification service is not configured');process.exitCode=1;}
}
