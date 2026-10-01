"""Refresh beta support/privacy copy and embedded views, without touching access.
Run without arguments to generate; --check verifies exact synchronized output.
This is an interim disclosure correction, not a finalized release privacy policy.
"""
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
CHECK='--check' in sys.argv

def replace_once(text, old, new):
    if new in text:
        assert text.count(new)==1 and old not in text.replace(new,'',1), 'Mixed old/new disclosure text'
        return text
    assert text.count(old)==1, 'Unexpected source near '+old[:90]
    return text.replace(old,new,1)

def write(path, text):
    target=ROOT/path
    if CHECK:
        assert target.read_text()==text, 'Generated information differs: '+path
    else:
        target.write_text(text)

privacy=(ROOT/'privacy.html').read_text()
changes=[
 ('<aside class="wm-doc-note"><strong>Beta information · September 20, 2026</strong><p>The final privacy policy and complete account-deletion process are still being prepared before the athlete pilot. This page explains current handling and how to contact us with a privacy question.</p></aside>',
  '<aside class="wm-doc-note"><strong>Beta privacy information · Updated October 1, 2026</strong><p>This page describes current beta handling. Final release disclosures, retention schedules and younger-athlete enrollment safeguards remain under review. Native account deletion is in a limited, build-dependent test pilot; it is not generally enabled.</p></aside>\n<p><strong>Product company:</strong> Mele Sports Technologies LLC · The Team Manager / Wrestling Manager. For privacy questions, contact <a href="mailto:support@theteammanager.app">support@theteammanager.app</a>.</p>'),
 ('<li><strong>GitHub Pages and jsDelivr</strong> deliver the web app and its client library. Requests to hosting services include technical information such as an IP address.</li>',
  '<li><strong>GitHub Pages</strong> delivers the web app, including its bundled client library. Requests to hosting services include technical information such as an IP address. This disclosure does not establish the retention period of hosting logs.</li>'),
 ('<p>SMS is not ready for this pilot. The currently registered push devices use Apple notifications. We will update this information when additional communication services are enabled.</p>',
  '<p>SMS delivery is not an advertised release-ready feature in this beta. The provider inventory must be reviewed before additional communication services are enabled.</p>'),
 ('<p>Camera, photo, Bluetooth and notification permissions support the features you choose to use. You can change device permissions in device Settings. The app also keeps sign-in preferences, settings and unfinished match recovery information locally on your device.</p>',
  '<p>Camera, photo, Bluetooth and notification permissions support the features you choose to use. You can change device permissions in device Settings. The app also keeps sign-in preferences, settings and unfinished match recovery information locally on your device. Some supported features keep account-scoped drafts, queued work or pilot recordings on the device. Not every feature works offline; clinical records and adult-reviewer history are not available as an offline cache. A saved or exported device copy is separate from any server record.</p>'),
 ('<p>A complete in-app account-deletion workflow is not available yet. Contact support with a data request so its identity, scope and any shared family records can be reviewed. Sending an email does not mean deletion has been completed. Retention periods and the final deletion process must be settled before the athlete pilot.</p>',
  '<p>Account deletion is available for limited native testing in compatible builds and specifically enrolled disposable accounts. General native activation remains restricted while interruption recovery, local media and preservation of other accounts are checked. Available account-deletion controls are in <strong>My Account → Account deletion</strong>. An accepted interrupted request must resume its original request; a failed sign-in alone is not proof of completed cleanup.</p>\n<p>For an access, correction or deletion request that is not available through your current controls, contact support so the requesting person, authority and scope can be verified. Sending an email does not complete deletion. The final release must provide a tested in-app initiation path for account holders, clear completion timing, and accurate retention details; this beta contact route is not a substitute for that work.</p>\n<p>A season or membership period is not a retention schedule. Purpose-specific retention periods for records, files, logs and backups, and any legally required exceptions, remain to be finalized. We do not claim that all records are erased immediately or that shared team records are automatically exempt. Copies already exported to Photos or Files, other devices, and information previously viewed by recipients require separate handling.</p>'),
 ('<h2>Your choices and questions</h2>',
  '<h2>Younger athletes and guardian authority</h2>\n<p>Family links, profile approvals, messaging choices and health-photo choices are separate permissions. An adult reviewer is not automatically a legal guardian, and an App Store age rating does not establish consent to collect a child’s information. Existing parent or trainer submission tools do not by themselves establish the required younger-child consent process. Parent-led notice, verification, review, withdrawal and child-data handling must be completed before collecting personal information from younger children through the pilot. Use fictional records for younger-athlete tests until the required process is complete.</p>\n<h2>Your choices and questions</h2>'),
]
for old,new in changes: privacy=replace_once(privacy,old,new)

