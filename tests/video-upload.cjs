const assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm'),{randomUUID}=require('crypto');
(async()=>{
 const state={userId:'u',teamId:'t',id:randomUUID(),matchId:randomUUID(),boutId:randomUUID(),status:'ready',mime:'video/mp4',bytes:13*1024*1024,durationMs:1000,events:[],athleteIds:['a']};
 let saved=structuredClone(state),verified=false,fail=true,posts=0,patches=[],complete=false;
 const offsets={},sizes={},ctx={window:{WMVideoPilot:{active:()=>false}},session:{user:{id:'u'},access_token:'test'},activeTeam:{id:'t'},SUPABASE_KEY:'test-key',managedLogin:false,document:{hidden:false},navigator:{onLine:true},Blob,URL,AbortSignal,Error,Number,btoa,console};
 ctx.WMMatchVideo={rpc:async(action)=>{if(action==='prepare')return{status:complete?'ready':'uploading',video_path:'t/u/id/original',timeline_path:'t/u/id/timeline.json'};if(action==='complete'){if(Object.keys(offsets).length!==2||Object.keys(offsets).some(k=>offsets[k]!==sizes[k]))throw Error('not complete');complete=true;return{status:'ready'};}},verifyCloud:async()=>{assert(complete);verified=true;}};
 ctx.fetch=async(url,r)=>{if(r.method==='POST'){const target='https://vfocpoyexnjsjpxhhyqr.storage.supabase.co/storage/v1/upload/resumable/'+(++posts);offsets[target]=0;sizes[target]=Number(r.headers['Upload-Length']);return{status:201,headers:new Headers({Location:target})};}
  if(r.method==='HEAD')return{ok:true,status:200,headers:new Headers({'Upload-Offset':String(offsets[url])})};
  const offset=Number(r.headers['Upload-Offset']);assert.equal(offset,offsets[url]);if(offset>0&&fail){fail=false;return{status:503,headers:new Headers()};}patches.push({url,offset,size:r.body.size});offsets[url]+=r.body.size;return{status:204,headers:new Headers({'Upload-Offset':String(offsets[url])})};};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync('src/video-upload.js','utf8'),ctx);
 const store={put:async r=>{saved=structuredClone(r);},file:async()=>new Blob([new Uint8Array(state.bytes)],{type:state.mime})};
 await ctx.window.WMVideoUpload.run(store,structuredClone(saved));assert.equal(saved.upload.status,'waiting');assert(!verified);assert.equal(posts,1);assert.equal(patches.length,1);
 await ctx.window.WMVideoUpload.run(store,structuredClone(saved));assert.equal(saved.upload.status,'ready');assert(verified);assert.equal(posts,2);assert.equal(patches.filter(p=>p.url.endsWith('/1')&&p.offset===0).length,1);assert(patches.every(p=>p.size<=6*1024*1024));
 const passed=['Interrupted upload keeps device data and persisted upload address','Retry resumes from server offset without duplicating committed chunks','Cloud-ready requires both completed objects and verified playback','Upload requests are bounded to six MiB'];
 await assert.rejects(()=>ctx.window.WMVideoUpload.tus(new Blob(['x']),'/x',{...state,upload:{video:'https://untrusted.test/storage/v1/upload/resumable/a'}},'video',async()=>{}),/trusted/);passed.push('Untrusted saved upload addresses rejected before transmitting credentials');
 // The video object can be complete even when its resumable URL has expired.
 const beforeSkipped=posts;let checks=0;verified=false;
 ctx.WMMatchVideo.rpc=async action=>{if(action==='prepare')return {status:'uploading',video_path:'t/u/id/original',timeline_path:'t/u/id/timeline.json',video_uploaded:true,timeline_uploaded:false};if(action==='complete'){if(++checks===1)throw Error('timeline missing');return {status:'ready'};}};
 await ctx.window.WMVideoUpload.run(store,{...state,id:randomUUID(),upload:{video:'https://vfocpoyexnjsjpxhhyqr.storage.supabase.co/storage/v1/upload/resumable/expired'}});
 assert.equal(posts,beforeSkipped+1);assert.equal(saved.upload.status,'ready');assert(verified);passed.push('Server-confirmed video is preserved when only its timeline needs retrying');
 ctx.session.user.id='other';const before=posts;await ctx.window.WMVideoUpload.run(store,{...state,upload:{}});assert.equal(posts,before);passed.push('Wrong account cannot resume the previous recorder upload');
 fs.writeFileSync('validation/video-upload.json',JSON.stringify({passed,engine:'Node VM protocol/storage fixtures; no production upload'},null,2));passed.forEach(p=>console.log('PASS',p));
})().catch(e=>{console.error(e);process.exit(1)});
