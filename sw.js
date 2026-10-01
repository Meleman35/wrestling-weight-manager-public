/* Static resources only. Never cache Supabase, authenticated responses, attachments, or invite URLs. */
const CACHE='wm-shell-0.20.108';
const ROOT=new URL('./',self.location.href);
const FILES=['index.html','vendor/supabase.js','assets/wrestling-manager-icon.png','manifest.webmanifest'];
self.addEventListener('install',event=>event.waitUntil((async()=>{const c=await caches.open(CACHE);await c.addAll(FILES.map(p=>new Request(new URL(p,ROOT),{cache:'reload'})));})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{for(const name of await caches.keys())if(name.startsWith('wm-shell-')&&name!==CACHE)await caches.delete(name);await self.clients.claim();})()));
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);if(event.request.method!=='GET'||url.origin!==ROOT.origin)return;
 const home=url.pathname===ROOT.pathname||url.pathname===new URL('index.html',ROOT).pathname;
 if(event.request.mode==='navigate'&&home){event.respondWith((async()=>{
  // Keep shell and worker on the same version. Browser checks worker updates separately.
  const hit=await caches.match(new URL('index.html',ROOT));return hit||fetch(event.request);
 })());return;}
 if(!url.search&&FILES.slice(1).some(p=>url.href===new URL(p,ROOT).href))event.respondWith(caches.match(url).then(hit=>hit||fetch(event.request)));
});
