const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('https://plans.test/**',route=>{
   const name=new URL(route.request().url()).pathname.slice(1);
   if(!name)return route.fulfill({contentType:'text/html',body:`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/subscription-screen.css"><button id="open">Plans</button><div id="root"></div><script type="module">
import {installSubscriptionApp} from '/subscription-app.mjs';
window.owner='11111111-1111-4111-8111-111111111111';window.team='22222222-2222-4222-8222-222222222222';window.unlocked=true;window.personal=true;window.calls=[];window.waitActivation=false;
const products=['teampro','familyvideo'].flatMap(kind=>['monthly','annual'].map(period=>({id:'com.damonmele.wrestlingmanager.'+kind+'.'+period,type:'autoRenewable',displayPrice:kind==='familyvideo'?(period==='monthly'?'$10.00':'$75.00'):(period==='monthly'?'$75.00':'$269.99')})));
const handlers={wmPurchaseActivation:{postMessage:async body=>{calls.push(body.command);if(body.command==='stop')return {stopped:true};if(waitActivation)await new Promise(resolve=>window.resolveActivation=resolve);return {ready:true,generation:'generation'};}},wmPurchases:{postMessage:async body=>{calls.push(body);return body.command==='products'?{products}:{outcome:'delivered'};}}};
window.host=installSubscriptionApp({button:document.querySelector('#open'),root:document.querySelector('#root'),show:()=>{},hide:()=>{},beforeOpen:()=>{},getSession:()=>({user:{id:owner},access_token:'h.'+btoa(JSON.stringify({sub:owner,session_id:'33333333-3333-4333-8333-333333333333'}))+'.s'}),getTeam:()=>team?{id:team}:null,unlocked:()=>unlocked,personal:()=>personal,publishableKey:'public',native:()=>handlers,createAPI:()=>({readAccess:async()=>({teamPro:true}),coverageOptions:async()=>({athletes:[{athlete_id:'44444444-4444-4444-8444-444444444444',profile_id:'55555555-5555-4555-8555-555555555555',display_name:'<img src=x onerror=alert(1)>',selected:true}]}),saveCoverage:async args=>({selectedCount:args.athleteIDs.length}),stop(){}})});
</script>`});
   if(!/^[a-z-]+\.(mjs|css)$/.test(name))return route.abort();
   return route.fulfill({contentType:name.endsWith('.css')?'text/css':'text/javascript',body:fs.readFileSync(path.join(root,name),'utf8')});
  });
  await page.goto('https://plans.test/');await page.waitForFunction(()=>window.host);
  await page.click('#open');await page.getByText('Team Pro is active for this team.',{exact:true}).waitFor();
  const benefits=await page.locator('.wm-subscription-benefits').innerText();
  assert.match(benefits,/Practice Plans/);assert.match(benefits,/Wrestler Statistics/);
  assert.equal(await page.evaluate(()=>calls.filter(x=>x?.command==='purchase').length),0);
  const links=page.getByRole('navigation',{name:'Subscription information'});
  assert.equal(await links.getByRole('link',{name:'Privacy information'}).getAttribute('data-wm-info'),'privacy');
  assert.equal(await links.getByRole('link',{name:'Help and support'}).getAttribute('data-wm-info'),'support');
  const eula=links.getByRole('link',{name:'Apple standard EULA'});
  assert.equal(await eula.getAttribute('href'),'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
  assert.equal(await eula.getAttribute('referrerpolicy'),'no-referrer');
  for(const width of [320,390,768]){await page.setViewportSize({width,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));}
  await page.setViewportSize({width:390,height:844});fs.mkdirSync('validation',{recursive:true});
  await page.screenshot({path:'validation/team-pro-launch-information.png',fullPage:true});
  await page.getByRole('button',{name:'Monthly — $75.00/month',exact:true}).click();
  assert.deepEqual(await page.evaluate(()=>calls.filter(x=>x?.command==='purchase').at(-1).target),{kind:'team',teamID:'22222222-2222-4222-8222-222222222222'});
  assert.equal(await page.getByRole('button',{name:'Family Video',exact:true}).count(),0);
  await page.getByText('Availability and plan limits',{exact:true}).click();
  await page.getByText('Family Video is planned for a later update and is not included at launch.',{exact:true}).waitFor();
  const purchasesBefore=await page.evaluate(()=>calls.filter(x=>x?.command==='purchase').length);
  await page.evaluate(()=>host.open('family'));
  await page.getByText('Family Video is planned for a later update and is not available for purchase.',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>calls.filter(x=>x?.command==='purchase').length),purchasesBefore);
  assert.equal(await page.locator('.wm-family-coverage-screen').count(),0);
  await page.evaluate(()=>host.open('team'));await page.getByText('Team Pro is active for this team.',{exact:true}).waitFor();
  await page.evaluate(()=>unlocked=false);await page.waitForFunction(()=>document.querySelector('#root').childElementCount===0);
  await page.evaluate(()=>{unlocked=true;personal=false;});await page.click('#open');assert.equal(await page.locator('#root').textContent(),'');
  await page.evaluate(()=>{personal=true;waitActivation=true;});await page.click('#open');await page.waitForFunction(()=>window.resolveActivation);
  await page.evaluate(()=>{host.close();owner='66666666-6666-4666-8666-666666666666';resolveActivation();});
  await page.waitForTimeout(100);assert.equal(await page.locator('#root').textContent(),'');
  assert.deepEqual(errors,[]);console.log('PASS: in-app plan host, native activation, immutable team target, deferred Family Video blocked, lock/managed rejection and stale activation isolation');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
