const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try {
  const page=await browser.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('https://billing.test/**',route=>{
   const name=new URL(route.request().url()).pathname.slice(1);
   if(!name)return route.fulfill({contentType:'text/html',body:`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/subscription-screen.css"><main id="target"></main><script type="module">import {mountSubscriptionScreen} from '/subscription-screen.mjs';import {mountFamilyCoverageScreen} from '/family-coverage-screen.mjs';window.mount=mountSubscriptionScreen;window.mountCoverage=mountFamilyCoverageScreen;</script>`});
   if(!['subscription-screen.css','subscription-screen.mjs','subscription-presentation.mjs','family-coverage-screen.mjs'].includes(name))return route.abort();
   return route.fulfill({contentType:name.endsWith('.css')?'text/css':'text/javascript',body:fs.readFileSync(path.join(root,name),'utf8')});
  });
  await page.goto('https://billing.test/');await page.waitForFunction(()=>typeof window.mount==='function');
  const config={kind:'family',purchaseReady:true,products:[{id:'com.damonmele.wrestlingmanager.familyvideo.monthly',type:'autoRenewable',displayPrice:'$14.99'},{id:'com.damonmele.wrestlingmanager.familyvideo.annual',type:'autoRenewable',displayPrice:'$99.99'}]};
  await page.evaluate(c=>{
   window.calls=[];window.screenHandle=mount(document.querySelector('#target'),c,{
    purchase:(id,target)=>{calls.push({id,target});return new Promise(resolve=>window.resolvePurchase=resolve)},
    restore:()=>{calls.push({restore:true});return 'delivered'}
   });
  },config);
  for(const width of [320,390,768,1100]){
   await page.setViewportSize({width,height:900});
   assert.equal(await page.locator('body').evaluate(n=>n.scrollWidth<=innerWidth),true,`overflow at ${width}`);
  }
  await page.setViewportSize({width:390,height:844});
  await page.getByText('Streaming, storage and texting',{exact:true}).click();
  assert.equal(await page.getByText('Live streaming is not available yet.',{exact:true}).isVisible(),true);
  fs.mkdirSync(path.join(root,'../validation'),{recursive:true});
  await page.screenshot({path:path.join(root,'../validation/subscription-family-phone.png'),fullPage:true});
  await page.getByRole('button',{name:'Monthly — $14.99/month',exact:true}).click();
  assert.equal(await page.getByRole('button',{name:'Restore Purchases'}).isDisabled(),true);
  assert.deepEqual(await page.evaluate(()=>calls),[{id:'com.damonmele.wrestlingmanager.familyvideo.monthly',target:{kind:'family'}}]);
  await page.evaluate(()=>resolvePurchase('pending'));
  await page.getByRole('status').filter({hasText:'awaiting approval'}).waitFor();
  await page.getByRole('button',{name:'Restore Purchases'}).click();
  await page.getByRole('status').filter({hasText:'Purchase processed'}).waitFor();
  assert.deepEqual(await page.evaluate(()=>calls.at(-1)),{restore:true});
  await page.getByRole('button',{name:'Monthly — $14.99/month',exact:true}).click();
  await page.evaluate(()=>{screenHandle.dispose();resolvePurchase('delivered')});
  assert.equal(await page.locator('.wm-subscription-screen').count(),0);
  // A new account's screen must not receive the disposed account's response.
  await page.evaluate(c=>{window.screenHandle=mount(document.querySelector('#target'),{...c,purchaseReady:false});},config);
  assert.equal(await page.getByRole('button',{name:'Restore Purchases'}).isDisabled(),true);
  assert.match(await page.getByRole('status').textContent(),/not available for purchase/);
  await page.evaluate(c=>{
   screenHandle.dispose();window.injected=false;
   screenHandle=mount(document.querySelector('#target'),{...c,products:[{...c.products[0],displayPrice:'<img src=x onerror="window.injected=true">'}]});
  },config);
  assert.equal(await page.locator('img').count(),0);assert.equal(await page.evaluate(()=>injected),false);
  await page.evaluate(()=>{
   screenHandle.dispose();window.generation='a';window.coverageCalls=[];window.coverageRefreshes=0;
   window.coverageHandle=mountCoverage(document.querySelector('#target'),{
    athletes:[{athlete_id:'a',profile_id:'p-a',display_name:'<img src=x onerror="window.injected=true">'},
     {athlete_id:'duplicate',profile_id:'p-a',display_name:'Same athlete on another team'},
     {athlete_id:'b',profile_id:'p-b',display_name:'Second athlete'},
     {athlete_id:'c',profile_id:'p-c',display_name:'Third athlete'}],
    isCurrent:()=>generation==='a',
    saveCoverage:context=>{coverageCalls.push(context.athleteIDs);window.coverageGuard=context.isCurrent;return new Promise(resolve=>window.resolveCoverage=resolve);},
    refreshAccess:async()=>{coverageRefreshes++;}
   });
  });
  const boxes=page.locator('.wm-family-coverage-screen input');
  await boxes.nth(0).check();await boxes.nth(1).check();assert.equal(await boxes.nth(1).isChecked(),false);
  await boxes.nth(2).check();await boxes.nth(3).check();assert.equal(await boxes.nth(3).isChecked(),false);
  assert.equal(await page.locator('img').count(),0);
  await page.getByRole('button',{name:'Save athlete selection'}).click();
  assert.equal(await boxes.nth(0).isDisabled(),true);
  assert.deepEqual(await page.evaluate(()=>coverageCalls),[['a','b']]);
  await page.evaluate(()=>resolveCoverage({selectedCount:2}));
  await page.getByRole('status').filter({hasText:'Subscription access checked'}).waitFor();
  assert.equal(await page.evaluate(()=>coverageRefreshes),1);
  await boxes.nth(0).uncheck();await boxes.nth(2).uncheck();
  await page.getByRole('button',{name:'Save athlete selection'}).click();
  assert.deepEqual(await page.evaluate(()=>coverageCalls.at(-1)),[]);
  await page.evaluate(()=>{generation='b';coverageHandle.dispose();resolveCoverage({selectedCount:0});});
  await page.waitForTimeout(20);
  assert.equal(await page.evaluate(()=>coverageGuard()),false);
  assert.equal(await page.evaluate(()=>coverageRefreshes),1);
  assert.equal(await page.locator('.wm-family-coverage-screen').count(),0);
  assert.deepEqual(errors,[]);
  console.log('PASS subscription screen: responsive widths, price escaping, family scope, restore, pending, busy state and disposed account responses');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
