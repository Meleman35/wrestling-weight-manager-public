const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),passed=[];
const pass=s=>{passed.push(s);console.log('PASS',s);};
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const ctx=await browser.newContext({viewport:{width:390,height:844}}),p=await ctx.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));
 await ctx.addInitScript({content:fs.readFileSync(path.join(__dirname,'browser-fixture.js'),'utf8')});
 await p.route('**/*',r=>r.request().isNavigationRequest()?r.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(root,'index.html'),'utf8')}):r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:''}):r.abort());
 await p.goto('https://wm.test/');await p.waitForFunction(()=>window.wrestlingManagerSignInReady===true);
 await p.evaluate(()=>{
   session=fixture.session={user:{id:'test-coach'},access_token:'synthetic'};managedLogin=null;
   show('authView',false);show('appView',false);show('setupView',true);show('appLockOverlay',false);document.getElementById('setupChoices').open=true;
   fixture.weightCalls=[];fixture.teamNumber=0;fixture.ruleDelay=0;
   client.from=name=>{const filters={};return {select(){return this;},eq(k,v){filters[k]=v;return this;},in(){return this;},order(){return this;},then(resolve){resolve({data:name==='organization_memberships'?[{organization_id:'org-existing',role:'organization_admin'}]:name==='organizations'?[{id:'org-existing',name:'Example Organization'}]:[],error:null});},async maybeSingle(){
     const f={...filters},delay=fixture.ruleDelay;await new Promise(r=>setTimeout(r,delay));
     return {data:name==='state_high_school_weight_rules'&&f.state_code==='WY'&&f.season_name==='2026-27'?{state_code:'WY',season_name:'2026-27',gender_scope:f.gender_scope,association_name:'Synthetic State Association',weights:WEIGHT_CLASS_PRESETS[f.gender_scope==='boys'?'nfhs_boys_14':'nfhs_girls_14'].weights}:null,error:null};
   }};};
   client.rpc=async(name,args)=>{
     fixture.weightCalls.push({name,args:JSON.parse(JSON.stringify(args))});
     if(name==='bootstrap_wrestling_organization'){fixture.teamNumber++;return {data:[{organization_id:'org-created',team_id:'team-'+fixture.teamNumber,season_id:'season-'+fixture.teamNumber}],error:null};}
     if(name==='create_team_in_organization_v4'){fixture.teamNumber++;return {data:[{team_id:'team-'+fixture.teamNumber,season_id:'season-'+fixture.teamNumber}],error:null};}
     if(fixture.failWeights&&name==='apply_team_weight_class_preset_v2')return {data:null,error:{message:'Synthetic save interrupted'}};
     return {data:{applied:true},error:null};
   };
   refresh=async()=>{fixture.refreshed=true;};
   window.WMOperations={open:async()=>{},close:()=>{}};
 });
 // The first-team flow is the path that previously never saved a school level or weight setup.
 await p.locator('#orgName').fill('Example School');await p.locator('#teamName').fill('Example Girls');
 await p.locator('#bootstrapTeamBtn').click();assert.match(await p.locator('#bootstrapTeamStatus').innerText(),/program level/);assert.equal(await p.evaluate(()=>fixture.teamNumber),0);
 await p.locator('#setupTeamLevels input[value=high_school]').check();await p.locator('#setupTeamState').selectOption('WY');await p.locator('#seasonName').fill('2026-27');await p.locator('#seasonName').dispatchEvent('change');
 await p.waitForFunction(()=>document.getElementById('setupWeightClassList').children.length===14);
 assert.equal(await p.locator('#setupWeightClassPreset').inputValue(),'state_high_school');assert.match(await p.locator('#setupWeightClassList').innerText(),/100/);assert.match(await p.locator('#setupWeightClassList').innerText(),/235/);
 assert.deepEqual(await p.locator('#setupWeightClassPreset option').evaluateAll(os=>os.map(o=>o.value)),['state_high_school','nfhs_girls_12','nfhs_girls_13','nfhs_girls_14','custom']);
 pass('First-team setup exposes High School, state, girls’ presets and a 14-class preview before saving');
 for(const count of [12,13,14]){await p.locator('#setupWeightClassPreset').selectOption('nfhs_girls_'+count);assert.equal(await p.locator('#setupWeightClassList > span').count(),count);}
 await p.evaluate(()=>fixture.ruleDelay=150);
 await p.locator('#genderScope').selectOption('boys');await p.locator('#genderScope').selectOption('girls');await p.locator('#genderScope').selectOption('boys');
 await p.waitForFunction(()=>document.getElementById('setupWeightClassNote').textContent.includes('Boys.'));
 assert.match(await p.locator('#setupWeightClassList').innerText(),/285/);assert(!await p.locator('#setupWeightClassPreset option[value=nfhs_girls_14]').count());
 pass('Switching gender replaces the options and rejects stale state-rule responses');
 await p.locator('#setupWeightClassPreset').selectOption('nfhs_boys_14');await p.evaluate(()=>fixture.failWeights=true);
 await p.locator('#bootstrapTeamBtn').click();await p.waitForFunction(()=>!bootstrapTeamSaving);
 assert.match(await p.locator('#bootstrapTeamStatus').innerText(),/team was created.*Finish Team Setup/);assert.equal(await p.locator('#bootstrapTeamBtn').innerText(),'Finish Team Setup');
 const settings=await p.evaluate(()=>fixture.weightCalls.find(c=>c.name==='update_team_settings_v3').args);
 assert.deepEqual(settings.p_service_levels,['high_school']);assert.equal(settings.p_gender_scope,'boys');assert.equal(settings.p_state_code,'WY');
 await p.evaluate(()=>fixture.failWeights=false);await p.locator('#bootstrapTeamBtn').click();await p.waitForFunction(()=>!bootstrapTeamSaving);
 assert.equal(await p.evaluate(()=>fixture.teamNumber),1);
 assert.equal(await p.evaluate(()=>fixture.weightCalls.filter(c=>c.name==='apply_team_weight_class_preset_v2').at(-1).args.p_preset),'nfhs_boys_14');
 pass('First-team creation saves level, state and selected preset; interrupted weight save retries without duplicating the team');
 // Existing-organization path and state with no verified rule.
 await p.evaluate(()=>openCreateTeam('org-existing'));await p.locator('#newTeamName').fill('Example Girls HS');await p.locator('#newTeamLevels input[value=high_school]').check();await p.locator('#newTeamState').selectOption('CA');
 await p.waitForFunction(()=>!creationWeightSetups.newTeam.loading);
 assert.match(await p.locator('#newTeamWeightClassNote').innerText(),/No verified/);
 await p.locator('#saveNewTeamBtn').click();await p.waitForFunction(()=>!teamCreationSaving);assert.equal(await p.evaluate(()=>fixture.teamNumber),1);
 await p.locator('#newTeamWeightClassPreset').selectOption('nfhs_girls_14');
 await p.locator('#newTeamWeightClassPreset').scrollIntoViewIfNeeded();
 for(const width of [320,390]){await p.setViewportSize({width,height:844});assert(await p.evaluate(()=>document.getElementById('createTeamSheet').scrollWidth<=document.getElementById('createTeamSheet').clientWidth+1));}
 fs.mkdirSync(path.join(root,'validation'),{recursive:true});await p.screenshot({path:path.join(root,'validation/team-creation-weights-phone.png')});
 await p.locator('#saveNewTeamBtn').click();await p.waitForFunction(()=>!teamCreationSaving);
 const calls=await p.evaluate(()=>fixture.weightCalls);
 const create=calls.find(c=>c.name==='create_team_in_organization_v4').args;
 assert.equal(create.p_gender_scope,'girls');assert.equal(create.p_state_code,'CA');assert.deepEqual(create.p_service_levels,['high_school']);
 assert.equal(calls.filter(c=>c.name==='apply_team_weight_class_preset_v2').at(-1).args.p_preset,'nfhs_girls_14');
 pass('Additional teams save the chosen girls’ preset; missing state rules block guessing, and phone layout fits');
 await p.evaluate(()=>openCreateTeam('org-existing'));await p.locator('#newTeamName').fill('Example Coed Club');await p.locator('#newTeamType').selectOption('club');await p.locator('#newTeamGender').selectOption('coed');await p.locator('#newTeamLevels input[value=club]').check();
 assert.deepEqual(await p.locator('#newTeamWeightClassPreset option').evaluateAll(os=>os.map(o=>o.value)),['custom']);
 await p.locator('#newTeamWeightClassAdd').fill('95');await p.locator('#newTeamWeightClassAddBtn').click();await p.locator('#newTeamWeightClassAdd').fill('105');await p.locator('#newTeamWeightClassAdd').press('Enter');
 await p.locator('#saveNewTeamBtn').click();await p.waitForFunction(()=>!teamCreationSaving);
 assert.deepEqual(await p.evaluate(()=>fixture.weightCalls.filter(c=>c.name==='save_custom_team_weight_classes').at(-1).args.p_weights),[95,105]);
 pass('Coed/club creation preserves custom classes without assigning a boys’ or girls’ preset');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'validation/team-creation-weights.json'),JSON.stringify({passed,engine:'Chromium; actual app with synthetic API fixtures',nativeDeviceVerified:false},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
