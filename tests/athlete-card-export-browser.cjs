const {execFileSync}=require('node:child_process'),{PNG}=require('pngjs'),jsQR=require('jsqr');
const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{const root=path.resolve(__dirname,'..'),b=await chromium.launch({args:['--no-sandbox']}),p=await b.newPage();
await p.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')});
await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.abort());await p.goto('https://theteammanager.app');
const result=await p.evaluate(async()=>{const cards=Array.from({length:9},(_,i)=>({athlete_id:String(i),first_name:'Athlete',last_name:String(i),credential_token:'TEST-CARD-'+i}));cards[0].photo_path='approved-test-photo';let photoLoads=0;
const photoCanvas=document.createElement('canvas');photoCanvas.width=20;photoCanvas.height=30;const ctx=photoCanvas.getContext('2d');ctx.fillStyle='#ff0000';ctx.fillRect(0,0,20,30);const photo=new Image();photo.src=photoCanvas.toDataURL();await photo.decode();
const options={cards,teamName:'Test Team',PDFLib,document,QRCode,isCurrent:()=>true,loadPhoto:async path=>{if(path!=='approved-test-photo')throw Error('Unexpected photo');photoLoads++;return photo;}};
const bytes=await renderAthleteCardPDF(options),pdf=await PDFLib.PDFDocument.load(bytes);const single=await PDFLib.PDFDocument.load(await renderAthleteCardPDF({...options,cards:cards.slice(0,1),individual:true}));return {photoLoads,bytes:Array.from(bytes),pages:pdf.getPageCount(),size:pdf.getPage(0).getSize(),single:single.getPage(0).getSize()};});
fs.mkdirSync(path.join(root,'validation/cards'),{recursive:true});fs.writeFileSync(path.join(root,'validation/cards/sample.pdf'),Buffer.from(result.bytes));
execFileSync('pdftoppm',['-f','1','-singlefile','-r','180','-png',path.join(root,'validation/cards/sample.pdf'),path.join(root,'validation/cards/sample')]);
const png=PNG.sync.read(fs.readFileSync(path.join(root,'validation/cards/sample.png')));
const positions=await p.evaluate(()=>athleteCardLayout(9));
for(let i=0;i<8;i++){
 const c=positions[i],scale=180/72,x=Math.floor(c.x*scale),y=Math.floor((792-c.y-c.height)*scale),w=Math.ceil(c.width*scale),h=Math.ceil(c.height*scale),data=new Uint8ClampedArray(w*h*4);
 for(let row=0;row<h;row++)data.set(png.data.subarray(((y+row)*png.width+x)*4,((y+row)*png.width+x+w)*4),row*w*4);
 const code=jsQR(data,w,h);assert.equal(code?.data,'TEST-CARD-'+i,'Each printed QR must preserve its athlete credential');
}
assert.equal(result.photoLoads,2);
const first=positions[0],photoX=Math.floor((first.x+first.width*100/1011)*2.5),photoY=Math.floor((792-first.y-first.height+first.height*380/638)*2.5),pixel=(photoY*png.width+photoX)*4;
assert.ok(png.data[pixel]>240&&png.data[pixel+1]<20&&png.data[pixel+2]<20,'Approved photo must appear in the PDF');
assert.equal(result.pages,2);assert.deepEqual(result.size,{width:612,height:792});assert.ok(Math.abs(result.single.width*25.4/72-85.6)<.001);
await p.evaluate(()=>{show('appLockOverlay',false);managedLogin=null;actualIsStaff=true;session={user:{id:'test'}};athleteCardRows=[{athlete_id:'a',first_name:'Long athlete name',last_name:'Test'}];document.getElementById('athleteCardSelect').replaceChildren(document.createElement('option'));openSheet('athleteCardSheet');});await p.locator('#bulkAthleteCards summary').click();
for(const width of [320,390,768]){await p.setViewportSize({width,height:900});assert.equal(await p.locator('#athleteCardSheet').evaluate(e=>e.scrollWidth<=e.clientWidth),true);}
await p.evaluate(()=>{window.exportCalls=0;client.rpc=async()=>{window.exportCalls++;throw Error('Must not request cards');};document.querySelector('#bulkAthleteCards input').checked=true;managedLogin={id:'managed-test'};});
await p.locator('#bulkAthleteCards [data-export]').click();assert.equal(await p.evaluate(()=>exportCalls),0);
await p.evaluate(()=>{managedLogin=null;document.body.classList.add('kiosk-locked');});
await p.locator('#bulkAthleteCards [data-export]').dispatchEvent('click');assert.equal(await p.evaluate(()=>exportCalls),0);
await p.evaluate(()=>{document.body.classList.remove('kiosk-locked');show('appLockOverlay',true);});
await p.locator('#bulkAthleteCards [data-export]').dispatchEvent('click');assert.equal(await p.evaluate(()=>exportCalls),0);
await p.evaluate(()=>{show('appLockOverlay',false);});
await p.waitForTimeout(20);
// A completed response must not escape after closing/reopening or replacing
// the signed-in session, even if the same user is signed in again.
for(const change of ['sheet','session','lock']){
 await p.evaluate(()=>{
  window.exportCalls=0;window.sharedFiles=0;
  navigator.canShare=()=>true;navigator.share=async()=>{window.sharedFiles++;};
  document.querySelector('#bulkAthleteCards input').checked=true;
  client.rpc=()=>{window.exportCalls++;return new Promise(resolve=>{window.finishCard=()=>resolve({data:{athlete_id:'a',first_name:'Test',credential_token:'TEST-PRIVATE-CARD'}});});};
 });
 await p.locator('#bulkAthleteCards [data-export]').click();
 assert.equal(await p.evaluate(()=>exportCalls),1);
 await p.evaluate(kind=>{if(kind==='sheet')show('athleteCardSheet',false);else if(kind==='session')session={user:{id:'test'}};else document.body.classList.add('kiosk-locked');},change);
 await p.waitForTimeout(20);
 await p.evaluate(kind=>{if(kind==='sheet')openSheet('athleteCardSheet');else if(kind==='lock')document.body.classList.remove('kiosk-locked');},change);
 await p.waitForTimeout(20);
 await p.evaluate(()=>finishCard());
 await p.waitForFunction(()=>!document.querySelector('#bulkAthleteCards [data-export]').disabled);
 assert.equal(await p.evaluate(()=>sharedFiles),0,'Interrupted export must not share private cards');
}
await b.close();console.log('PDF page geometry, renderer and phone controls passed');})().catch(e=>{console.error(e);process.exit(1)});
