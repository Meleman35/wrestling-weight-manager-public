const {execFileSync}=require('node:child_process'),{PNG}=require('pngjs'),jsQR=require('jsqr');
const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{const root=path.resolve(__dirname,'..'),b=await chromium.launch({args:['--no-sandbox']}),p=await b.newPage();
await p.addInitScript({content:fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')});
await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.abort());await p.goto('https://theteammanager.app');
const result=await p.evaluate(async()=>{const cards=Array.from({length:9},(_,i)=>({athlete_id:String(i),first_name:'Athlete',last_name:String(i),credential_token:'TEST-CARD-'+i}));const options={cards,teamName:'Test Team',PDFLib,document,QRCode,isCurrent:()=>true};
const bytes=await renderAthleteCardPDF(options),pdf=await PDFLib.PDFDocument.load(bytes);const single=await PDFLib.PDFDocument.load(await renderAthleteCardPDF({...options,cards:cards.slice(0,1),individual:true}));return {bytes:Array.from(bytes),pages:pdf.getPageCount(),size:pdf.getPage(0).getSize(),single:single.getPage(0).getSize()};});
fs.mkdirSync(path.join(root,'validation/cards'),{recursive:true});fs.writeFileSync(path.join(root,'validation/cards/sample.pdf'),Buffer.from(result.bytes));
execFileSync('pdftoppm',['-f','1','-singlefile','-r','180','-png',path.join(root,'validation/cards/sample.pdf'),path.join(root,'validation/cards/sample')]);
const png=PNG.sync.read(fs.readFileSync(path.join(root,'validation/cards/sample.png')));const code=jsQR(new Uint8ClampedArray(png.data),png.width,png.height);assert.ok(code&&/^TEST-CARD-/.test(code.data),'Printed PDF QR must decode to the original credential');
assert.equal(result.pages,2);assert.deepEqual(result.size,{width:612,height:792});assert.ok(Math.abs(result.single.width*25.4/72-85.6)<.001);
await p.evaluate(()=>{actualIsStaff=true;session={user:{id:'test'}};athleteCardRows=[{athlete_id:'a',first_name:'Long athlete name',last_name:'Test'}];document.getElementById('athleteCardSelect').replaceChildren(document.createElement('option'));openSheet('athleteCardSheet');});await p.locator('#bulkAthleteCards summary').click();
for(const width of [320,390,768]){await p.setViewportSize({width,height:900});assert.equal(await p.locator('#athleteCardSheet').evaluate(e=>e.scrollWidth<=e.clientWidth),true);}
await b.close();console.log('PDF page geometry, renderer and phone controls passed');})().catch(e=>{console.error(e);process.exit(1)});
