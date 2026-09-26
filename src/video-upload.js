/* Immutable, resumable private uploads. Device data survives every failure. */
window.WMVideoUpload=(()=>{
 'use strict';
 const ORIGIN='https://vfocpoyexnjsjpxhhyqr.storage.supabase.co',ENDPOINT=ORIGIN+'/storage/v1/upload/resumable',CHUNK=6*1024*1024;
 let busy=false;
 const same=row=>session?.user?.id===row.userId&&activeTeam?.id===row.teamId&&!managedLogin&&!document.hidden&&!window.WMVideoPilot?.active();
 function safeURL(value){const u=new URL(value,ENDPOINT);if(u.origin!==ORIGIN||!u.pathname.startsWith('/storage/v1/upload/resumable/')||u.username||u.password)throw Error('Upload server address was not trusted.');return u.href;}
 async function tus(blob,path,row,kind,save){
  let url=row.upload?.[kind];if(url)url=safeURL(url);
  const send=async(method,target,headers={},body)=>{if(!same(row))throw Error('Upload paused. Return to this account and team.');const r=await fetch(target,{method,headers:{'Tus-Resumable':'1.0.0',Authorization:'Bearer '+session.access_token,apikey:SUPABASE_KEY,...headers},body,redirect:'error',signal:AbortSignal.timeout(60000)});if(!same(row))throw Error('Upload paused after account or screen change.');return r;};
  let offset=0;
  if(url){const r=await send('HEAD',url);if([404,410].includes(r.status)){url=null;delete row.upload[kind];await save(row);}else{if(!r.ok)throw Error('Upload paused. Your device copy is safe.');const raw=r.headers.get('Upload-Offset');offset=Number(raw);if(raw===null||!Number.isSafeInteger(offset)||offset<0||offset>blob.size)throw Error('Upload offset is invalid. Keep the device copy.');}}
  if(!url){const metadata={bucketName:'match-video-pilot',objectName:path,contentType:blob.type.split(';')[0],cacheControl:'0'};const r=await send('POST',ENDPOINT,{'Upload-Length':String(blob.size),'Upload-Metadata':Object.entries(metadata).map(([k,v])=>k+' '+btoa(v)).join(',')});if(r.status!==201)throw Error('Upload could not start. Your device copy is safe.');const location=r.headers.get('Location');if(!location)throw Error('Missing upload address.');url=safeURL(location);row.upload||={};row.upload[kind]=url;await save(row);}
  while(offset<blob.size){const part=blob.slice(offset,offset+CHUNK),r=await send('PATCH',url,{'Content-Type':'application/offset+octet-stream','Upload-Offset':String(offset)},part);if(r.status!==204)throw Error('Upload interrupted. It will resume when you have service.');const next=Number(r.headers.get('Upload-Offset'));if(next!==offset+part.size)throw Error('Upload confirmation did not match. Keep the device copy.');offset=next;row.upload.progress=Math.round(offset/blob.size*100);await save(row);}
 }
 function timeline(row){return new Blob([JSON.stringify({schema:row.schema||1,id:row.id,matchId:row.matchId,athleteIds:row.athleteIds,label:row.label,createdAt:row.createdAt,events:row.events})],{type:'application/json'});}
 async function run(store,row){if(busy||!same(row)||!navigator.onLine||!row.boutId||!['ready','partial'].includes(row.status)||row.upload?.status==='ready')return;busy=true;
  const save=r=>store.put(r);
  try{row.upload||={};row.upload.status='uploading';row.upload.error='';await save(row);const file=await store.file(row),score=timeline(row);const plan=await WMMatchVideo.rpc('prepare',{id:row.id,match_id:row.matchId,bytes:file.size,timeline_bytes:score.size,mime:row.mime.split(';')[0],duration_ms:Math.round(row.durationMs),partial:row.status==='partial'});
   if(plan.status!=='ready'){
    // Lost final responses are reconciled against server-owned object metadata first.
    let complete=false;try{await WMMatchVideo.rpc('complete',{id:row.id});complete=true;}catch{}
    if(!complete){if(!plan.video_uploaded)await tus(file,plan.video_path,row,'video',save);if(!plan.timeline_uploaded)await tus(score,plan.timeline_path,row,'timeline',save);await WMMatchVideo.rpc('complete',{id:row.id});}
   }
   await WMMatchVideo.verifyCloud(row.id);if(!same(row))throw Error('Return to the recording account to check upload.');row.upload={status:'ready',verifiedAt:new Date().toISOString()};await save(row);
  }catch(e){row.upload||={};row.upload.status='waiting';row.upload.error=e.message;await save(row);}finally{busy=false;}}
 async function queue(store,scope){if(busy||!navigator.onLine||document.hidden)return;for(const row of await store.list(scope)){if(!same(row))break;if(row.boutId&&row.upload?.status!=='ready'&&['ready','partial'].includes(row.status)){await run(store,row);break;}}}
 return{queue,run,busy:()=>busy,tus,timeline};
})();