support=(ROOT/'support.html').read_text()
support=replace_once(support,
 '<p>Include what you were trying to do, what happened, your device model and the app build shown in Account &amp; Team. A screenshot can help; crop out other people\'s information.</p>',
 '<p>Include what you were trying to do, what happened, your device model, iOS/iPadOS version, whether you used the installed app or Safari, and the web Build shown in the app. Include the installed Apple version/build separately when known; the web Build and TestFlight build are different. A cropped screenshot of the error can help, without other people’s information.</p>\n<p>Product company: <strong>Mele Sports Technologies LLC</strong> · The Team Manager / Wrestling Manager. This page was updated October 1, 2026.</p>')
support=replace_once(support,'<h2>Scale and weight checks</h2>',
 '''<h2>Finding the right workspace</h2>
<p>Assigned trainers can use <strong>Toolbox → Trainer Dashboard</strong> for their selected team. A trainer must accept the responsibility before seeing the care overview. A missing dashboard can reflect an unaccepted or removed assignment; being a coach, Team Mom or organization leader does not automatically grant private care access.</p>
<p>Assigned adult conversation reviewers accept from <strong>Messages → Conversation review · approved adults</strong>. Reviewer-only access is read-only and creates no routine reviewer notifications. Normal parent or conversation-participant notifications are separate.</p>
<p>Specifically authorized personal logins can open <strong>More / Toolbox → Creator Dashboard</strong> without signing out. <strong>Return to Team</strong> closes that workspace. This does not give other team members Creator access.</p>
<h2>Demonstrations and paid features</h2>
<p><strong>Explore Role Views · Demo</strong> uses fictional people and representative screens; it never opens a real person’s account. Practice Plans currently shows a paid-feature sample while verified billing access is unfinished. Creator discount drafts cannot be redeemed, and saving a trial preference does not start a trial or charge anyone.</p>
<h2>Connection and saved work</h2>
<p>Reconnect before reopening private health or reviewer views. Offline support varies by feature; do not assume a queued message was delivered or that a local recording was uploaded. For recovery problems, report the exact status rather than submitting the same operation again.</p>
<p><strong>Do not uninstall, clear app/site data or remove saved credentials as a first troubleshooting step.</strong> Unsynced work and device recordings may be lost. Preserve your current installation and available exports while support checks the issue. A web update does not install new Apple-native functionality.</p>
<h2>Scale and weight checks</h2>''')
support=replace_once(support,'<h2>Privacy and data requests</h2>',
 '''<h2>Account deletion during the beta</h2>
<p>Look in <strong>My Account → Account deletion</strong> for the controls available to your account. Native deletion remains a limited pilot for compatible builds and specifically enrolled test accounts. Do not create a new request to recover an already accepted interrupted request; resume the original request and wait for its actual completion status.</p>
<p>Signing out, leaving a team or uninstalling is not account deletion. Contact support when the available controls do not cover your request or the completion status is unclear. Deleting your own guardian account and requesting removal of a child’s information are different requests. No deletion is performed merely by opening this help page or sending an email.</p>
<h2>Privacy and data requests</h2>''')
index=(ROOT/'index.html').read_text()
for kind,page in [('Support',support),('Privacy',privacy)]:
    body=re.search(r'</nav>([\s\S]*?)<footer class="wm-doc-footer">',page)
    assert body, 'Missing page content: '+kind
    pattern=r'(<template id="wm'+kind+r'Template">)[\s\S]*?(</template>)'
    assert len(re.findall(pattern,index))==1,'Unexpected template: '+kind
    index=re.sub(pattern,lambda m:m[1]+body[1]+m[2],index)
index=index.replace('0.20.114','0.20.115').replace(
 'Shared Creator dashboard with personal-login access and fictional role previews.',
 'Updated beta privacy and support guidance; native and billing access unchanged.')
worker=(ROOT/'sw.js').read_text().replace('0.20.114','0.20.115')
p='scripts/prepare-linked-creator-release.py'
release=(ROOT/p).read_text()
release=replace_once(release,"assert '0.20.113' in s or '0.20.114' in s,'Unexpected release version: '+path",
                    "assert any(v in s for v in ('0.20.113','0.20.114','0.20.115')),'Unexpected release version: '+path")
for path,text in [('privacy.html',privacy),('support.html',support),('index.html',index),('sw.js',worker),(p,release)]:write(path,text)
print('PASS Paired v0.20.115 beta support/privacy pages and in-app templates; no authorization changes')
