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
  async function page(query = '', width = 390) {
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
    await p.goto('https://wm.example.test/' + query, {waitUntil: 'domcontentloaded'});
    await p.waitForFunction(() => typeof WMOnboarding !== 'undefined' && !accountRefreshFlight);
    return {p, context, errors};
  }
  try {
    const regular = await page();
    const p = regular.p;
    assert.equal(await p.locator('#signUpBtn').count(), 1);
    assert.equal(await p.locator('#signUpBtn').isVisible(), true);
    assert.match(await p.locator('.auth-create-account').innerText(), /does not create an account/);
    assert.equal(await p.locator('#teamSignInNotice').isVisible(), false);
    await p.locator('#signUpBtn').click();
    await p.waitForSelector('#signUpSheet:not(.hidden)');
    assert.equal(await p.locator('#createPersonalAccountBtn').isDisabled(), true);
    assert.equal(await p.locator('[data-signup-role]').count(), 3);
    await p.locator('#signUpSheet [data-close-sheet]').click();
    pass('New-account prompt opens the existing role-based signup without creating an account');

    for (const width of [320, 390, 1024]) {
      await p.setViewportSize({width, height: 844});
      for (const team of [false, true]) {
        await p.locator(team ? '#teamSignInTab' : '#personalSignInTab').click();
        assert.equal(await p.locator('#signUpBtn').isVisible(), true);
        assert.equal(await p.locator('#teamSignInNotice').isVisible(), team);
        assert.equal(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
        assert.equal(await p.evaluate(() => document.getElementById('signUpBtn').getBoundingClientRect().top < document.getElementById('personalSignInTab').getBoundingClientRect().top), true);
        assert.equal(await p.locator('#teamSignInCode').isDisabled(), !team);
        assert.equal(await p.locator('#email').isDisabled(), team);
      }
    }
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
    await j.locator('#teamSignInTab').click();
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
    await j.locator('#signUpEmail').fill('athlete@example.test');
    await j.locator('#signUpPassword').fill('example-personal-password');
    await j.locator('#createPersonalAccountBtn').click();
    await j.waitForSelector('#confirmationNotice:not(.hidden)');
    const saved = await j.evaluate(() => ({calls: fixture.signupCalls, memory: JSON.parse(localStorage.getItem('wm.onboarding.v1'))}));
    assert.equal(saved.calls.length, 1);
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
    await j.locator('#signInBtn').click();
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
    await staff.p.locator('#teamSignInTab').click();
    await staff.p.locator('#signUpBtn').click();
    assert.equal(await staff.p.locator('[data-signup-role="team_leader"]').getAttribute('aria-pressed'), 'true');
    assert.equal(await staff.p.evaluate(() => pendingInviteToken), 'WMM-EXAMPLE-PRIVATE');
    assert.deepEqual(await staff.p.evaluate(() => fixture.writes), []);
    assert.deepEqual(staff.errors, []);
    await staff.context.close();
    pass('Private staff invitation keeps its token and existing starting role without granting access');

    const native = await page();
    await native.p.locator('#teamSignInTab').click();
    await native.p.evaluate(() => wrestlingManagerHandleAuthURL('wrestlingmanager://join?code=WMW-NATIVE-EXAMPLE'));
    await native.p.locator('#signUpBtn').click();
    assert.equal(await native.p.evaluate(() => pendingJoinCode), 'WMW-NATIVE-EXAMPLE');
    assert.equal(await native.p.locator('#personalSignInTab').getAttribute('aria-pressed'), 'true');
    assert.deepEqual(native.errors, []);
    await native.context.close();
    pass('Existing native join-link handler preserves its code through signup');

    fs.writeFileSync(path.join(root, 'validation/login-onboarding-browser.json'), JSON.stringify({release: '0.20.37', engine: 'Isolated Chromium with complete HTML and mocked backend; no real accounts or messages', passed: checks.length, checks}, null, 2) + '\n');
  } finally { await browser.close(); }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
