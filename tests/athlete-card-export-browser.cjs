const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{const root=path.resolve(__dirname,'..'),b=await chromium.launch({args:['--no-sandbox']}),p=await b.newPage();
await p.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')});
await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.abort());await p.goto('https://theteammanager.app');
const result=await p.evaluate(async()=>{const cards=Array.from({length:9},(_,i)=>({athlete_id:String(i),first_name:'Athlete',last_name:String(i),credential_token:'TEST-CARD-'+i}));const options={cards,teamName:'Test Team',PDFLib,document,QRCode,isCurrent:()=>true};
const bytes=await renderAthleteCardPDF(options),pdf=await PDFLib.PDFDocument.load(bytes);const single=await PDFLib.PDFDocument.load(await renderAthleteCardPDF({...options,cards:cards.slice(0,1),individual:true}));return {pages:pdf.getPageCount(),size:pdf.getPage(0).getSize(),single:single.getPage(0).getSize()};});
assert.equal(result.pages,2);assert.deepEqual(result.size,{width:612,height:792});assert.ok(Math.abs(result.single.width*25.4/72-85.6)<.001);
await p.evaluate(()=>{actualIsStaff=true;session={user:{id:'test'}};athleteCardRows=[{athlete_id:'a',first_name:'Long athlete name',last_name:'Test'}];document.getElementById('athleteCardSelect').replaceChildren(document.createElement('option'));openSheet('athleteCardSheet');});await p.locator('#bulkAthleteCards summary').click();
for(const width of [320,390,768]){await p.setViewportSize({width,height:900});assert.equal(await p.locator('#athleteCardSheet').evaluate(e=>e.scrollWidth<=e.clientWidth),true);}
await b.close();console.log('PDF page geometry, renderer and phone controls passed');})().catch(e=>{console.error(e);process.exit(1)});
