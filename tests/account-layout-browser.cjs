'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({headless:true,args:['--no-sandbox']}),page=await browser.newPage();
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript({content:'if(window===window.top){'+fs.readFileSync(path.join(root,'tests/browser-fixture.js'),'utf8')+'}'});
 await page.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.abort());
 await page.goto('https://theteammanager.app/');
 await page.evaluate(()=>{session=fixture.session={user:{id:'layout-test',email:'test@example.invalid'},access_token:'synthetic'};managedLogin=null;show('appLockOverlay',false);openAccountSheet();});
 await page.waitForTimeout(150);
 assert.equal(await page.locator('#editTeamBtn').count(),1);
 assert.equal(await page.locator('[data-account-group="preferences"] #securityBtn').count(),1);
 assert.equal(await page.locator('[data-account-group="tools"] [data-wm-mat-mode]').count(),1);
 assert.equal(await page.locator('[data-account-group="creator"]').isVisible(),false);
 await page.locator('.account-profile-editor summary').click();
 await page.locator('#accountDisplayName').fill('Unsaved profile draft');
 await page.locator('.account-profile-editor summary').click();
 await page.locator('.account-profile-editor summary').click();
 assert.equal(await page.locator('#accountDisplayName').inputValue(),'Unsaved profile draft');
 await page.evaluate(()=>{show('creatorOffersBtn',true);show('editTeamBtn',true);});
 await page.waitForTimeout(50);assert.equal(await page.locator('[data-account-group="creator"]').isVisible(),true);
 assert.equal(await page.locator('#editTeamBtn').evaluate(e=>getComputedStyle(e).backgroundColor),'rgba(0, 0, 0, 0)');
 await page.evaluate(()=>{show('creatorOffersBtn',false);});await page.waitForTimeout(50);
 assert.equal(await page.locator('[data-account-group="creator"]').isVisible(),false);
 for(const width of [320,390,768,1100]){
  await page.setViewportSize({width,height:900});
  assert.equal(await page.locator('#accountSheet').evaluate(e=>e.scrollWidth<=e.clientWidth),true);
 }
 await page.setViewportSize({width:390,height:844});await page.locator('.account-profile-editor summary').click();
 await page.locator('#accountSheet').evaluate(e=>{e.scrollTop=0;});
 await page.screenshot({path:path.join(root,'validation/account-layout-phone.png')});
 assert.equal(await page.locator('#signOutBtn').count(),1);
 assert.equal(await page.locator('#webUpdatesCheck').count(),1);
 await page.evaluate(async()=>{
  const prior=client.rpc;client.rpc=async(name,args)=>name==='creator_offers_request'?{data:args.p_action==='access'?{creator:true,home_mode:'team'}:{creator:true,home_mode:'team',offers:[],trial:{requested:true,revision:1}},error:null}:prior(name,args);
  await WMCreatorOffers.refreshAccess();openAccountSheet();
 });
 await page.locator('#creatorOffersBtn').click();await page.locator('#creatorDashboardRolePreviewBtn').waitFor({state:'visible'});
 await page.locator('#creatorOffersSheet [data-sheet-back]').click();assert.equal(await page.locator('#accountSheet').isVisible(),true);
 await page.locator('#creatorAccountRolePreviewBtn').click();await page.locator('#creatorRolePreviewFrame').waitFor();
 const demo=page.frameLocator('#creatorRolePreviewFrame');await demo.locator('[data-demo-page="profile"]').click();
 await page.locator('#creatorRolePreviewSheet [data-sheet-back]').click();await demo.locator('[data-demo-page="home"][aria-pressed="true"]').waitFor();
 assert.equal(await page.locator('#creatorRolePreviewSheet').isVisible(),true);
 await page.locator('#creatorRolePreviewClose').click();await page.locator('#creatorDashboardRolePreviewBtn').waitFor({state:'visible'});
 assert.equal(await page.locator('#creatorRolePreviewFrame').count(),0);
 await page.locator('#creatorOffersSheet [data-sheet-back]').click();assert.equal(await page.locator('#accountSheet').isVisible(),true);
 await page.evaluate(()=>{closeSheets();openSheet('athleteProfileSheet');});
 assert.equal(await page.locator('#athleteProfileSheet .athlete-profile-section').count(),4);
 assert.equal(await page.locator('#profileFirstName').count(),1);await page.locator('#profileFirstName').fill('Unsaved athlete');
 for(const width of [320,390,768,1100]){await page.setViewportSize({width,height:900});assert.equal(await page.locator('#athleteProfileSheet').evaluate(e=>e.scrollWidth<=e.clientWidth),true);}
 assert.equal(await page.locator('#profileFirstName').inputValue(),'Unsaved athlete');
 assert.equal(await page.locator('#profileMedicalShare').count(),1);assert.equal(await page.locator('#saveAthleteProfileBtn').count(),1);
 await page.setViewportSize({width:390,height:844});await page.locator('#athleteProfileSheet').evaluate(e=>e.scrollTop=0);
 await page.screenshot({path:path.join(root,'validation/athlete-profile-layout-phone.png')});
 console.log('Creator/demo return navigation and athlete editor layout passed');
 assert.equal(errors.length,0,errors.join('\n'));
 console.log('Account layout: widths, visibility, retained drafts and controls passed');await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
