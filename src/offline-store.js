/* Durable, encrypted, account-scoped IndexedDB state. No authenticated responses in Cache Storage. */
window.WMOfflineStore=(()=>{
 'use strict';const DB='wm-coach-offline-v1',enc=new TextEncoder(),dec=new TextDecoder();let opening;
 function db(){return opening||(opening=new Promise((resolve,reject)=>{const r=indexedDB.open(DB,1);r.onupgradeneeded=()=>{r.result.createObjectStore('keys');r.result.createObjectStore('records');};r.onsuccess=()=>{r.result.onversionchange=()=>{r.result.close();opening=null;};resolve(r.result);};r.onerror=()=>{opening=null;reject(r.error);};r.onblocked=()=>reject(Error('Close other app windows and reopen Offline workspace.'));}));}
 async function tx(store,mode,fn){const d=await db();return new Promise((resolve,reject)=>{const t=d.transaction(store,mode),s=t.objectStore(store);let value;t.oncomplete=()=>resolve(value);t.onabort=t.onerror=()=>reject(t.error||Error('Device storage could not save. Keep this screen open and try again.'));try{fn(s,v=>value=v,t);}catch(e){t.abort();reject(e);}});}
 const read=(s,k)=>tx(s,'readonly',(o,done)=>{const r=o.get(k);r.onsuccess=()=>done(r.result);});
 async function key(user){const old=await read('keys',user);if(old)return old;const fresh=await crypto.subtle.generateKey({name:'AES-GCM',length:256},false,['encrypt','decrypt']);return tx('keys','readwrite',(s,done,t)=>{const r=s.get(user);r.onsuccess=()=>{try{if(r.result)done(r.result);else{s.put(fresh,user);done(fresh);}}catch{t.abort();}};});}
 const empty=()=>({version:1,packs:{},queue:[],history:[],drafts:{}});
 async function decode(user,row){if(!row)return empty();if(row.version!==1)throw Error('Update the app to read this device’s saved work.');return JSON.parse(dec.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:row.iv,additionalData:enc.encode(user)},await key(user),row.data)));}
 async function get(user){if(!user)throw Error('Choose your profile.');return decode(user,await read('records',user));}
 async function update(user,change,guard=()=>true){
  for(let n=0;n<12;n++){
   if(!guard())throw Error('Your profile changed. Reopen Offline workspace.');
   const old=await read('records',user),body=await decode(user,old),result=change(body),iv=crypto.getRandomValues(new Uint8Array(12));
   const data=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:enc.encode(user)},await key(user),enc.encode(JSON.stringify(body)));
   const saved=await tx('records','readwrite',(s,done,t)=>{const r=s.get(user);r.onsuccess=()=>{try{if(!guard()){t.abort();return;}if(r.result?.revision!==old?.revision){done(false);return;}s.put({version:1,revision:crypto.randomUUID(),iv,data},user);done(true);}catch{t.abort();}};});
   if(saved)return result;
  }
  throw Error('Another window is saving. Try again.');
 }
 const packKey=(team,season)=>team+'/'+season;
 function enqueue(body,request,label,draftKey){
  const same=q=>q.request.team_id===request.team_id&&q.request.season_id===request.season_id&&q.request.kind===request.kind&&q.request.event_id===request.event_id&&(request.kind!=='attendance'||q.request.athlete_id===request.athlete_id);
  if(request.kind!=='message'&&body.queue.some(same))throw Error('This record already has a saved change. Sync or review it first.');
  const item={id:crypto.randomUUID(),created_at:new Date().toISOString(),state:'pending',attempts:0,next_at:0,label,request};
  item.request={...request,operation_id:item.id};body.queue.push(item);if(draftKey)delete body.drafts[draftKey];return item;
 }
 function accept(body,id,result){const q=body.queue.find(x=>x.id===id);if(!q)return;
  if(result.status!=='applied'){q.state=result.status;q.result=result;return;}
  const p=body.packs[packKey(q.request.team_id,q.request.season_id)],v=result.value;
  if(p&&q.request.kind==='attendance'){p.attendance=p.attendance.filter(x=>!(x.event_id===q.request.event_id&&x.athlete_id===q.request.athlete_id));p.attendance.push(v);}
  if(p&&q.request.kind==='event')p.events=p.events.map(x=>x.id===q.request.event_id?v:x);
  if(p&&q.request.kind==='message'){const list=p.messages[q.request.thread_id]||[];if(!list.some(x=>x.message_id===v))list.push({message_id:v,body:q.request.body,sender_name:'You',is_mine:true,created_at:new Date().toISOString()});p.messages[q.request.thread_id]=list.slice(-80);}
  body.history.unshift({...q,state:'applied',result,confirmed_at:new Date().toISOString()});body.history=body.history.slice(0,50);body.queue=body.queue.filter(x=>x.id!==id);
 }
 return {get,update,packKey,enqueue,accept};
})();
