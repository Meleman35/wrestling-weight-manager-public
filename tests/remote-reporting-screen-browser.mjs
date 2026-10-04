import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)('playwright');
const html=`<!doctype html><html><body><button id="open">Remote weigh-ins</button><div id="root"></div><script type="module">
import {installRemoteReportingApp} from '/src/remote-weighins-app.mjs';
window.unlocked=true;window.personal=true;window.owner='user';window.responses=[];window.photoResolve=null;
const period={id:'week',programId:'network',timeZone:'America/Denver',opensAt:'2026-10-01T00:00:00Z',closesAt:'2026-10-08T00:00:00Z'};
window.api=installRemoteReportingApp({enabled:true,button:document.getElementById('open'),root:document.getElementById('root'),show:()=>{},hide:()=>{},unlocked:()=>window.unlocked,personal:()=>window.personal,publishableKey:'public-key',getSession:async()=>({user:{id:window.owner},access_token:'header.'+btoa(JSON.stringify({sub:window.owner,session_id:'browser-session'}))+'.signature'}),fetch:async(url,options)=>{
const action=url.split('/').at(-1),body=JSON.parse(options.body);window.responses.push({action,body});
if(action==='context')return Response.json({scopes:[{programId:'network',clubId:'club',label:'Network · Club',canCapture:true,windows:[period]}]});
if(action==='photo-read')return new Promise(resolve=>window.photoResolve=()=>resolve(new Response(new Uint8Array([255,216,255,217]),{headers:{'Content-Type':'image/jpeg'}})));
return Response.json({programId:'network',windowId:'week',revision:'a'.repeat(64),classification:'Remote club report',timeZone:'America/Denver',counts:{expected:2,submitted:1,late:0,missing:1},total:2,nextOffset:body.offset?null:1,rows:body.status==='missing'?[{athleteId:'missing',clubId:'club',athleteName:'Casey Sample',clubName:'Club',status:'missing',submission:null}]:[{athleteId:'athlete',clubId:'club',athleteName:'<img src=x onerror=alert(1)>',clubName:'Club',status:'submitted',submission:{submissionId:'capture',weight:120,capturedAt:'2026-10-03T20:00:00Z',receivedAt:'2026-10-03T20:01:00Z'}}]});}});
</script></body></html>`;
const server=createServer(async(req,res)=>{try{if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end(html);return;}if(!['/src/remote-weighins-app.mjs','/src/remote-weighins-client.mjs','/src/remote-weighins-screen.mjs','/src/remote-weighins-export.mjs','/src/remote-weighins-xlsx.mjs','/src/remote-weighins.mjs'].includes(req.url)){res.statusCode=404;res.end();return;}res.setHeader('Content-Type','text/javascript');res.end(await readFile('.'+req.url));}catch{res.statusCode=500;res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({headless:true});
try{
const page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}`);
await page.waitForFunction(()=>window.api);await page.click('#open');await page.waitForSelector('tbody tr');
assert.equal(await page.locator('tbody th').textContent(),'Club');assert.equal(await page.getByText('Download Excel with photos',{exact:true}).count(),1);assert.match(await page.locator('.remote-reporting-screen').textContent(),/Your downloaded spreadsheet remains available/);assert.equal(await page.locator('tbody img').count(),0);assert.match(await page.locator('tbody').textContent(),/<img src=x/);
assert.equal(await page.getByText('Start club weigh-ins',{exact:true}).isVisible(),false);
await page.getByText('Load more',{exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('tbody [data-athlete-row]').length===2);
const queries=await page.evaluate(()=>window.responses.filter(r=>r.action==='report').map(r=>r.body));assert.equal(queries[0].clubId,'club');assert.equal(queries[1].offset,1);
await page.locator('select[aria-label="Submission status"]').selectOption('missing');await page.waitForFunction(()=>document.querySelector('tbody')?.textContent.includes('Casey Sample'));assert.equal(await page.getByText('View photo',{exact:true}).count(),0);
await page.locator('select[aria-label="Submission status"]').selectOption('');await page.waitForSelector('tbody button');
await page.getByText('View photo',{exact:true}).click();await page.waitForFunction(()=>window.photoResolve!==null);
await page.evaluate(()=>{window.api.close();window.photoResolve();});await page.waitForTimeout(100);assert.equal(await page.locator('#root img').count(),0);assert.equal(await page.locator('#root').textContent(),'');
await page.click('#open');await page.waitForSelector('tbody tr');await page.evaluate(()=>window.unlocked=false);await page.waitForFunction(()=>document.getElementById('root').childElementCount===0);
await page.evaluate(()=>{window.unlocked=true;window.personal=false;});await page.click('#open');assert.equal(await page.locator('#root').textContent(),'');
console.log('Reporting screen browser checks passed: scoped queries, pagination/filtering, HTML escaping, capture gate, late photo cancellation, lock and managed-account rejection.');
}finally{await browser.close();await new Promise(r=>server.close(r));}
