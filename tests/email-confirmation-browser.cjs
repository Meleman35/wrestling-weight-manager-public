const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),checks=[];
const pass=s=>{checks.push(s);console.log('PASS',s);};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const fixture=fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8');
 const app=fs.readFileSync(path.join(root,'index.html'),'utf8'),confirm=fs.readFileSync(path.join(root,'auth-confirm.html'),'utf8');
 async function screen(url,{confirmed=true,fail=false}={}){
   const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[],launches=[],requests=[];
   await ctx.addInitScript({content:fixture});
   p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(/wrestlingmanager:|Failed to launch/.test(m.text()))launches.push(m.text());});
   await p.route('**/*',r=>{
     const u=new URL(r.request().url());
     if(u.pathname==='/auth/v1/user'){requests.push(r.request().headers());return r.fulfill({status:fail?401:200,contentType:'application/json',body:JSON.stringify({email_confirmed_at:confirmed?'2026-09-28T00:00:00Z':null})});}
     if(r.request().isNavigationRequest()&&u.hostname==='theteammanager.app')return r.fulfill({contentType:'text/html',body:u.pathname==='/auth-confirm.html'?confirm:app});
     if(u.href.includes('supabase-js'))return r.fulfill({contentType:'text/javascript',body:''});
     return r.abort();
   });
   await p.goto(url);return {p,ctx,errors,launches,requests};
 }
 const good=await screen('https://theteammanager.app/auth-confirm.html#access_token=synthetic-only&refresh_token=never-forward');
 await good.p.waitForFunction(()=>document.getElementById('title').textContent==='Email confirmed');
 assert.equal(good.p.url(),'https://theteammanager.app/auth-confirm.html');
 assert.equal(good.requests[0].authorization,'Bearer synthetic-only');
 assert.equal(await good.p.locator('#openApp').isVisible(),false);
 assert.equal(await good.p.locator('#openWebsite').getAttribute('href'),'https://theteammanager.app/?email-confirmed=1');
 assert(!JSON.stringify(await good.p.locator('a').evaluateAll(xs=>xs.map(x=>x.href))).includes('synthetic-only'));
 assert(!await good.p.evaluate(()=>localStorage.getItem('access_token')));
 await good.p.screenshot({path:path.join(root,'validation/email-confirmation-phone.png'),fullPage:true});
 pass('Verified email confirmation offers browser continuation first, hides installed-app action, and strips credentials from URL and onward links');
 await good.p.locator('#openWebsite').click();await good.p.waitForFunction(()=>window.wrestlingManagerSignInReady===true);
 assert.equal(await good.p.locator('#email').isVisible(),true);assert.deepEqual(good.launches,[]);assert.deepEqual(good.errors,[]);await good.ctx.close();
 pass('Continue in Browser reaches personal sign-in with no native app launch');
 for(const opts of [{confirmed:false},{fail:true}]){
   const s=await screen('https://theteammanager.app/auth-confirm.html#access_token=synthetic-only',opts);
   await s.p.waitForFunction(()=>document.getElementById('title').textContent==='Return to sign in');
   assert.match(await s.p.locator('#status').innerText(),/Resend Confirmation Email/);assert(await s.p.locator('#openWebsite').isVisible());assert.deepEqual(s.errors,[]);await s.ctx.close();
 }
 const expired=await screen('https://theteammanager.app/auth-confirm.html#error=access_denied&error_code=otp_expired');
 assert.equal(await expired.p.locator('#title').innerText(),'Return to sign in');assert.equal(expired.requests.length,0);assert.equal(expired.p.url(),'https://theteammanager.app/auth-confirm.html');await expired.ctx.close();
 pass('Unconfirmed, rejected, and expired links offer browser sign-in/resend without claiming confirmation succeeded');
 for(const query of ['?join=WMW-EXAMPLE-TEAM','?invite=WMM-EXAMPLE-PRIVATE']){
   const s=await screen('https://theteammanager.app/'+query);await s.p.waitForFunction(()=>window.wrestlingManagerSignInReady===true);await s.p.waitForTimeout(400);
   assert.equal(await s.p.evaluate(()=>sessionStorage.getItem('wm-app-open-attempt')),null);assert.deepEqual(s.launches,[]);assert.deepEqual(s.errors,[]);
   assert(await s.p.locator('#inviteAppChoice').isVisible());assert.equal(await s.p.locator('#inviteOpenApp').isVisible(),false);
   await s.p.locator('#inviteAppChoice summary').click();
   assert.equal(await s.p.locator('#inviteOpenApp').getAttribute('href'),query.includes('join')?'wrestlingmanager://join?code=WMW-EXAMPLE-TEAM':'wrestlingmanager://invite?token=WMM-EXAMPLE-PRIVATE');
   const saved=await s.p.evaluate(()=>JSON.parse(localStorage.getItem('wm.onboarding.v1')));assert(query.includes('join')?saved.join==='WMW-EXAMPLE-TEAM':saved.invite==='WMM-EXAMPLE-PRIVATE');
   for(const width of [320,390]){await s.p.setViewportSize({width,height:844});assert(await s.p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));}
   await s.ctx.close();
 }
 pass('Team and invitation links stay in the browser, preserve onboarding context, fit phone widths, and expose native links only as an explicit choice');
 const native=await screen('https://theteammanager.app/?join=WMW-EXAMPLE-TEAM&nativeBuild=3');await native.p.waitForFunction(()=>window.wrestlingManagerSignInReady===true);assert.equal(await native.p.locator('#inviteAppChoice').isVisible(),false);await native.ctx.close();
 pass('Installed native builds do not show the browser/app choice');
 fs.writeFileSync(path.join(root,'validation/email-confirmation.json'),JSON.stringify({checks,engine:'Chromium; actual app pages with synthetic authentication responses',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
