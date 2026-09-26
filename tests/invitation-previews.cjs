const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'join.html'),'utf8'),dom=new JSDOM(html),d=dom.window.document;
assert.ok(Buffer.byteLength(html)<1000000,'Preview page must stay below Apple’s 1 MB limit');
assert.equal(d.querySelector('meta[property="og:site_name"]').content,'Wrestling Manager');
assert.equal(d.querySelector('meta[property="og:title"]').content,'Wrestling Manager invitation');
assert.match(d.querySelector('meta[property="og:image"]').content,/^https:\/\/theteammanager\.app\/assets\/wrestling-manager-icon\.png$/);
assert.ok(fs.statSync(path.join(root,'assets/wrestling-manager-icon.png')).size<10000000);
assert.equal(d.querySelector('meta[name="referrer"]').content,'no-referrer');
assert.equal(d.querySelectorAll('script[src]').length,0);
assert.equal(d.querySelectorAll('meta[http-equiv="refresh"]').length,0);
console.log('PASS Lightweight static preview supplies app name and existing logo without authentication');
const script=d.querySelector('script').textContent;
const base='https://theteammanager.app/';
const legacyBase='https://meleman35.github.io/wrestling-weight-manager-public/';
for(const routeBase of [base,legacyBase])for(const suffix of ['?invite=WMO-'+ 'a'.repeat(64),'?invite=WMM-private-token','?invite=WMWA-private-token','?invite=WMWG-private-token','?join=TEAM-42','#family-invite=private-family-token','?invite=WMO-private&redirect=https%3A%2F%2Fexample.test%2Fevil']){
 const url=new URL('join.html'+suffix,routeBase);let redirected;
 vm.runInNewContext(script,{URL,document:d,window:{location:{href:url.href,search:url.search,hash:url.hash,replace:value=>{redirected=value}}}});
 const dest=new URL(redirected);assert.equal(dest.origin,url.origin);assert.equal(dest.pathname,new URL(routeBase).pathname);
 assert.equal(dest.search,url.search);assert.equal(dest.hash,url.hash);assert.equal(d.getElementById('openInvitation').href,redirected);
}
console.log('PASS Fourteen branded and legacy invitation/query/hash routes preserve private links and stay on the app origin');
vm.runInNewContext(script,{URL,document:d,window:{location:{href:base+'join.html?invite=WMO-private',search:'?invite=WMO-private',hash:'',replace:()=>{throw Error('blocked')}}}});
assert.match(d.getElementById('openInvitation').href,/\?invite=WMO-private$/);
assert.match(d.getElementById('joinStatus').textContent,/Tap below/);
console.log('PASS Blocked automatic navigation retains a working invitation button');
const app=fs.readFileSync(path.join(root,'index.html'),'utf8');
const helpers=app.slice(app.indexOf('const JOIN_PUBLIC_BASE_042'),app.indexOf('function makeQr'));
for(const href of [base, legacyBase, 'file:///app/index.html', 'capacitor://localhost/index.html']){
 const context={URL,location:new URL(href)};vm.createContext(context);vm.runInContext(helpers,context);
 assert.equal(context.inviteUrl('WMO-test'),base+'join.html?invite=WMO-test');
 assert.equal(context.teamJoinUrl('TEAM-test'),base+'join.html?join=TEAM-test');
}
console.log('PASS Web and native link helpers generate public branded-entry URLs');
dom.window.close();
