const fs = require('fs');
const path = require('path');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const fixture = fs.readFileSync(path.join(__dirname, 'browser-fixture.js'), 'utf8');

async function main() {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM_EXECUTABLE_PATH, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
  const checks = [];
  const pass = label => { checks.push(label); console.log('PASS', label); };
  async function page(query = '', width = 390, native = null, autoOff = false) {
    const context = await browser.newContext({viewport: {width, height: 844}});
    const p = await context.newPage();
    const errors = [];
    p.on('pageerror', e => errors.push(e.message));
    await p.route('**/*', route => {
      const req = route.request();
      if (req.isNavigationRequest() && new URL(req.url()).hostname === 'wm.example.test')
        return route.fulfill({contentType: 'text/html', body: html});
      if (req.url().includes('supabase-js')) return route.fulfill({contentType: 'text/javascript', body: '/* isolated fixture */'});
      return route.abort();
    });
    await context.addInitScript({content: fixture + '\nsessionStorage.setItem("wm-app-open-attempt","1"); fixture.confirmation=true;'});
    if (native) await context.addInitScript(({state, autoOff}) => {
      if (autoOff && localStorage.getItem('wm_biometric_auto') === null) localStorage.setItem('wm_biometric_auto', 'false');
      window.biometricCommands = [];
      window.webkit = {messageHandlers: {biometricLogin: {postMessage(body) {
        biometricCommands.push({...body});
        if (body.command === 'status') queueMicrotask(() => window.wrestlingManagerBiometricLoginResult?.({event:'status', available:true, label:'Face ID', ...state}));
        if (body.command === 'read') queueMicrotask(() => window.wrestlingManagerBiometricLoginResult?.({requestId:body.requestId, ok:false, message:'Face ID cancelled. Use your password.'}));
      }}}};
    }, {state:native, autoOff});
    await p.goto('https://wm.example.test/' + query, {waitUntil: 'domcontentloaded'});
    await p.waitForFunction(() => typeof WMOnboarding !== 'undefined' && !accountRefreshFlight);
    return {p, context, errors};
  }
  async function mode(p, team) {
    if (!await p.locator('#authMoreOptions').evaluate(x=>x.open)) await p.locator('#authMoreOptions > summary').click();
    await p.locator(team ? '#teamSignInTab' : '#personalSignInTab').click();
  }
  try {
    const regular = await page();
    const p = regular.p;
    assert.equal(await p.locator('#signUpBtn').count(), 1);
    assert.equal(await p.locator('#signUpBtn').isVisible(), true);
    assert.equal(await p.locator('#signUpBtn').innerText(), 'Create account');
    assert.equal(await p.locator('#authMoreOptions').evaluate(x=>x.open), false);
    assert.equal(await p.locator('#quickSignInArea').isVisible(), false);
    assert.equal(await p.locator('#emailSignInLink').isVisible(), false);
    assert.equal(await p.evaluate(()=>document.getElementById('signUpBtn').getBoundingClientRect().top > document.getElementById('signInBtn').getBoundingClientRect().bottom), true);
    assert.equal(await p.evaluate(()=>document.getElementById('authView').getBoundingClientRect().bottom < innerHeight), true);
    await p.screenshot({path:path.join(root,'validation/login-onboarding-phone.png'), fullPage:true});
    assert.equal(await p.locator('#teamSignInNotice').isVisible(), false);
    await p.locator('#signUpBtn').click();
    await p.waitForSelector('#signUpSheet:not(.hidden)');
    assert.equal(await p.locator('#createPersonalAccountBtn').isDisabled(), true);
    assert.equal(await p.locator('[data-signup-role]').count(), 3);
    assert.equal(await p.locator('#signUpSheet').evaluate(x=>Math.round(x.getBoundingClientRect().top)), 0);
    assert.equal(await p.evaluate(()=>document.activeElement.id), 'signUpTitle');
    await p.screenshot({path:path.join(root,'validation/signup-phone.png'), fullPage:true});
    await p.locator('#signUpSheet [data-close-sheet]').click();
    pass('New-account prompt opens the existing role-based signup without creating an account');

    for (const width of [320, 390, 1024]) {
      await p.setViewportSize({width, height: 844});
      for (const team of [false, true]) {
        await mode(p,team);
        assert.equal(await p.locator('#signUpBtn').isVisible(), true);
        assert.equal(await p.locator('#teamSignInNotice').isVisible(), team);
        assert.equal(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
        assert.equal(await p.locator('#teamSignInCode').isDisabled(), !team);
        assert.equal(await p.locator('#email').isDisabled(), team);
      }
    }
    await mode(p,false);
    await p.setViewportSize({width: 390, height: 844});
    await p.evaluate(() => window.scrollTo(0, 0));
    await p.screenshot({path: path.join(root, 'validation/login-onboarding-phone.png'), fullPage: true});
    assert.deepEqual(regular.errors, []);
    await regular.context.close();
    pass('Signup remains visible in both login modes at 320px, 390px and 1024px without overflow');

    const joining = await page('?join=WMW-EXAMPLE-TEAM');
    const j = joining.p;
    const initial = await j.evaluate(() => JSON.parse(localStorage.getItem('wm.onboarding.v1')));
    assert.equal(initial.join, 'WMW-EXAMPLE-TEAM');
    await mode(j,true);
    await j.locator('#teamSignInCode').fill('SHARED-DEVICE');
    await j.locator('#teamSignInUsername').fill('shared-device-login');
    await j.locator('#teamSignInPassword').fill('not-a-personal-password');
    await j.locator('#signUpBtn').click();
    await j.waitForSelector('#signUpSheet:not(.hidden)');
    assert.equal(await j.locator('#personalSignInTab').getAttribute('aria-pressed'), 'true');
    assert.equal(await j.locator('#signUpEmail').inputValue(), '');
    assert.equal(await j.locator('#signUpPassword').inputValue(), '');
    assert.equal(await j.evaluate(() => pendingJoinCode), initial.join);
    pass('Signup from Team Login switches to Personal Login without copying shared credentials or replacing the invitation');

    await j.locator('[data-signup-role="athlete"]').click();
    await j.locator('#signUpFirstName').fill('Real');await j.locator('#signUpLastName').fill('Athlete');
    await j.locator('#signUpEmail').fill('athlete@example.test');
    await j.locator('#signUpPassword').fill('example-personal-password');
    await j.locator('#createPersonalAccountBtn').click();
    await j.waitForSelector('#confirmationNotice:not(.hidden)');
    const saved = await j.evaluate(() => ({calls: fixture.signupCalls, memory: JSON.parse(localStorage.getItem('wm.onboarding.v1'))}));
    assert.equal(saved.calls.length, 1);
    assert.equal(saved.calls[0].options.data.full_name,'Real Athlete');
    assert.equal(saved.calls[0].options.data.wm_onboarding_role, 'athlete');
    assert.equal(saved.calls[0].options.data.wm_onboarding_team.code, initial.join);
    assert.equal(saved.memory.join, initial.join);
    assert.equal(saved.memory.awaitingEmail, 'athlete@example.test');
    assert.equal(await j.locator('#email').isDisabled(), false);
    assert.equal(await j.locator('#teamSignInFields').isVisible(), false);
    pass('Account creation retains the team link through the email-confirmation screen');

    await j.reload({waitUntil: 'domcontentloaded'});
    await j.waitForSelector('#confirmationNotice:not(.hidden)');
    assert.equal(await j.evaluate(() => pendingJoinCode), initial.join);
    await j.evaluate(() => {
      fixture.signInCalls = [];
      client.auth.signInWithPassword = async input => {
        fixture.signInCalls.push(input);
        return {error: {message: 'Example sign-in response'}};
      };
    });
    await j.locator('#email').fill('athlete@example.test');
    await j.locator('#password').fill('example-personal-password');
    await j.locator('#email').focus();
    await j.keyboard.press('Enter');assert.equal(await j.evaluate(()=>document.activeElement.id),'password');
    await j.keyboard.press('Tab');assert.equal(await j.evaluate(()=>document.activeElement.id),'forgotPasswordBtn');
    await j.keyboard.press('Shift+Tab');assert.equal(await j.evaluate(()=>document.activeElement.id),'password');
    await j.keyboard.press('Enter');
    await j.waitForFunction(()=>fixture.signInCalls.length===1);
    assert.deepEqual(await j.evaluate(() => fixture.signInCalls), [{email: 'athlete@example.test', password: 'example-personal-password'}]);
    await j.evaluate(() => {
      client.auth.signInWithPassword = async input => {
        fixture.session = {user: {id: 'example-athlete', email: input.email, user_metadata: {wm_onboarding_role: 'athlete'}}};
        return {data: {session: fixture.session}, error: null};
      };
    });
    await j.locator('#signInBtn').click();
    await j.waitForSelector('#joinRequestSheet:not(.hidden)');
    assert.equal(await j.evaluate(() => joinPreview.team_id), 'team-a');
    const previewCalls = await j.evaluate(() => fixture.calls.filter(c => c.name === 'preview_team_join_code'));
    assert.ok(JSON.stringify(previewCalls).includes(initial.join));
    assert.deepEqual(await j.evaluate(() => fixture.writes), []);
    pass('Successful personal sign-in opens the invited team join form without granting membership');
    assert.deepEqual(joining.errors, []);
    await joining.context.close();
    pass('Reload retains the invitation and the existing personal sign-in form still submits correctly');

    const staff = await page('?invite=WMM-EXAMPLE-PRIVATE');
    await mode(staff.p,true);
    await staff.p.locator('#signUpBtn').click();
    assert.equal(await staff.p.locator('[data-signup-role="team_leader"]').getAttribute('aria-pressed'), 'true');
    assert.equal(await staff.p.evaluate(() => pendingInviteToken), 'WMM-EXAMPLE-PRIVATE');
    assert.deepEqual(await staff.p.evaluate(() => fixture.writes), []);
    assert.deepEqual(staff.errors, []);
    await staff.context.close();
    pass('Private staff invitation keeps its token and existing starting role without granting access');

    const native = await page();
    await mode(native.p,true);
    await native.p.evaluate(() => wrestlingManagerHandleAuthURL('wrestlingmanager://join?code=WMW-NATIVE-EXAMPLE'));
    await native.p.locator('#signUpBtn').click();
    assert.equal(await native.p.evaluate(() => pendingJoinCode), 'WMW-NATIVE-EXAMPLE');
    assert.equal(await native.p.locator('#personalSignInTab').getAttribute('aria-pressed'), 'true');
    assert.deepEqual(native.errors, []);
    await native.context.close();
    pass('Existing native join-link handler preserves its code through signup');

    const face = await page('',390,{saved:true},true);
    const f=face.p;
    assert.equal(await f.locator('#quickSignInArea').isVisible(),true);
    assert.equal(await f.locator('#quickAutoSignIn').isChecked(),false);
    assert.equal(await f.evaluate(()=>biometricCommands.filter(x=>x.command==='read').length),0);
    await f.locator('#quickSignInBtn').click();
    await f.waitForFunction(()=>biometricCommands.filter(x=>x.command==='read').length===1);
    await f.waitForFunction(()=>!WMQuickSignIn.busy());
    assert.match(await f.locator('#quickSignInStatus').innerText(),/cancelled/);
    assert.equal(await f.locator('#password').isEnabled(),true);
    await f.locator('#quickAutoSignIn').check();
    await f.waitForFunction(()=>biometricCommands.filter(x=>x.command==='read').length===2);
    await f.waitForFunction(()=>!WMQuickSignIn.busy());
    await f.locator('#quickAutoSignIn').uncheck();
    await f.reload({waitUntil:'domcontentloaded'});
    await f.waitForFunction(()=>window.wrestlingManagerSignInReady);
    assert.equal(await f.evaluate(()=>biometricCommands.filter(x=>x.command==='read').length),0);
    assert.equal(await f.locator('#quickAutoSignIn').isChecked(),false);
    assert.equal(await f.evaluate(()=>document.getElementById('signUpBtn').getBoundingClientRect().bottom<innerHeight),true);
    await f.screenshot({path:path.join(root,'validation/login-face-id-phone.png'),fullPage:true});
    await f.locator('#signUpBtn').click();
    await f.evaluate(()=>{WMQuickSignIn.background();WMQuickSignIn.resume();});
    assert.equal(await f.evaluate(()=>biometricCommands.filter(x=>x.command==='read').length),0);
    assert.deepEqual(face.errors,[]);await face.context.close();
    pass('Face ID remains available manually, cancellation restores password login, and the automatic switch persists across reloads');

    const automatic = await page('',390,{saved:true});
    await automatic.p.waitForFunction(()=>biometricCommands.filter(x=>x.command==='read').length===1);
    await automatic.p.waitForFunction(()=>!WMQuickSignIn.busy());
    await automatic.p.evaluate(()=>{WMQuickSignIn.status();WMQuickSignIn.ready();});
    assert.equal(await automatic.p.evaluate(()=>biometricCommands.filter(x=>x.command==='read').length),1);
    await automatic.p.locator('#signUpBtn').click();
    await automatic.p.evaluate(()=>{WMQuickSignIn.background();WMQuickSignIn.resume();});
    assert.equal(await automatic.p.evaluate(()=>biometricCommands.filter(x=>x.command==='read').length),1);
    assert.deepEqual(automatic.errors,[]);await automatic.context.close();
    pass('Existing enrolled Face ID prompts once and does not interrupt signup or loop after cancellation');

    const enrolling = await page('',390,{saved:false});
    const e=enrolling.p;
    assert.equal(await e.locator('#quickAutoSignIn').isDisabled(),true);
    await e.evaluate(()=>{fixture.confirmation=false;const rpc=client.rpc;client.rpc=(name,args)=>name==='get_operations'&&args?.p_request?.action==='context'?Promise.resolve({data:[],error:null}):rpc(name,args);});
    await e.locator('#signUpBtn').click();await e.locator('[data-signup-role="athlete"]').click();
    await e.locator('#signUpFirstName').fill('Test');await e.locator('#signUpLastName').fill('Athlete');
    await e.locator('#signUpEmail').fill('new@example.test');await e.locator('#signUpPassword').fill('synthetic-password');
    await e.locator('#createPersonalAccountBtn').click();
    await e.waitForSelector('#setupView:not(.hidden)');await e.waitForSelector('#quickSetupOffer:not([hidden])');
    assert.equal(await e.locator('#setupJoinCard').isVisible(),true);
    await e.locator('#quickSetupOfferBtn').click();
    await e.waitForSelector('#securitySheet:not(.hidden)');
    assert.equal(await e.evaluate(()=>document.activeElement.id),'quickSetupPassword');
    assert.equal(await e.evaluate(()=>biometricCommands.filter(x=>x.command==='enroll').length),0);
    assert.deepEqual(enrolling.errors,[]);await enrolling.context.close();
    pass('New native accounts continue to team setup with an optional Face ID setup prompt; enrollment requires explicit action');

    fs.writeFileSync(path.join(root, 'validation/login-onboarding-browser.json'), JSON.stringify({release: '0.20.101', engine: 'Isolated Chromium with complete HTML and mocked backend; no real accounts or messages', passed: checks.length, checks}, null, 2) + '\n');
  } finally { await browser.close(); }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
