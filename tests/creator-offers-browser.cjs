const fs=require('fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']}),ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];
p.on('pageerror',e=>errors.push(e.message));fs.mkdirSync('validation',{recursive:true});
await ctx.addInitScript({content:fs.readFileSync('tests/browser-fixture.js','utf8')});const html=fs.readFileSync('index.html','utf8');
await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:html}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
await p.goto('https://wm.example.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady&&!accountRefreshFlight);
await p.evaluate(()=>{
 session={user:{id:'creator',email:'creator@example.test'}};fixture.session=session;activeTeam=null;managedLogin=null;
 show('authView',false);show('setupView',false);show('appView',true);show('appLockOverlay',false);
 window.creatorTest={allowed:false,offers:[],events:[],trial:{days:7,requested:true,status:'awaiting_billing',revision:1},delay:0,calls:[]};
 const old=client.rpc;client.rpc=async(name,args)=>{
  if(name!=='creator_offers_request')return old(name,args);
  const c=creatorTest;c.calls.push(structuredClone(args));if(c.delay)await new Promise(r=>setTimeout(r,c.delay));
  if(args.p_action==='access')return {data:{creator:c.allowed}};
  if(!c.allowed)return {error:{code:'42501',message:'Creator access is unavailable for this account'}};
  const a=args.p_action,d=args.p_data;
  if(a==='dashboard')return {data:{creator:true,offers:c.offers,events:c.events,trial:c.trial,billing_connected:false,redemption_available:false}};
  if(a==='create'){c.offers.push({...d,code:d.code.toUpperCase(),status:'draft',revision:1,created_at:new Date().toISOString()});return {data:{saved:true}}}
  if(a==='update'){Object.assign(c.offers.find(o=>o.id===d.id),d,{revision:d.revision+1});return {data:{saved:true}}}
  if(a==='archive'){c.offers.find(o=>o.id===d.id).status='archived';return {data:{archived:true}}}
  if(a==='trial'){Object.assign(c.trial,{requested:d.requested,revision:d.revision+1});return {data:{saved:true}}}
 };
});
await p.evaluate(()=>WMCreatorOffers.refreshAccess());assert(await p.locator('#creatorOffersBtn').evaluate(el=>el.classList.contains('hidden')));
await p.evaluate(()=>WMCreatorOffers.open());await p.waitForFunction(()=>document.querySelector('#creatorOffersSheet').classList.contains('hidden'));
assert.equal(await p.locator('#creatorOfferBody').innerText(),'');console.log('PASS Unprivileged accounts have no Creator content, including direct open attempts');
await p.evaluate(()=>{creatorTest.allowed=true;return WMCreatorOffers.refreshAccess()});assert(!(await p.locator('#creatorOffersBtn').evaluate(el=>el.classList.contains('hidden'))));
await p.evaluate(()=>WMCreatorOffers.open());await p.waitForSelector('#creatorTrialSave');assert.match(await p.locator('#creatorOfferBody').innerText(),/Billing is not connected/);assert.match(await p.locator('#creatorOfferBody').innerText(),/7-day full-feature trial/);
for(const width of [320,390,768]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1))}
await p.setViewportSize({width:390,height:844});await p.screenshot({path:'validation/creator-offers-phone.png'});
await p.locator('#creatorTrialWanted').uncheck();await p.locator('#creatorTrialSave').click();await p.waitForFunction(()=>creatorTest.trial.requested===false);await p.waitForFunction(()=>!document.querySelector('#creatorTrialSave').disabled);
await p.locator('#creatorNewOffer').click();await p.locator('#creatorCode').fill('sample20');await p.locator('#creatorProduct').selectOption('team_pro_year');await p.locator('#creatorDraftSave').click();await p.waitForSelector('[data-creator-edit]');
assert.match(await p.locator('#creatorOfferBody').innerText(),/Draft · not redeemable/);assert.match(await p.locator('#creatorOfferBody').innerText(),/SAMPLE20/);console.log('PASS The Creator can prepare codes and a seven-day trial without a team; neither is presented as active');
await p.locator('[data-creator-edit]').click();await p.locator('#creatorDiscount').fill('25');await p.locator('#creatorDraftSave').click();await p.waitForFunction(()=>creatorTest.offers[0].discount_percent===25);await p.waitForSelector('[data-creator-archive]');await p.locator('[data-creator-archive]').click();await p.waitForFunction(()=>creatorTest.offers[0].status==='archived');
await p.locator('#creatorClose').click();assert.equal(await p.locator('#creatorOfferBody').innerText(),'');assert(await p.locator('#sheetBackdrop').evaluate(el=>el.classList.contains('hidden')));console.log('PASS Draft edits and archive actions use revisions; Close clears content and the backdrop');
await p.evaluate(()=>WMCreatorOffers.open());await p.waitForSelector('#creatorTrialSave');await p.evaluate(()=>show('appLockOverlay',true));await p.waitForSelector('#creatorOffersSheet.hidden',{state:'attached'});assert.equal(await p.locator('#creatorOfferBody').innerText(),'');await p.evaluate(()=>show('appLockOverlay',false));
await p.evaluate(()=>{creatorTest.delay=800;WMCreatorOffers.open()});await p.evaluate(()=>{session={user:{id:'another-account'}};fixture.session=session});await p.waitForTimeout(1000);assert.equal(await p.locator('#creatorOfferBody').innerText(),'');
await p.evaluate(()=>{creatorTest.delay=0;return WMCreatorOffers.open()});await p.waitForSelector('#creatorTrialSave');await ctx.setOffline(true);await p.waitForSelector('#creatorOffersSheet.hidden',{state:'attached'});assert.equal(await p.locator('#creatorOfferBody').innerText(),'');console.log('PASS Lock, account changes, delayed replies and disconnection clear private Creator content');
assert.deepEqual(errors,[]);await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
